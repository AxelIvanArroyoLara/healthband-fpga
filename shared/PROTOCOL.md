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
