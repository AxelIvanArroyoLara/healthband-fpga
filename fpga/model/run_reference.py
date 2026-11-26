"""Ejecuta el modelo de referencia sobre los estímulos y resume los resultados.

Lee fpga/stim/*.hex y escribe en fpga/evidence/reference/:
  <caso>_beats.csv    latidos detectados (muestra, intervalo)
  <caso>_1hz.csv      salidas cada segundo (bpm, ibi_ms, data_valid, quality)
  <caso>.svg          señal filtrada, umbral y latidos
  summary.md          tabla esperado vs. observado

Los CSV tienen el mismo formato que escribe tb_ppg_processor.v, de modo que
compare_rtl.py puede compararlos línea por línea.

Uso: python -I fpga/model/run_reference.py
"""

import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ppg_model as m  # noqa: E402

FPGA_DIR = Path(__file__).resolve().parent.parent
STIM_DIR = FPGA_DIR / "stim"
OUT_DIR = FPGA_DIR / "evidence" / "reference"
SETTLE_S = 8  # Segundos de estabilización antes de exigir error <= 2 BPM.


def read_stim(path):
    rows = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        word = int(line, 16)
        flags = word >> 32
        if flags & 0x80:
            break
        rows.append((word & 0xFFFF, (word >> 16) & 0xFFFF, flags))
    return rows


def read_truth(path):
    with open(path) as f:
        return [float(r["beat_time_s"]) for r in csv.DictReader(f)]


def true_bpm(beats, t):
    """BPM real a partir de los últimos 4 intervalos anteriores a t."""
    prev = [b for b in beats if b <= t]
    if len(prev) < 5:
        return None
    ivs = [b - a for a, b in zip(prev[-5:-1], prev[-4:])]
    return 60.0 / (sum(ivs) / len(ivs))


def run_case(rows):
    proc = m.PpgProcessor()
    beats, per_sec, trace = [], [], []
    for i, (ir, _red, flags) in enumerate(rows):
        interval = proc.slot(ir, dropped=bool(flags & 1), overflow=bool(flags & 2))
        if interval is not None:
            beats.append((i, interval))
        trace.append((proc.filt.sum >> m.AVG_LOG2 if proc.filt.primed else 0,
                      proc.det.env >> 1, interval is not None))
        if (i + 1) % m.SAMPLE_HZ == 0:
            per_sec.append(((i + 1) // m.SAMPLE_HZ, proc.calc.bpm, proc.calc.ibi_ms,
                            int(proc.data_valid), proc.quality))
    return beats, per_sec, trace


def write_csvs(name, beats, per_sec):
    with open(OUT_DIR / f"{name}_beats.csv", "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["sample", "interval"])
        w.writerows(beats)
    with open(OUT_DIR / f"{name}_1hz.csv", "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["t_s", "bpm", "ibi_ms", "data_valid", "quality"])
        w.writerows(per_sec)


def write_svg(name, rows, trace, title):
    """Gráfica simple en SVG (sin dependencias externas)."""
    width, height, pad = 1100, 360, 40
    ir = [r[0] for r in rows]
    filt = [t[0] for t in trace]
    thr = [t[1] for t in trace]
    n = len(rows)

    def poly(values, top, h, color):
        lo, hi = min(values), max(values)
        span = (hi - lo) or 1
        pts = " ".join(f"{pad + i * (width - 2 * pad) / n:.1f},{top + h - (v - lo) * h / span:.1f}"
                       for i, v in enumerate(values))
        return f'<polyline fill="none" stroke="{color}" stroke-width="1" points="{pts}"/>'

    # La señal filtrada y el umbral comparten escala para que se puedan comparar.
    lo = min(min(filt), min(thr))
    hi = max(max(filt), max(thr))
    span = (hi - lo) or 1
    top, h = 170, 160

    def shared(values, color, dash=""):
        pts = " ".join(f"{pad + i * (width - 2 * pad) / n:.1f},{top + h - (v - lo) * h / span:.1f}"
                       for i, v in enumerate(values))
        return f'<polyline fill="none" stroke="{color}" stroke-width="1" {dash} points="{pts}"/>'

    marks = "".join(
        f'<line x1="{pad + i * (width - 2 * pad) / n:.1f}" y1="{top}" '
        f'x2="{pad + i * (width - 2 * pad) / n:.1f}" y2="{top + h}" stroke="#d62728" stroke-width="1"/>'
        for i, t in enumerate(trace) if t[2])
    ticks = "".join(
        f'<text x="{pad + s * m.SAMPLE_HZ * (width - 2 * pad) / n:.1f}" y="{height - 8}" '
        f'font-size="10" text-anchor="middle">{s}s</text>'
        for s in range(0, n // m.SAMPLE_HZ + 1, 5))
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" font-family="sans-serif">
<rect width="100%" height="100%" fill="white"/>
<text x="{pad}" y="18" font-size="13" font-weight="bold">{title}</text>
<text x="{pad}" y="36" font-size="11">IR crudo (entrada)</text>
{poly(ir, 42, 110, "#1f77b4")}
<text x="{pad}" y="{top - 4}" font-size="11">Señal filtrada (negro), umbral env/2 (naranja), latidos detectados (rojo)</text>
{marks}
{shared(filt, "#000000")}
{shared(thr, "#ff7f0e", 'stroke-dasharray="4 2"')}
{ticks}
</svg>"""
    (OUT_DIR / f"{name}.svg").write_text(svg, encoding="utf-8")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Resultados del modelo de referencia",
        "",
        "Generado por `fpga/model/run_reference.py`. Error medido después de "
        f"{SETTLE_S} s de estabilización contra el BPM real de los últimos 4 latidos.",
        "",
        "| Caso | BPM esperado | BPM observado (final) | Error máx. con Q=1 | Segundos con Q=1 | Latidos reales / detectados | Q=1 con error > 2 BPM |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    failures = 0
    for stim in sorted(STIM_DIR.glob("*.hex")):
        name = stim.stem
        rows = read_stim(stim)
        truth = read_truth(STIM_DIR / f"{name}_truth.csv")
        beats, per_sec, trace = run_case(rows)
        write_csvs(name, beats, per_sec)
        title = stim.read_text().splitlines()[0].lstrip("/ ").strip()
        write_svg(name, rows, trace, title)

        errors, bad = [], 0
        for t, bpm, _ibi, valid, _q in per_sec:
            ref = true_bpm(truth, t)
            if valid and ref is not None:
                err = abs(bpm - ref)
                if t >= SETTLE_S:
                    errors.append(err)
                if err > 2:
                    bad += 1
        valid_secs = sum(1 for r in per_sec if r[3])
        final = per_sec[-1]
        expected = f"{true_bpm(truth, final[0]):.1f}" if truth else "sin pulso (Q=0)"
        observed = f"{final[1]} (Q={final[3]})"
        max_err = f"{max(errors):.2f}" if errors else "-"
        failures += bad
        if not truth and valid_secs:
            failures += 1
        lines.append(f"| {name} | {expected} | {observed} | {max_err} | {valid_secs}/{len(per_sec)} | "
                     f"{len(truth)} / {len(beats)} | {bad} |")
        print(lines[-1])

    lines += ["", f"Mediciones válidas con error > 2 BPM: **{failures}**", ""]
    (OUT_DIR / "summary.md").write_text("\n".join(lines), encoding="utf-8")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
