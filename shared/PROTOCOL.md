# Protocolo provisional

Este documento describe una primera propuesta para intercambiar mediciones.
**No es el protocolo definitivo**: los UUID BLE, límites exactos de los
campos, política de reconexión y otros parámetros siguen pendientes de
acuerdo.

## Trama de ejemplo

```text
HB1,SEQ=000012,BPM=075,IBI=0800,Q=1
```

Los campos son:

- `HB1`: versión provisional del protocolo.
- `SEQ`: número secuencial de la medición.
- `BPM`: frecuencia cardíaca estimada, en pulsaciones por minuto.
- `IBI`: intervalo entre pulsaciones, en milisegundos.
- `Q`: indicador de validez; `1` significa válida y `0`, inválida.

## Transporte inicial

- UART entre FPGA y ESP32: 115200 baudios, 8N1.
- Frecuencia prevista: una trama por segundo.
- Delimitador de trama: salto de línea (`\n`).
- ESP32 hacia Android: notificaciones de un servicio GATT BLE.

La codificación de caracteres, el tamaño máximo de trama, los UUID y la
configuración GATT todavía deben especificarse.

## Reglas para Android

El receptor debe:

1. Acumular bytes hasta encontrar el salto de línea para reconstruir mensajes
   fragmentados.
2. Validar la versión, la presencia de campos, sus tipos y sus rangos una vez
   que estos sean acordados.
3. Detectar números de secuencia duplicados, saltos de secuencia y lecturas
   obsoletas.
4. Separar una trama inválida de una lectura con `Q=0`, sin convertir ninguna
   de ellas en un diagnóstico.

Los criterios de recuperación y de reconexión quedan pendientes.

## Emisor FPGA (propuesta de Dani)

Comportamiento implementado en `fpga/rtl/hb1_framer.v`; pendiente de que el
equipo lo acepte:

- Trama ASCII de 36 bytes terminada solo en `\n` (sin `\r`).
- Se envía una trama por segundo aunque no haya medición válida.
- Medición inválida: `BPM=000`, `IBI=0000` y `Q=0`. La FPGA nunca envía un BPM
  distinto de cero con `Q=0`.
- Con `Q=1`, `BPM` está entre 030 y 240 e `IBI` entre 0250 y 2000.
- `SEQ` empieza en `000000` al encender o reiniciar la FPGA, aumenta 1 por
  trama (también con `Q=0`) y pasa de `999999` a `000000`.

**Reinicio de la FPGA (pendiente de acuerdo con Android).** Tras un reset la
secuencia vuelve a `000000`. Propuesta: el receptor interpreta `SEQ=000000`
que no sigue a `999999` como arranque nuevo del emisor, reinicia su control de
secuencia y abre un segmento nuevo, en lugar de rechazar las tramas como fuera
de orden.
