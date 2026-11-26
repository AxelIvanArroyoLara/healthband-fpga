# Archivos listos para programar la DE10-Lite

Compilados con **Quartus Prime 21.1.1 Build 850 Lite** (la misma versión del
laboratorio) a partir de `fpga/quartus/healthband.qpf`, sin errores. Detalles
en [`../evidence/quartus/`](../evidence/quartus/).

| Archivo | Para qué | SHA-256 |
| --- | --- | --- |
| `healthband.sof` | Programar la FPGA (se pierde al apagar) | `cdd1ce029e2590a69256e3262d68bb0c10d7dd456645a10e143cf2f8dabb9847` |
| `healthband.pof` | Grabar en la memoria flash interna (CFM); queda al apagar | `962ddbf827ad25fe268a20f568541f1f239a2a3219ad2e714c80312ee3c226ae` |
| `i2c_scan.sof` | Diagnóstico: busca el sensor en todos los pines del JP1 ([detalles](../diag/i2c_scan/README.md)) | `788826bed508bd3a6f83e9e5acf1e93c590831d566e58f832e4d9a2a782fd172` |

## Programar sin compilar

1. Conectar la DE10-Lite por USB (conector USB-Blaster).
2. Abrir **Quartus Prime → Tools → Programmer** (o `quartus_pgmw`).
3. **Hardware Setup** → seleccionar **USB-Blaster** → Close.
4. Mode: **JTAG**. **Add File…** → `healthband.sof` → marcar **Program/Configure**.
5. **Start**. La barra llega a 100 % y LEDR8 se enciende si el sensor está conectado.

Para que el diseño quede grabado aunque se apague la placa, usar
`healthband.pof` en el paso 4 (marcar Program/Configure en la fila `CFM0`).

Desde la terminal:

```sh
quartus_pgm -m jtag -o "p;healthband.sof"
```

Si se cambia el Verilog hay que volver a compilar: estos archivos corresponden
al commit en el que se agregaron. Este `healthband.sof` es el que se probó en la
DE10-Lite el 2026-11-26 con el MAX30100 real y el ESP32 (UART_BRIDGE → app).

Conexiones y uso: [`../DEMO.md`](../DEMO.md).
