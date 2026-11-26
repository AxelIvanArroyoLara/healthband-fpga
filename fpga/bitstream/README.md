# Archivos listos para programar la DE10-Lite

Compilados con **Quartus Prime 21.1.1 Build 850 Lite** (la misma versión del
laboratorio) a partir de `fpga/quartus/healthband.qpf`, sin errores. Detalles
en [`../evidence/quartus/`](../evidence/quartus/).

| Archivo | Para qué | SHA-256 |
| --- | --- | --- |
| `healthband.sof` | Programar la FPGA (se pierde al apagar) | `b31fdf9e65c65aa09a927e8d51c37dbf1306db4f412ba7db3833ee646d841e7e` |
| `healthband.pof` | Grabar en la memoria flash interna (CFM); queda al apagar | `6e09c1709daf930f9cc4889278f0b3898c9bbe9fe598a11fa8aed18ccddd2e6b` |

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
al commit en el que se agregaron.

Conexiones y uso: [`../DEMO.md`](../DEMO.md).
