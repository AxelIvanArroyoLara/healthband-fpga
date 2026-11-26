# Guía rápida para la demostración: DE10-Lite + MAX30100

Solo se necesita la DE10-Lite, el módulo del sensor (MAX30100 o MAX30102),
4 cables dupont hembra-hembra y el cable USB de la placa. El ESP32 no hace
falta para esta demo.

## 1. Conexiones (con la placa apagada)

Todo va al header de 40 pines **JP1 (GPIO)** de la DE10-Lite. El **pin 1 está
en la última fila, la que queda junto al conector USB** (comprobado en la placa
con el escáner I²C). Los impares (1, 3, 5…) van en una columna y los pares
(2, 4, 6…) en la otra; las filas se cuentan desde la del USB.

| Módulo del sensor | JP1 (DE10-Lite) | Qué es |
| --- | --- | --- |
| **VIN** | **pin 29** | 3.3 V (**no usar 5 V**, pin 11) |
| **GND** | **pin 30** (o 12) | tierra |
| **SCL** | **pin 1** | `GPIO[0]`, `PIN_V10` |
| **SDA** | **pin 2** | `GPIO[1]`, `PIN_W10` |
| INT, IRD, RD | nada | — |

```text
          JP1 visto desde arriba, contando desde la fila del USB
          col. impar   col. par
 fila  1:  [ 1] SCL     [ 2] SDA      <- sensor
 fila  2:  [ 3] TX      [ 4] -        (TX va al ESP32, no se usa en esta demo)
 fila  3:  [ 5]         [ 6]
 fila  4:  [ 7]         [ 8]
 fila  5:  [ 9]         [10]
 fila  6:  [11] 5V !!   [12] GND
 ...
 fila 15:  [29] 3.3V    [30] GND      <- sensor VIN y GND
 ...
 fila 20:  [39]         [40]
            ────── conector USB ──────   (la fila 1 queda de este lado)
```

- La serigrafía del módulo dice qué pin es cuál; en el módulo de 7 pines el
  orden normal es `VIN SCL SDA INT IRD RD GND`.
- No conectar nada del sensor al header Arduino (el header pequeño junto a los
  displays): VIN y GND del sensor van a los pines 29 y 30 del JP1.
- Verificado el 2026-11-26: con este cableado el MAX30100 responde en los
  pines 1 y 2 con PART_ID `11`.
- Si el ESP32 sigue cableado, que solo toque JP1 pin 3 (TX) y GND; nunca los
  pines 1 y 2.

## 2. Programar

**No hace falta compilar:** el archivo ya compilado (Quartus 21.1.1, sin
errores) está en [`bitstream/healthband.sof`](bitstream/). Quartus →
Tools → Programmer → Hardware Setup: **USB-Blaster** → Add File →
`bitstream/healthband.sof` → marcar Program/Configure → **Start**. Ver
[`bitstream/README.md`](bitstream/README.md).

Si se cambia el Verilog, recompilar:

1. Quartus Prime Lite → File → Open Project → `fpga/quartus/healthband.qpf`.
2. Processing → Start Compilation (unos 2 minutos). Debe terminar sin errores.
3. Programar `quartus/output_files/healthband.sof` igual que arriba.

El `.sof` se borra al apagar la placa. Para que quede grabado, programar
`bitstream/healthband.pof` (fila CFM0) en lugar del `.sof`.

## 3. Prueba con el sensor (todos los switches abajo)

| Qué ver | Significa |
| --- | --- |
| **LEDR8 encendido** en menos de 1 s | El sensor responde por I²C y quedó configurado. |
| Displays en `---` | Todavía no hay medición válida (normal sin dedo o en los primeros 5 s). |
| Dedo puesto: **LEDR0 parpadea** con cada latido | Se detectan los pulsos. |
| A los 5–10 s **HEX2..HEX0 = BPM** y **LEDR1 encendido** | Medición válida (Q=1). |

Consejo: apoyar la yema del dedo **sin apretar** y sin moverla. Si se aprieta
mucho o se mueve, la señal se pierde y vuelve a `---` unos segundos.

## 4. Plan B (si el sensor falla durante la demo)

Subir **SW9** (generador sintético) y SW0: muestra **75 BPM** a los ~5 s.
Con SW1..SW0 se elige 60/75/100/120 BPM, SW2 agrega ruido, SW3 simula dedo
retirado (`---`) y SW4 saturación.

## 5. Si algo no funciona

| Síntoma | Revisar |
| --- | --- |
| No se sabe si el sensor responde | Cargar `bitstream/i2c_scan.sof` (escáner I²C, ver [`diag/i2c_scan/`](diag/i2c_scan/)): con los switches abajo muestra en qué pines del JP1 está el sensor y su PART_ID (`01 02 11` = correcto). Después volver a cargar `healthband.sof`. |
| LEDR8 apagado | Cables SCL/SDA invertidos o en otros pines; VIN/GND; el módulo sin alimentar. Con **SW8 arriba**, HEX5..HEX4 deben decir `11` (MAX30100) o `15` (MAX30102); `00` = no hay comunicación. Probar presionando KEY0 (reset). |
| LEDR8 apagado y cables bien | Algunos módulos morados suben SDA/SCL a 1.8 V. Poner resistencias de 4.7 kΩ de SDA a 3.3 V y de SCL a 3.3 V (pin 29). |
| LEDR8 encendido pero siempre `---` | Subir SW8: HEX3..HEX0 = IR crudo. Con el dedo debe estar entre `2000` y `F000`. Cerca de `FFFF` → bajar corriente (SW7..SW5 = 001 o 010). Debajo de `1F40` → subir corriente (SW7..SW5 = 101 o 111). LEDR3 encendido = "sin contacto", LEDR2 = saturación, LEDR6 = amplitud baja. |
| El BPM salta mucho | Dedo quieto, sin apretar, sin luz directa encima. |

## Switches y LEDs

| Control | Función |
| --- | --- |
| KEY0 | Reset |
| SW9 | 0 = sensor real, 1 = generador sintético |
| SW8 | Displays de depuración (IR crudo y PART_ID) |
| SW7..SW5 | Corriente de LEDs: 000 = 24 mA (normal), 001 = 11, 010 = 17, 011 = 24, 100 = 31, 101 = 37, 110 = 44, 111 = 50 mA |
| SW4..SW0 | Solo con SW9 = 1: BPM, ruido, dedo retirado, saturación |
| LEDR0 | Latido |
| LEDR1 | Medición válida (Q=1) |
| LEDR2..LEDR6 | Saturación, sin contacto, FIFO, muestras perdidas, amplitud baja |
| LEDR7 | UART transmitiendo (1 trama por segundo) |
| LEDR8 | Sensor configurado y respondiendo |
| LEDR9 | Generador sintético activo |
