# HealthBand

Prototipo académico de monitoreo fisiológico basado en FPGA. El sistema toma
muestras del sensor MAX30100, calcula BPM e IBI en una Terasic DE10-Lite,
transporta los resultados mediante un ESP32 y los presenta y analiza en una
aplicación Android.

HealthBand no es un dispositivo médico y no realiza diagnósticos.

## Arquitectura

```text
MAX30100 → I²C → FPGA (DE10-Lite) → UART → ESP32 → BLE → Android
```

La FPGA se encarga del procesamiento de señales y del cálculo de BPM e IBI.
El ESP32 actúa como puente UART–BLE. Android realiza la visualización, el
historial local y la detección personalizada de anomalías.

## Módulos

- [`fpga/`](fpga/): adquisición, procesamiento PPG, métricas y UART en Verilog.
- [`esp32/`](esp32/): puente UART–BLE y servicios GATT.
- [`mobile/`](mobile/): aplicación Android, visualización e historial local.
- [`ml/`](ml/): experimentación con la detección personalizada de anomalías.
- [`shared/`](shared/): interfaces y protocolo común.
- [`docs/`](docs/): arquitectura y decisiones del proyecto.

## Integración

Empieza por la [guía física](docs/PHYSICAL_INTEGRATION_GUIDE.md) y registra
cada resultado en el [checklist](docs/PHYSICAL_TEST_CHECKLIST.md). El
[estado de integración](docs/FINAL_INTEGRATION_STATUS.md) indica pruebas,
binarios y bloqueos. El recorrido automatizado RTL–C–Android se ejecuta
desde la raíz con `bash shared/test_hb1.sh`.

## Entrega para pruebas físicas

El [registro de responsabilidades](docs/RESPONSIBILITIES.md) asigna las
pruebas y el cierre a Sebas y Dani. La integración está en `develop`.
El [manifiesto](docs/ARTIFACTS_MANIFEST.md) describe los binarios, sus
sumas y cómo regenerarlos. El ZIP de entrega incluye los APK y el firmware.
Un clon obtiene fuentes, reportes y manifiestos. Para incorporar los binarios,
extrae el ZIP o compílalos siguiendo los README de cada proyecto.

Con los binarios ya ubicados en sus carpetas, ejecuta
`python3 shared/package_testing.py` desde la raíz. El resultado queda en
`deliverables/healthband-final-testing.zip`. Usa `--output` para generar
otra copia en una ruta nueva.
