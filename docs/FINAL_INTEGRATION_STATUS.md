# Estado de integración final

## Base y entorno

Rama `feature/healthband-final-integration` sobre `origin/develop`
`7b5b75f0302c5ff25a7c160a903b27e445651d78`, confirmada por fetch el
25 de noviembre de 2026. La base incluía captura MAX30100, RTL PPG, UART y
Android estabilizado. ESP32 tenía solo su README. Se reutilizó el checkout
separado de integración para preservar `feature/axel-mobile` y su ZIP local.

Entorno macOS Apple Silicon, Python 3.9.6, Icarus 13.0, compilador C del
sistema, Gradle Wrapper 9.6.0, Java de Android Studio 25.0.3, SDK Android
API 37 y ADB 37.0.1. Se instaló ESP-IDF v5.5.6 con GCC Xtensa 14.2.0,
CMake y Ninja en un directorio temporal. Quartus y Verilator no estaban
disponibles. El AVD `Medium_Phone_API_37.0` se ejecutó en el puerto 5556
y se cerró al terminar.

## Verificación

| Bloque | Resultado | Evidencia |
| --- | --- | --- |
| HB1 | 36 bytes con LF, UART 115200 8N1, UUID Nordic TX, secuencia circular y parser por conexión | [Contrato](../shared/PROTOCOL.md) |
| ESP32 | Compilados UART_BRIDGE con UART2/GPIO16 y BLE_TEST con 75 BPM y fragmentos de 7 bytes. esptool validó las imágenes | Logs de compilación y paquetes de flash |
| Pruebas ESP32 | Framing parcial y múltiple, CRLF, overflow, resincronización, FIFO acotada, aislamiento de conexión, generación de cinco escenarios y 150 tramas sintéticas | `esp32/tests/hb1_test.c` y ejecución de contrato |
| FPGA | 12 escenarios PPG coinciden con Python. Banco UART de 100 tramas y banco de rollover 999998 → 999999 → 000000. Comparación byte a byte con valores cambiando durante transmisión. Cadena sintética 39 tramas. Modelo I²C 35 tramas y 3490 muestras | [Simulaciones](../fpga/evidence/rtl/), [comparación](../fpga/evidence/rtl/compare.md) |
| Android | 24 pruebas JVM incluidas las del contrato, 15 instrumentadas en API 37, lint 0 errores y 7 advertencias, debug y release sin firmar generados | Reportes JVM, Android y lint |
| Contrato de integración | 100 tramas RTL de 36 bytes en ATT MTU 23 y 39 y en MTU 247 limitado a 7 bytes. Conservación exacta de bytes y LF, orden, secuencias, BPM, IBI y Q | `bash shared/test_hb1.sh` |
| Anomalías | Parámetros originales preservados. Cobertura de entrada inválida, reposo, episodio, pérdida y calibración. Prueba de BLE sintético usa su referencia y corta el episodio tras salto SEQ | Pruebas Android JVM e instrumentadas |
| Quartus | Proyecto MAX 10 revisado. Síntesis, utilización, temporización, potencia y SOF pendientes | [Proyecto](../fpga/quartus/healthband.qpf) |
| Mesa | Validación eléctrica, flasheo, enlace de radio y corrida física pendientes | [Checklist](PHYSICAL_TEST_CHECKLIST.md) |

## Decisiones y limitaciones

- El puente pasa bytes HB1 sin procesamiento PPG. La cola BLE admite cuatro
  líneas, preserva orden y descarta nuevas líneas al saturarse. Si una
  notificación falla, termina el enlace para que Android abandone cualquier
  fragmento parcial. La prueba C verifica framing y descarte por conexión.
- HB1 carece de identificador de arranque. Android inicia un parser nuevo al
  reconectar después de reset de FPGA. El receptor conserva la tolerancia
  IBI de 250–2500 ms y la FPGA emite 250–2000 ms.
- El banco UART general incluye el IBI saturado a 9999 para probar el
  formateador. El perfil de contrato usa los rangos del emisor físico y
  conserva la validación de Android.
- Android marca como prueba el nombre anunciado `HealthBand-Test` y ofrece
  selección manual para anuncios sin nombre o para PPG sintética desde FPGA.
  El indicador determina la referencia y la clasificación en Room.
- Confirmar el breakout y niveles I²C, el pin RX del módulo, el retorno
  de advertising y la fragmentación física. El maestro I²C carece de
  clock stretching. Los umbrales PPG requieren caracterización física.
  SpO₂ queda fuera del MVP.
- Icarus informó advertencias de timescale heredado y tamaño de los estímulos
  respecto del arreglo del banco. Android lint conserva advertencias de
  dependencias y recursos registradas en su informe.

## Cierre del repositorio

La integración se incorporó por fast-forward a `develop` en el directorio
principal. Los entregables se conservan por componente en `mobile/artifacts/`
y `esp32/artifacts/`. Los reportes están en `mobile/evidence/`,
`esp32/evidence/`, `fpga/evidence/` y `shared/evidence/`.

[Manifiesto de entregables](ARTIFACTS_MANIFEST.md) ·
[Responsabilidades](RESPONSIBILITIES.md) ·
[Guía física](PHYSICAL_INTEGRATION_GUIDE.md)

La verificación de cierre ejecuta `bash shared/test_hb1.sh` y
`bash fpga/sim/run_icarus.sh`. Los resultados de instrumentación, lint y
compilación se conservan de la integración. El estado de mesa se registra
en la checklist durante las pruebas físicas.
