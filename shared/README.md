# Interfaces compartidas

Este directorio contiene los contratos que deben respetar FPGA, ESP32 y
Android. Centralizar estas decisiones permite que los tres integrantes
trabajen en paralelo y que los simuladores sean compatibles con el hardware.

El protocolo actual es provisional y está documentado en
[`PROTOCOL.md`](PROTOCOL.md). Los UUID BLE, límites de campos y otros
parámetros se agregarán cuando sean aprobados.
