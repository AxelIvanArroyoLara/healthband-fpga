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

## Configuración provisional de Bluetooth LE

En el monitor, abre **Configurar Bluetooth LE** e introduce los UUID completos del
servicio y la característica que confirme el equipo del ESP32. Activa Bluetooth,
concede los permisos solicitados, busca dispositivos y selecciona el periférico.
La característica debe admitir notificaciones o indicaciones con descriptor CCCD.
La búsqueda dura hasta 10 segundos y la suscripción hasta 15 segundos. Para
reconectar, vuelve a seleccionar el dispositivo. La app conserva la selección
disponible en memoria mientras vive el monitor.

Sin datos físicos todavía queda por verificar el anuncio del ESP32, la suscripción
GATT y la entrega de tramas fragmentadas. Los UUID se introducen en pantalla y
el simulador se puede iniciar sin configurarlos.

[Permisos Bluetooth de Android](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
