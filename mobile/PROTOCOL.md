# Recepción de HB1 en Android

El [contrato compartido](../shared/PROTOCOL.md) define el formato y los UUID
predeterminados. Android conserva UUID editables y tolera IBI de 250–2500 ms
con Q=1. La FPGA emite IBI de 250–2000 ms.

- El parser acumula notificaciones ASCII, admite LF y CRLF, y descarta líneas
  de más de 128 caracteres hasta el siguiente LF.
- La primera trama aceptada fija SEQ. El avance circular cero se rechaza como
  duplicado y un avance de 500000 o mayor se rechaza por orden. El paso
  999999 → 000000 es válido. Un salto hacia delante corta la gráfica y la
  continuidad del detector.
- Q=0 cuenta como trama aceptada. Retira BPM e IBI, corta la gráfica y
  reinicia la continuidad del detector. El historial almacena Q=1.
- Cuatro segundos sin tramas aceptadas retiran la lectura actual. El tiempo
  transcurrido usa reloj monotónico y el historial guarda fechas Unix.
- Cada adquisición utiliza un parser nuevo. Tras reiniciar la FPGA, pulsa
  **Desconectar** y vuelve a elegir el ESP32. HB1 carece de identificador de
  arranque. Por ejemplo, 001000 → 000000 se rechaza y 999990 → 000010 se
  acepta como avance circular dentro de la misma conexión.
- Marca **Fuente BLE sintética** para un puente de prueba sin nombre o
  cuando la FPGA use PPG sintética. La app marca `HealthBand-Test` al ver
  ese nombre en el escaneo. El historial usa la clasificación para elegir
  la referencia de reposo.
