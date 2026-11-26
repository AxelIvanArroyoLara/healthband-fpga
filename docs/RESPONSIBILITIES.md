# Responsabilidades para el cierre físico

Axel concluyó sus contribuciones a Android y a la integración. Su autoría,
sus commits y la rama `feature/axel-mobile` se conservan.
**Tareas pendientes de Axel: 0.**

## Sebas · hardware, ESP32S y Bluetooth

- [ ] Identificar placa y breakout. Verificar alimentación, niveles, SDA/SCL,
  pull-ups, tierra común y disponibilidad de GPIO16. Elegir otro RX seguro
  si corresponde.
- [ ] Medir corriente y consumo con instrumentos. Estimar autonomía cuando
  se conozcan capacidad utilizable y condiciones de uso.
- [ ] Seleccionar, recompilar cuando proceda y flashear BLE_TEST. Verificar
  advertising, servicio, CCCD, Notify y tramas sintéticas.
- [ ] Instalar el APK debug. Conceder permisos, confirmar UUID y conectar.
  Medir 100 tramas, comprobar fragmentación, Q=0, caducidad y reconexión.
- [ ] Flashear UART_BRIDGE. Verificar la recepción UART y depurar el transporte.
  Registrar capturas y logs. Responsable de B, C1 y C2.

## Dani · FPGA y validación funcional de Android

- [ ] Compilar en Quartus, generar SOF, programar la DE10-Lite y guardar
  utilización, avisos, TimeQuest y Power Analyzer cuando haya actividad.
- [ ] Probar PPG sintética a 60, 75, 100 y 120 BPM. Contrastar BPM, IBI, Q,
  displays y UART. Caracterizar parámetros PPG con el sensor real.
- [ ] Verificar simulación normal y errores intencionales. Revisar monitor,
  gráficas y persistencia Room. Consultar y eliminar una sesión de prueba.
- [ ] Calibrar con tres sesiones de reposo. Verificar pico breve, elevación
  sostenida, consulta del episodio y guardado del contexto. Depurar lógica
  o presentación y guardar evidencias. Responsable de A1–A4 y D1–D2.

## Sebas y Dani · integración y cierre

- [ ] Integrar FPGA → ESP32S → Android con PPG sintética y luego con el
  MAX30100. Confirmar que la FPGA procesa la señal y el puente conserva
  HB1. Comparar el display, las tramas UART y la lectura Android.
- [ ] Probar pérdida y recuperación del contacto, reset de la FPGA y
  reapertura de adquisición para reiniciar el parser. Realizar un ensayo
  de al menos diez minutos y registrar calidad, pérdidas y reinicios.
- [ ] Corregir fallos comprobados, justificar cambios de protocolo,
  recopilar evidencias, actualizar documentación y preparar entregables.
  Publicar mediante el flujo Git acordado cuando exista autorización.
  Responsables de E–H.

[Guía de montaje y diagnóstico](PHYSICAL_INTEGRATION_GUIDE.md) ·
[Checklist de aceptación](PHYSICAL_TEST_CHECKLIST.md)
