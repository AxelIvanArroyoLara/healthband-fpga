# Compilación en Quartus

Compilado con **Quartus Prime 21.1.1 Build 850 06/23/2022 SJ Lite Edition**
(`quartus_sh --flow compile healthband`), la misma versión del laboratorio.
Los archivos resultantes están en [`../../bitstream/`](../../bitstream/).

## Resultado

| Etapa | Resultado |
| --- | --- |
| Analysis & Synthesis | Sin errores, 18 warnings |
| Fitter | Sin errores, 5 warnings |
| Assembler (`.sof`, `.pof`) | Sin errores, 1 warning |
| Timing Analyzer | Sin errores; **todas las restricciones se cumplen** |

Recursos (10M50DAF484C7G): 1 771 elementos lógicos de 49 760 (4 %), 873
registros, 75 pines, sin memoria ni multiplicadores. `max30100_ctrl` ocupa
363 elementos lógicos e `i2c_master` 69.

Tiempos con el reloj de 50 MHz (periodo de 20 ns), peor caso:

| Modelo | Setup | Hold |
| --- | --- | --- |
| Slow 1200 mV 85 °C | +5.330 ns | +0.340 ns |
| Slow 1200 mV 0 °C | +6.463 ns | +0.305 ns |

Fmax ≈ 68 MHz.

Pines del sensor (reporte del fitter): `GPIO[0]` (V10, SCL) y `GPIO[1]` (W10,
SDA) quedaron **open drain con pull-up débil activado**; `GPIO[2]` (V9, TX)
es salida normal. Lista completa en [`healthband.pin`](healthband.pin).

## Warnings revisados

Lista completa en [`warnings.txt`](warnings.txt). Ninguno afecta el funcionamiento:

| Warning | Por qué no importa |
| --- | --- |
| 13410 `HEXn[7]` stuck at VCC | Puntos decimales apagados a propósito. |
| 15610 / 21074 `KEY[1]` sin uso | Solo se usa KEY0 (reset). |
| 13034 / 13035 / 13009 `GPIO[2]` | `GPIO` es `inout`; la UART lo maneja siempre como salida. |
| 10230 truncamientos en `ppg_filter.v` y `uart_tx.v` | Intencionales; el RTL coincide bit a bit con el modelo de referencia. |
| 10036 `h3` sin leer en `bpm_calc.v` | Registro de historial que no se usa en la salida; Quartus lo elimina. |
| 169177 interfaces de 3.3 V | Aviso general del MAX 10 (AN 447); la DE10-Lite ya está diseñada para eso. |
| 15714 / 169064 asignaciones de E/S incompletas | Faltan opciones opcionales (corriente, slew); se usan los valores por defecto. |
| 292013 LogicLock | Las líneas de partición del QSF las agregó Quartus; no se usa LogicLock. |
| 18236 número de procesadores | Solo rendimiento de compilación. |

## Simulación del netlist post-síntesis

Además de la simulación RTL (`../rtl/`), se simuló el **netlist de compuertas
que genera Quartus** (`quartus_eda --simulation --functional`) con el modelo
I2C del sensor, para descartar diferencias entre simulación y síntesis. Para
que fuera corta se compiló una versión con relojes escalados (345 600 Hz,
I2C a 28 800 Hz). Los buffers de E/S del MAX 10 vienen cifrados para
ModelSim, así que para Icarus se usaron equivalentes de comportamiento
(triestado / open drain). Resultado: [`gate_sim.txt`](gate_sim.txt).
