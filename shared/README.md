# Interfaces compartidas

El [contrato HB1](PROTOCOL.md) define UART, ASCII, secuencia, rangos,
fragmentación y UUID BLE para FPGA, ESP32 y Android.

Ejecuta `bash shared/test_hb1.sh` desde la raíz con Icarus, un compilador C
y el entorno Gradle de Android. El script genera 100 tramas con el UART RTL,
ejecuta framing y fragmentación con el C del firmware y pasa los fragmentos
al parser JVM. Los intermedios quedan en `shared/build/hb1/`.
