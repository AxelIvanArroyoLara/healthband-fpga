# Evidencia Android

- `jvm/TEST-*.xml` conserva 24 resultados JVM. Los reportes
  `AnomalyDetectorTest` y `SimulatorScenariosTest` cubren calibración,
  ruido, continuidad y elevación sostenida.
- `android-instrumented.xml` y `android-instrumented.log` conservan
  las 15 pruebas en emulador API 37, incluyendo aislamiento de BLE
  sintético, salto de SEQ, Room y recreación de actividad.
- `lint-results-debug.html` y `lint-results-debug.txt` registran
  0 errores y 7 advertencias. `android-build.log` conserva la compilación
  debug y release de la integración.
- [Verificación de contrato y JVM del cierre](../../shared/evidence/README.md).

Las rutas de la máquina se normalizaron en los reportes distribuidos.
La validación en el teléfono físico se registra en la checklist de mesa.
