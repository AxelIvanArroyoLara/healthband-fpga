# ESP32

Este módulo implementará el puente de comunicaciones entre la FPGA y la
aplicación Android.

## Responsabilidades

- Recibir tramas de la FPGA por UART a 115200 baudios, 8N1.
- Exponer los datos mediante notificaciones Bluetooth Low Energy (BLE).
- Configurar el servicio GATT y gestionar conexión, desconexión y consumo.
- Probar el puente con mensajes simulados antes de usar hardware real.

El formato provisional compartido está en
[`../shared/PROTOCOL.md`](../shared/PROTOCOL.md). El modelo exacto de ESP32 y
la configuración GATT siguen pendientes.
