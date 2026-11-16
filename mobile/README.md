# Aplicación móvil

Este módulo contendrá la aplicación Android. No se ha seleccionado todavía un
framework Android.

## Responsabilidades

- Conectarse al ESP32 mediante BLE.
- Reconstruir mensajes fragmentados, validar el protocolo y rechazar datos
  duplicados, obsoletos o con saltos de secuencia.
- Mostrar BPM, IBI y calidad de señal en un dashboard.
- Mantener historial y línea base individual en almacenamiento local.
- Detectar anomalías de forma personalizada y proporcionar retroalimentación.
- Probar el parser y el flujo de datos con un simulador de mensajes.

La aplicación consume la interfaz provisional de
[`../shared/PROTOCOL.md`](../shared/PROTOCOL.md); sus límites y su
comportamiento de reconexión aún deben acordarse.
