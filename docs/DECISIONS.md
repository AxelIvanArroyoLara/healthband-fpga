# Registro de decisiones

## Decisiones de la primera fase

- FPGA Terasic DE10-Lite y sensor MAX30100. Adquisición y procesamiento PPG
  en Verilog, incluido cálculo de BPM e IBI.
- ESP32 como puente UART–BLE. Android como plataforma móvil con
  almacenamiento local y análisis experimental.
- Módulos independientes y colaboración mediante Git y Pull Requests.

## Integración del MVP

- [HB1](../shared/PROTOCOL.md) a 115200, 8N1 y una trama por segundo. El
  esquema Nordic UART se usa para la salida Notify con CCCD. Android
  conserva UUID editables.
- ESP-IDF v5.5.6, target `esp32` clásico y NimBLE. El perfil UART usa
  recepción configurable. El perfil autónomo BLE_TEST anuncia
  `HealthBand-Test`. Confirmar variante y alimentación en mesa.
- El puente conserva bytes en orden y limita su cola a cuatro líneas. Ante
  un fallo Notify cierra el enlace para descartar cualquier fragmento
  pendiente. Una llamada exitosa representa aceptación por la pila local.
- Cada adquisición Android abre un parser nuevo. Un reset de FPGA requiere
  desconectar y volver a elegir el periférico. Descartada la propuesta
  histórica de aceptar automáticamente cualquier SEQ cero como arranque,
  por su ambigüedad con el contador circular y las tramas atrasadas.
- Kotlin, Compose, MVVM y Room. El escritor por adquisición guarda Q=1 en
  orden, con una cola de 32, cierre acotado y avisos de almacenamiento
  separados del transporte. El historial conserva segmentos y tiempos.
- Referencia individual por mediana y MAD. El detector usa persistencia
  temporal y fuentes sintéticas separadas de la referencia física.
  Los episodios guardados excluyen la sesión de la referencia futura.
- SpO₂ queda fuera del MVP. El canal RED se adquiere para usos posteriores.

[Detalle de Android](../mobile/README.md) · [Validación física](PHYSICAL_TEST_CHECKLIST.md)
