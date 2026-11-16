# FPGA

Este módulo contiene el procesamiento Verilog que se ejecutará en la Terasic
DE10-Lite.

## Responsabilidades

- Adquirir muestras IR/RED del MAX30100 mediante I²C.
- Filtrar la señal PPG y detectar pulsaciones.
- Calcular BPM, IBI e indicadores de validez.
- Transmitir mediciones por UART y mostrar indicadores en displays de siete
  segmentos.
- Incluir testbenches, síntesis y validación en Quartus.

Sus interfaces con el resto del sistema se describen en
[`../shared/PROTOCOL.md`](../shared/PROTOCOL.md). Todavía no se generan
módulos Verilog ni archivos de proyecto.
