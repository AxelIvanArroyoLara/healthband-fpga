# Arquitectura

## Flujo principal

```text
MAX30100 ── I²C ──> DE10-Lite ── UART 115200 ──> ESP32 ── BLE ──> Android
```

El MAX30100 produce muestras IR/RED. La FPGA las adquiere, procesa la señal
PPG, detecta pulsaciones y calcula BPM, IBI y calidad. El ESP32 transporta las
tramas UART como notificaciones BLE. Android las valida, visualiza, almacena y
analiza respecto de una línea base individual.

## Responsabilidades técnicas

- **MAX30100:** sensor óptico y fuente de muestras IR/RED.
- **Terasic DE10-Lite:** adquisición I²C, procesamiento PPG, detección de
  pulsaciones, BPM, IBI, calidad, UART y displays.
- **ESP32:** puente UART–BLE, servicio GATT, conexión y consumo energético.
- **Android:** conexión BLE, parser, dashboard, historial local, línea base y
  detección personalizada experimental.

## Desarrollo independiente

Cada módulo debe poder probarse sin esperar al hardware completo. FPGA puede
usar señales sintéticas; ESP32 puede recibir tramas UART simuladas; Android
puede usar un simulador de mensajes y pruebas del parser. Las interfaces
comunes se mantienen en [`../shared/`](../shared/).

## Interfaces y principios

El protocolo provisional define el intercambio de mediciones; las decisiones
BLE se documentarán cuando se aprueben. Se aplican ETC (evitar complejidad
prematura y mantener puntos de cambio explícitos) y DRY (una sola definición
del contrato compartido), sin duplicar reglas de validación entre módulos.

## Orden de integración

1. ESP32 simulado → Android.
2. FPGA con señales sintéticas → ESP32 → Android.
3. MAX30100 real → FPGA → ESP32 → Android.

## Limitaciones conocidas

- El protocolo, UUID BLE, límites de campos y reconexión no son definitivos.
- El framework Android y el modelo exacto de ESP32 están pendientes.
- El análisis personalizado es experimental y no médico.
- La calidad depende de sensor, contacto, alimentación y calibración.
- Aún no están definidos los algoritmos de filtrado, las interfaces Verilog ni
  las métricas de aceptación.
