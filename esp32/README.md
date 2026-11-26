# ESP32 UART–BLE

Puente HB1 para ESP32 clásico. La versión verificada de compilación es
ESP-IDF v5.5.6 con NimBLE. El servicio de salida y el UUID Notify están
definidos en el [contrato HB1](../shared/PROTOCOL.md).

## Configuración y compilación

Activa un entorno oficial de [ESP-IDF v5.5.6](https://docs.espressif.com/projects/esp-idf/en/v5.5.6/esp32/get-started/).
Ejecuta desde `esp32/`. Usa un directorio de configuración por perfil para
poder conservar ambos binarios y flashearlos sin cambiar el otro.

```bash
mkdir -p build/bridge build/ble-test
idf.py -B build/bridge -D SDKCONFIG="$PWD/build/bridge/sdkconfig" set-target esp32
idf.py -B build/bridge build

idf.py -B build/ble-test -D SDKCONFIG="$PWD/build/ble-test/sdkconfig" \
  -D 'SDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.ble-test' set-target esp32
idf.py -B build/ble-test build
```

| Perfil | Nombre anunciado | Fuente |
| --- | --- | --- |
| UART_BRIDGE (predeterminado) | HealthBand | RX UART a 115200, 8N1, sin control de flujo |
| BLE_TEST | HealthBand-Test | Secuencia sintética continua de una trama por segundo. El perfil inicial usa 75 BPM y fuerza fragmentos de hasta 7 bytes |

En `idf.py -B build/bridge menuconfig`, abre **HealthBand** para elegir UART1
o UART2 y GPIO RX. UART2/GPIO16 son los valores iniciales. Antes de conectar,
identifica el módulo y confirma que GPIO16 está disponible. Algunas variantes
lo reservan para PSRAM. Valida los pines de arranque, flash, consola y PSRAM
con el pinout específico. Conecta FPGA TX a ESP32 RX y GND común, con lógica
de 3,3 V. La consola de flasheo y monitor sigue en el puerto USB de la placa.

En `idf.py -B build/ble-test menuconfig`, selecciona 60, 75, 100, 120 BPM o
Q=0 y habilita o deshabilita la fragmentación forzada. Para 100 tramas deja
el cliente suscrito durante al menos 100 segundos. Cambiar de escenario
requiere reconstruir ese perfil. Marca la fuente como sintética en Android
cuando el nombre no esté disponible o la FPGA emita PPG sintética.

Tras confirmar modelo y puerto serie, elige un perfil:

```bash
idf.py -B build/ble-test -p PUERTO flash monitor
idf.py -B build/bridge -p PUERTO flash monitor
```

Cada directorio contiene `healthband_bridge.bin`, `bootloader/bootloader.bin`,
`partition_table/partition-table.bin` y `flash_args`. Para flashear una copia
completa del directorio desde un equipo con la herramienta Espressif, ejecuta
desde el directorio copiado `python -m esptool --chip esp32 -p PUERTO write_flash @flash_args`.
Revisa el [procedimiento físico](../docs/PHYSICAL_INTEGRATION_GUIDE.md).

## Framing y diagnóstico

UART usa un anillo de 1024 bytes y reconstruye hasta 128 bytes antes de LF.
Las líneas largas y errores UART resuelven la sincronización en el siguiente
LF. La cola BLE admite cuatro líneas completas, drena en orden y descarta la
nueva al llenarse. La generación de suscripción evita pasar una línea parcial
a otro enlace. Desconectar limpia la cola. Un error al enviar fuerza cierre
del enlace y el advertising se reinicia. Para fragmentar se usa el MTU ATT
efectivo menos tres bytes, con 20 bytes de carga útil en ATT MTU 23.

El monitor lista modo, puerto, advertising, conexión, CCCD, MTU y
desconexión. Los acumulados de UART, descartes y errores aparecen al inicio
y cada 100 líneas. El contador BLE representa líneas aceptadas por la pila
local. Notify carece de confirmación de la app. Usa el contador Android
y SEQ para verificar recepción. Las tramas fisiológicas no se imprimen.

Ejecuta `bash shared/test_hb1.sh` desde la raíz para probar framing, FIFO,
fragmentación y la cadena RTL–C–Android. Las pruebas físicas BLE y UART se
registran en el checklist.

[API NimBLE de Espressif](https://docs.espressif.com/projects/esp-idf/en/v5.5.6/esp32/api-reference/bluetooth/nimble/index.html)
[API UART de Espressif](https://docs.espressif.com/projects/esp-idf/en/v5.5.6/esp32/api-reference/peripherals/uart.html)

## Paquetes listos para flashear

Usa [UART_BRIDGE](artifacts/uart-bridge/README.md) o
[BLE_TEST](artifacts/ble-test/README.md) desde el ZIP final. Cada carpeta
incluye configuración resuelta y `flash_args` para mantener los offsets
generados. Si cambias el pin o el escenario, recompila el perfil,
registra el commit y vuelve a calcular los hashes.
