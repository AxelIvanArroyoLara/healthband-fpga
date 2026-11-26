# Escáner I²C para la DE10-Lite

Diseño de diagnóstico, separado de HealthBand, que busca el sensor de pulso
(dirección I²C `0x57`) en **todos los pares de pines del JP1** y muestra en los
displays dónde lo encontró. Sirve para comprobar el cableado sin adivinar qué
extremo del header es el pin 1. Los pines solo se jalan a 0 (open drain) y
nunca se manejan en alto, así que no hay riesgo con lo que esté conectado. La
búsqueda se repite cada ~0.4 s: se pueden mover cables con la placa encendida.

Archivo listo para programar: [`../../bitstream/i2c_scan.sof`](../../bitstream/i2c_scan.sof).

| Switches | Displays |
| --- | --- |
| Todos abajo | `HEX5-4` = pin del JP1 donde está SCL, `HEX3-2` = pin de SDA, `HEX1-0` = PART_ID (`11` = MAX30100, `15` = MAX30102). Todo en `-` = no lo encuentra. |
| SW0 arriba | Pines del JP1 que leen 0 con todo suelto (cable a GND o sensor sin alimentación): los dos primeros y cuántos son. Tocar la punta de un cable con GND muestra a qué pin del JP1 llega. |

LEDR0 cambia en cada vuelta del escáner y LEDR9 indica que encontró el sensor.

Resultado con el cableado de [`../../DEMO.md`](../../DEMO.md) (2026-11-26):
`01 02 11`, es decir, MAX30100 con SCL en el pin 1 y SDA en el pin 2.

Compilar desde esta carpeta: `quartus_sh --flow compile i2c_scan`. Usa
`../../rtl/i2c_master.v` (el mismo maestro I²C del diseño principal) y el mapa
de los 36 GPIO del JP1 en `i2c_scan.qsf`.
