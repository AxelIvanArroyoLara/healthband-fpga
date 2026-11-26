# Compilación en Quartus

Compilado con **Quartus Prime 21.1.1 Build 850 06/23/2022 SJ Lite Edition**
(`quartus_sh --flow compile healthband`), la misma versión del laboratorio.
Los archivos resultantes están en [`../../bitstream/`](../../bitstream/).

## Resultado

| Etapa | Resultado |
| --- | --- |
| Analysis & Synthesis | Sin errores |
| Fitter | Sin errores |
| Assembler (`.sof`, `.pof`) | Sin errores, 1 warning |
| Timing Analyzer | Sin errores; **todas las restricciones se cumplen** |

Recursos (10M50DAF484C7G): 2 091 elementos lógicos de 49 760 (4 %), 1 075
registros, 75 pines y 131 072 bits de memoria (8 %), que son los del grabador
de depuración `ppg_logger` (4096 × 32, ~41 s de muestras, lectura por JTAG; ver
[`../../diag/ppg_capture/`](../../diag/ppg_capture/)). Sin multiplicadores.

Tiempos con el reloj de 50 MHz (periodo de 20 ns), peor caso:

| Modelo | Setup | Hold |
| --- | --- | --- |
| Slow 1200 mV 85 °C | +6.247 ns | +0.340 ns |

Fmax 72.7 MHz (85 °C).

Pines del sensor (reporte del fitter): `GPIO[0]` (V10, SCL) y `GPIO[1]` (W10,
SDA) quedaron **open drain con pull-up débil activado**; `GPIO[2]` (V9, TX)
es salida normal. Lista completa en [`healthband.pin`](healthband.pin).

## Diagrama RTL

[`rtl_viewer_healthband_top.pdf`](rtl_viewer_healthband_top.pdf): esquemático
del top `healthband_top` exportado desde el RTL Viewer de Quartus (Tools →
Netlist Viewers → RTL Viewer), con el generador sintético, el controlador
`max30100_ctrl`, el procesamiento PPG, la trama HB1 y la UART.

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
