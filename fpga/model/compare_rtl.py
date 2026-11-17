"""Compara la simulación RTL con el modelo de referencia.

Para cada caso de fpga/stim compara, línea por línea, los CSV escritos por
tb_ppg_processor.v (fpga/evidence/rtl/) con los del modelo
(fpga/evidence/reference/). Como el modelo es bit a bit, deben coincidir
exactamente. Escribe fpga/evidence/rtl/compare.md.

Uso: python -I fpga/model/compare_rtl.py   (después de run_reference.py y de
     correr los testbenches con fpga/sim/run_icarus.sh o run_questa.do)
"""

import sys
from pathlib import Path

FPGA_DIR = Path(__file__).resolve().parent.parent
REF_DIR = FPGA_DIR / "evidence" / "reference"
RTL_DIR = FPGA_DIR / "evidence" / "rtl"


def read_lines(path):
    return [ln.strip() for ln in path.read_text().splitlines() if ln.strip()]


def main():
    lines = [
        "# Comparación RTL vs. modelo de referencia",
        "",
        "| Caso | Latidos RTL / modelo | Muestras 1 Hz RTL / modelo | Diferencias | Resultado |",
        "| --- | --- | --- | --- | --- |",
    ]
    failures = 0
    for stim in sorted((FPGA_DIR / "stim").glob("*.hex")):
        name = stim.stem
        diffs = 0
        counts = []
        missing = False
        for suffix in ("_beats.csv", "_1hz.csv"):
            rtl_path = RTL_DIR / f"{name}{suffix}"
            ref_path = REF_DIR / f"{name}{suffix}"
            if not rtl_path.exists() or not ref_path.exists():
                missing = True
                counts.append("falta")
                continue
            rtl, ref = read_lines(rtl_path), read_lines(ref_path)
            counts.append(f"{len(rtl) - 1} / {len(ref) - 1}")
            for i in range(max(len(rtl), len(ref))):
                a = rtl[i] if i < len(rtl) else "<fin>"
                b = ref[i] if i < len(ref) else "<fin>"
                if a != b:
                    if diffs < 5:
                        print(f"{name}{suffix} línea {i + 1}: RTL={a} modelo={b}")
                    diffs += 1
        ok = not missing and diffs == 0
        failures += 0 if ok else 1
        lines.append(f"| {name} | {counts[0]} | {counts[1]} | {diffs} | {'PASS' if ok else 'FAIL'} |")
        print(lines[-1])

    lines += ["", f"Casos con diferencias: **{failures}**", ""]
    RTL_DIR.mkdir(parents=True, exist_ok=True)
    (RTL_DIR / "compare.md").write_text("\n".join(lines), encoding="utf-8")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
