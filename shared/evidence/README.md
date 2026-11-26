# Evidencia HB1 entre componentes

- `uart-contract.log` registra la captura de 100 tramas del UART RTL.
  Los bytes fuente están en [fixtures](../fixtures/README.md).
- `notifications.txt` contiene las notificaciones en hexadecimal,
  agrupadas por perfil de MTU 23, 39 y 247 con fragmentos de hasta 7 bytes.
- `contract-and-jvm.log` registra el cierre RTL → C → JVM. El parser
  compara cada byte, LF, SEQ, validación y campos en los tres perfiles.
  Se ejecutaron las 24 pruebas JVM.
- [Prueba C del puente](../../esp32/evidence/framing-c.log).

Ejecuta `bash shared/test_hb1.sh` desde la raíz del repositorio. Los
intermedios regenerados quedan en `shared/build/hb1/`.
