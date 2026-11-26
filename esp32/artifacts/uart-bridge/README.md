# UART_BRIDGE

Perfil de puente UART–BLE para ESP32 clásico. Imagen del commit
`88a5a1d1920ba9d7cdd31e0c1c5788c91bf364b0` con ESP-IDF v5.5.6 y
esptool 4.14.0. Configuración: UART2/GPIO16, 115200 baudios, 8N1, sin control de flujo.

Anuncio BLE `HealthBand`. Servicio `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
y característica Notify `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`.

Desde esta carpeta, con esptool 4.14.0 en el entorno de ESP-IDF:

```sh
shasum -a 256 -c SHA256SUMS.txt
python -m esptool --chip esp32 -p PUERTO write_flash @flash_args
python -m serial.tools.miniterm PUERTO 115200
```

Sustituye `PUERTO` por el puerto serie de la placa identificada. El monitor
debe confirmar el modo, advertising y suscripción. Se espera una trama HB1 por segundo cuando la FPGA emite y el cliente habilita Notify.

`flash_args` conserva los offsets emitidos por ESP-IDF. `sdkconfig`
registra la configuración resuelta. Para cambiar RX o generar otro
escenario, sigue la [guía de compilación y diagnóstico](../../README.md).
