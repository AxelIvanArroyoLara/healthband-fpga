# Resultados del modelo de referencia

Generado por `fpga/model/run_reference.py`. Error medido después de 8 s de estabilización contra el BPM real de los últimos 4 latidos.

| Caso | BPM esperado | BPM observado (final) | Error máx. con Q=1 | Segundos con Q=1 | Latidos reales / detectados | Q=1 con error > 2 BPM |
| --- | --- | --- | --- | --- | --- | --- |
| bpm060 | 60.1 | 60 (Q=1) | 0.51 | 26/30 | 30 / 30 | 0 |
| bpm075 | 74.9 | 75 (Q=1) | 0.83 | 27/30 | 38 / 37 | 0 |
| bpm100 | 100.9 | 101 (Q=1) | 0.73 | 27/30 | 50 / 49 | 0 |
| bpm120 | 119.8 | 121 (Q=1) | 1.39 | 28/30 | 60 / 60 | 0 |
| dicrotic075 | 74.8 | 75 (Q=1) | 0.74 | 27/30 | 38 / 38 | 0 |
| doublepeak075 | 74.8 | 0 (Q=0) | - | 0/30 | 38 / 75 | 0 |
| dropout | 75.2 | 75 (Q=1) | 0.62 | 22/30 | 37 / 36 | 0 |
| flat | sin pulso (Q=0) | 0 (Q=0) | - | 0/20 | 0 / 5 | 0 |
| nocontact | 75.0 | 75 (Q=1) | 0.74 | 19/30 | 38 / 32 | 0 |
| noise075 | 74.9 | 75 (Q=1) | 0.92 | 27/30 | 38 / 38 | 0 |
| overflow | 74.7 | 75 (Q=1) | 0.84 | 24/30 | 38 / 38 | 0 |
| saturation | 75.0 | 75 (Q=1) | 0.32 | 19/30 | 38 / 31 | 0 |

Mediciones válidas con error > 2 BPM: **0**
