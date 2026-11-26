# Captura de la señal PPG por JTAG

`rtl/ppg_logger.v` (incluido en `healthband.sof`) guarda en una RAM de la FPGA
una palabra de 32 bits por muestra, 4096 muestras (~41 s a 100 Hz), desde el
reset (KEY0) hasta llenarse. Se lee por el mismo cable USB-Blaster con el
In-System Memory Content Editor de Quartus (instancia `PPG`), sin hardware
adicional y sin detener el diseño.

| Bits | Contenido |
| --- | --- |
| 15:0 | `ir_sample` (fuente seleccionada con SW9) |
| 16 | hubo latido desde la muestra anterior |
| 17 | `data_valid` (Q) |
| 22:18 | `signal_quality` |
| 23 | `fifo_overflow` desde la muestra anterior |
| 31:24 | BPM |

La dirección 4095 vale `A5A50FFF` cuando la grabación terminó.

Uso:

1. Poner el dedo en el sensor y presionar **KEY0**; esperar ~41 s.
2. Desde esta carpeta: `quartus_stp -t read_ppg.tcl captura.hex`.
3. `captura.hex` trae las 4096 palabras en hexadecimal **de la dirección
   4095 a la 0** (8 caracteres por palabra), como las entrega Quartus.
