# Contrato HB1 de integración

La FPGA emite una línea por segundo en ASCII por UART a 115200, 8N1, sin
control de flujo. Cada línea canónica tiene 36 bytes, incluido LF (0x0A).

```text
HB1,SEQ=000012,BPM=075,IBI=0800,Q=1
HB1,SEQ=000013,BPM=000,IBI=0000,Q=0
```

| Campo | Emisor | Receptor Android |
| --- | --- | --- |
| SEQ | Seis dígitos, 000000–999999 | Avance circular inferior a 500000, con rechazo de duplicados |
| BPM | Tres dígitos, 30–240 con Q=1 | Mismo rango |
| IBI | Cuatro dígitos, 250–2000 ms con Q=1 | 250–2500 ms por compatibilidad |
| Q | 1 válida, 0 inválida | Q=0 consume SEQ, oculta lectura, corta gráfica y análisis, y excluye la muestra de estadísticas |

El puente conserva los bytes y el LF de cada línea en orden. Los receptores
admiten CRLF. Las líneas de más de 128 bytes antes de LF se descartan hasta
el siguiente LF. Las comprobaciones de campos y secuencia corresponden a Android.

## Enlace BLE

- Anuncio normal `HealthBand`. El firmware de prueba anuncia `HealthBand-Test`.
- Servicio `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`.
- Característica Notify `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`.
- Los UUID siguen el esquema Nordic UART para TX. El servidor expone
  únicamente la característica de salida con CCCD estándar.
- Una notificación lleva hasta MTU − 3 bytes. Con MTU 23, una trama se
  divide en 20 y 16 bytes. Se suscribe antes de emitir y se reinicia el
  enlace tras un fallo de notificación para aislar fragmentos parciales.

## Secuencia y reinicio

El paso 999999 → 000000 es válido. La FPGA arranca en 000000 y HB1 carece de
identificador de arranque. Tras reiniciar la FPGA, desconecta y vuelve a elegir
el periférico en Android. El puente elimina las notificaciones pendientes de
la conexión anterior y Android inicia un parser nuevo. Dentro de un enlace el
receptor conserva la política circular. La caducidad visual no reinicia SEQ.
