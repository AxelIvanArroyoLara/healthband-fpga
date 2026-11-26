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

El [contrato HB1](../shared/PROTOCOL.md) especifica UART, framing,
secuencia y GATT. NimBLE en ESP32 clásico conserva líneas completas y calcula
el límite de notificación con MTU ATT menos tres. Kotlin, Compose, MVVM y
Room implementan el monitor, el parser y la persistencia local.

## Orden de integración

1. ESP32 simulado → Android.
2. FPGA con señales sintéticas → ESP32 → Android.
3. MAX30100 real → FPGA → ESP32 → Android.

## Limitaciones conocidas

- HB1 carece de identificador de arranque. Tras reiniciar la FPGA, se abre
  una adquisición BLE nueva.
- Están pendientes la variante exacta ESP32S, el breakout y la prueba física.
- El análisis personalizado es experimental y no médico.
- La calidad depende de sensor, contacto, alimentación y calibración.
- [FPGA](../fpga/README.md) describe los filtros, interfaces y pruebas.
  El [checklist](PHYSICAL_TEST_CHECKLIST.md) define la aceptación física.

La [matriz de responsabilidades](RESPONSIBILITIES.md) indica quién verifica
cada tramo y dónde se documenta la aceptación física.
