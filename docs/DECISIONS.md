# Registro de decisiones

## Decisiones actuales

- La FPGA será una Terasic DE10-Lite.
- El procesamiento se implementará en Verilog.
- El sensor será un MAX30100.
- BPM e IBI se calcularán en la FPGA.
- El ESP32 será un puente UART–BLE.
- Android será la plataforma móvil.
- Los datos se almacenarán localmente por defecto.
- El análisis personalizado será experimental.
- El desarrollo será modular e independiente.
- La integración se realizará mediante Git y Pull Requests.

## Pendientes

Estas decisiones **no están aprobadas**:

- Framework Android.
- Modelo exacto de ESP32.
- UUID y configuración GATT.
- Protocolo definitivo.
- Algoritmos de filtrado y BPM.
- Interfaces entre módulos Verilog.
- Algoritmo de anomalías.
- Sistema de alimentación.
- Pruebas de aceptación y métricas.

## Implementación Android

- La captura publica primero las tramas interpretadas. Un escritor por
  adquisición confirma las lecturas válidas en Room en orden, con una cola de
  32 muestras y límites de espera al cerrar. Los avisos de almacenamiento
  se muestran por separado de los fallos de comunicación.
- El historial conserva interrupciones entre muestras válidas mediante marcas
  de segmento y tiempos de recepción. Los detalles de calidad de señal quedan
  fuera del esquema actual.
- Para una nueva adquisición se usa un parser HB1 nuevo. La identificación de
  un reinicio de la FPGA dentro de una conexión sigue pendiente de acuerdo
  junto con el modelo, los UUID y la configuración GATT del ESP32.

[Política Android y validación](../mobile/README.md)
