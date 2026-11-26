"""Genera señales PPG sintéticas para los testbenches de la FPGA.

Cada caso produce:
  fpga/stim/<caso>.hex        una palabra de 40 bits por ranura de 10 ms
                              {flags[7:0], red[15:0], ir[15:0]}
                              flags: bit0 = muestra perdida (sin sample_valid)
                                     bit1 = fifo_overflow
                                     bit7 = fin de archivo
  fpga/stim/<caso>_truth.csv  instantes reales de cada latido

La señal imita la salida óptica del MAX30100: un nivel DC alto que baja en
cada sístole (más sangre, más absorción), con deriva respiratoria y ruido.
Las semillas son fijas para que las pruebas sean reproducibles.

Uso: python -I fpga/model/gen_stimulus.py
"""

import csv
import math
import random
from pathlib import Path

FS = 100
DC_IR = 40000
DC_RED = 30000
AC_IR = 400
STIM_DIR = Path(__file__).resolve().parent.parent / "stim"


def pulse_shape(phase, dicrotic):
    """Forma de un latido normalizada a pico 1: sístole + onda dicrótica."""
    return (math.exp(-((phase - 0.20) / 0.08) ** 2)
            + dicrotic * math.exp(-((phase - 0.48) / 0.07) ** 2))


def synth(seconds, bpm, seed, noise=4.0, jitter=0.01, dicrotic=0.35,
          wander=60.0, ac=AC_IR):
    """Devuelve (ir, red, beat_times) como listas, una entrada por muestra."""
    rng = random.Random(seed)
    n = int(seconds * FS)
    period = 60.0 / bpm

    beats = []
    t = rng.uniform(0.0, period)
    while t < seconds + period:
        beats.append(t)
        t += period * (1.0 + rng.gauss(0.0, jitter))

    ir, red = [], []
    k = 0
    for i in range(n):
        ts = i / FS
        while k + 1 < len(beats) and beats[k + 1] <= ts:
            k += 1
        if ts < beats[0]:
            shape = 0.0
        else:
            length = beats[k + 1] - beats[k]
            shape = pulse_shape((ts - beats[k]) / length, dicrotic)
        drift = wander * math.sin(2 * math.pi * 0.25 * ts) + 40.0 * math.sin(2 * math.pi * 0.03 * ts)
        ir.append(DC_IR - ac * shape + drift + rng.gauss(0.0, noise))
        red.append(DC_RED - 0.6 * ac * shape + 0.6 * drift + rng.gauss(0.0, noise))
    return ir, red, [b for b in beats if b < seconds]


def clamp16(v):
    return max(0, min(0xFFFF, int(round(v))))


def write_case(name, ir, red, flags, beats, description):
    STIM_DIR.mkdir(exist_ok=True)
    with open(STIM_DIR / f"{name}.hex", "w", newline="\n") as f:
        f.write(f"// {name}: {description}\n")
        for x, r, fl in zip(ir, red, flags):
            f.write(f"{fl:02x}{clamp16(r):04x}{clamp16(x):04x}\n")
        f.write("8000000000\n")
    with open(STIM_DIR / f"{name}_truth.csv", "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["beat_time_s"])
        for b in beats:
            w.writerow([f"{b:.4f}"])


def main():
    cases = {}

    for bpm in (60, 75, 100, 120):
        ir, red, beats = synth(30, bpm, seed=bpm)
        cases[f"bpm{bpm:03d}"] = (ir, red, [0] * len(ir), beats,
                                 f"{bpm} BPM nominal, ruido bajo")

    ir, red, beats = synth(30, 75, seed=7501, noise=40.0, wander=150.0)
    cases["noise075"] = (ir, red, [0] * len(ir), beats, "75 BPM con ruido y deriva altos")

    ir, red, beats = synth(30, 75, seed=7502, dicrotic=0.6)
    cases["dicrotic075"] = (ir, red, [0] * len(ir), beats, "75 BPM con onda dicrotica marcada (60 %)")

    ir, red, beats = synth(30, 75, seed=7502, dicrotic=0.95)
    cases["doublepeak075"] = (ir, red, [0] * len(ir), beats,
                              "75 BPM con doble pico casi igual: debe quedar Q=0, nunca BPM falso")

    ir, red, beats = synth(30, 75, seed=7503)
    for i in range(1000, 1500):
        ir[i] = 0xFFFF
    cases["saturation"] = (ir, red, [0] * len(ir), beats, "75 BPM, IR saturado de 10 s a 15 s")

    ir, red, beats = synth(30, 75, seed=7504)
    rng = random.Random(1)
    for i in range(1000, 1500):
        ir[i] = 300 + rng.gauss(0.0, 20.0)
        red[i] = 250 + rng.gauss(0.0, 20.0)
    cases["nocontact"] = (ir, red, [0] * len(ir), beats, "75 BPM, dedo retirado de 10 s a 15 s")

    ir, red, beats = synth(30, 75, seed=7505)
    flags = [0] * len(ir)
    for i in range(1000, 1050):
        flags[i] = 0x01
    cases["dropout"] = (ir, red, flags, beats, "75 BPM, 50 muestras perdidas a los 10 s")

    ir, red, beats = synth(30, 75, seed=7506)
    flags = [0] * len(ir)
    flags[1000] = 0x02
    cases["overflow"] = (ir, red, flags, beats, "75 BPM, fifo_overflow a los 10 s")

    ir, red, _ = synth(20, 75, seed=7507, ac=0.0, noise=6.0)
    cases["flat"] = (ir, red, [0] * len(ir), [], "Sin pulso: solo DC, deriva y ruido")

    for name, (ir, red, flags, beats, desc) in cases.items():
        write_case(name, ir, red, flags, beats, desc)
        print(f"{name:12s} {len(ir):5d} muestras  {desc}")


if __name__ == "__main__":
    main()
