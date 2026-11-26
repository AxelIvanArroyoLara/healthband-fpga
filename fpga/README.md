# FPGA

Procesamiento PPG en Verilog para la Terasic DE10-Lite: filtra la señal IR
del MAX30100, detecta pulsaciones, calcula BPM e IBI con indicador de validez
y transmite el resultado por UART con el protocolo HB1
([`../shared/PROTOCOL.md`](../shared/PROTOCOL.md)).

Las muestras vienen del MAX30100 real por I²C (`max30100_ctrl`, SW9 = 0) o
de un generador sintético (`ppg_synth`, SW9 = 1) para probar la cadena
FPGA → ESP32 → app sin el sensor.

## Estado

| Parte | Estado |
| --- | --- |
| Filtro, detector de pulsos, BPM/IBI, calidad | RTL escrito; algoritmo validado con el modelo de referencia ([`evidence/reference/summary.md`](evidence/reference/summary.md)) |
| UART 115200 8N1 + trama HB1 | RTL escrito, testbench de 100 tramas listo |
| Top-level DE10-Lite, displays, LEDs, QSF/SDC | RTL escrito |
| Simulación RTL | Corrida con Icarus (`sim/run_icarus.sh`): todos los testbenches pasan, incluido `tb_max30100_top`. Evidencias en [`evidence/rtl/`](evidence/rtl/) |
| Compilación Quartus, TimeQuest, potencia | Pendiente (recompilar: el `.sof` anterior no conectaba el I²C a los pines) |
| Controlador I²C del MAX30100 (`i2c_master` + `max30100_ctrl`) | RTL escrito y simulado con un modelo I²C del sensor (`tb_max30100_top`): configuración, lectura del FIFO por punteros, dedo retirado, desconexión y reconexión. Pendiente probar en la placa. Ver [Conectar el MAX30100](#conectar-el-max30100) |

## Estructura

```text
fpga/
├── rtl/                 Verilog sintetizable
│   ├── ppg_processor.v  Bloque con la interfaz acordada (instancia los tres siguientes)
│   ├── ppg_filter.v     Línea base + promedio móvil
│   ├── pulse_detector.v Umbral adaptativo, histéresis y periodo refractario
│   ├── bpm_calc.v       Validación de intervalos, BPM e IBI
│   ├── hb1_framer.v     Trama HB1 una vez por segundo
│   ├── uart_tx.v        UART 8N1
│   ├── bin_to_bcd.v     Binario a BCD (trama y displays)
│   ├── seg7_bpm.v       BPM en HEX2..HEX0
│   ├── ppg_synth.v      Generador PPG sintético sintetizable
│   ├── i2c_master.v     Maestro I²C por bytes (open drain)
│   ├── max30100_ctrl.v  Configura el MAX30100 y lee su FIFO a 100 muestras/s
│   ├── healthband_top.v Top-level de la DE10-Lite
│   └── old_sebas/       Borradores anteriores del I²C (solo referencia, no se compilan)
├── tb/                  Testbenches
├── model/               Modelo de referencia y generador de estímulos (Python 3, sin dependencias)
├── stim/                Señales sintéticas usadas por los testbenches
├── sim/                 Scripts para Icarus Verilog y ModelSim/Questa
├── quartus/             Proyecto, pines (QSF) y reloj (SDC)
└── evidence/            Resultados del modelo y de la simulación RTL
```

## Interfaz de `ppg_processor`

Estos son los puertos que Sebas debe conectar desde el controlador del
MAX30100 y los que consume el resto de la FPGA.

| Señal | Dir. | Ancho | Significado |
| --- | --- | --- | --- |
| `clk` | in | 1 | Reloj de 50 MHz. |
| `reset_n` | in | 1 | Reset asíncrono activo en bajo. |
| `ir_sample` | in | 16 | Muestra IR cruda del FIFO del MAX30100 (sin signo, cuentas del ADC). |
| `red_sample` | in | 16 | Muestra RED cruda. Reservada para SpO₂ (extensión experimental); hoy no se usa. |
| `sample_valid` | in | 1 | Pulso de 1 ciclo cuando `ir_sample`/`red_sample` traen una muestra nueva. Se esperan 100 muestras/s. |
| `fifo_overflow` | in | 1 | Pulso de 1 ciclo si el FIFO del sensor perdió muestras. |
| `bpm` | out | 8 | Frecuencia cardíaca en pulsaciones por minuto, promedio de los últimos 4 latidos. Solo es significativa con `data_valid = 1`. |
| `ibi_ms` | out | 16 | Intervalo entre los dos últimos latidos, en milisegundos (10 ms por muestra). Solo con `data_valid = 1`. |
| `beat_valid` | out | 1 | Pulso de 1 ciclo por cada latido detectado. |
| `data_valid` | out | 1 | 1 = `bpm` e `ibi_ms` son una medición válida. Es el campo `Q` de HB1. |
| `signal_quality` | out | 5 | Banderas de calidad; `00000` = sin fallas (ver abajo). |

`signal_quality`:

| Bit | Nombre | Se activa cuando | Se limpia |
| --- | --- | --- | --- |
| 0 | Saturación | `ir_sample >= 0xFF00` | Al volver a `data_valid = 1` |
| 1 | Sin contacto | `ir_sample < 8000` (dedo retirado) | Al volver a `data_valid = 1` |
| 2 | FIFO | `fifo_overflow = 1` | Al volver a `data_valid = 1` |
| 3 | Muestras perdidas | Pasan más de 15 ms sin `sample_valid` | Al volver a `data_valid = 1` |
| 4 | Amplitud baja | La envolvente del pulso es menor que 20 cuentas | En cuanto la amplitud se recupera |

Los umbrales de saturación, contacto y amplitud son parámetros
(`SAT_LEVEL`, `CONTACT_MIN`, `MIN_AMP`) y deben ajustarse con las capturas
reales de Sebas.

## Algoritmo

Todo trabaja con enteros, sumas y desplazamientos, una vez por muestra (100 Hz).

1. **Línea base y suavizado** (`ppg_filter`). `base = acc >> 5` es una media
   exponencial (fc ≈ 0.5 Hz) que sigue la componente DC y la deriva lenta.
   `ac = base − ir` invierte la señal para que la sístole quede positiva
   (el MAX30100 lee menos luz cuando llega sangre). Un promedio móvil de 8
   muestras quita el ruido de alta frecuencia. Anchos: `acc` de 22 bits,
   `ac` de 18 bits con signo y la suma de 21 bits, sin desbordamiento posible
   para entradas de 16 bits.
2. **Detección de pulsos** (`pulse_detector`). La envolvente `env` sigue el
   máximo de la señal y decae `env/128` por muestra. Hay latido cuando la
   señal supera `env/2`, el detector está armado (la señal bajó de 0 desde el
   latido anterior), `env ≥ 20` y pasaron al menos 25 muestras (250 ms,
   240 BPM). La histéresis y el periodo refractario evitan contar dos veces la
   onda dicrótica.
3. **BPM e IBI** (`bpm_calc`). Con `N` muestras entre latidos, `IBI = 10·N`
   ms y `BPM = 6000/N`. Se aceptan `N` de 25 a 200 (240 a 30 BPM). Si un
   intervalo difiere más de 25 % del anterior se reinicia la cuenta de
   estabilidad. `data_valid` sube con 4 intervalos consistentes seguidos y
   `bpm = round(24000 / suma de los 4)` con un divisor secuencial de 16 ciclos
   (no hay división entre cero: la suma mínima es 100). Más de 2 s sin
   latido invalida la medición.
4. **Fallas**. Saturación, falta de contacto, `fifo_overflow` o un hueco de
   muestras descartan la muestra y reinician filtro, detector y cálculo:
   `data_valid` baja en el acto y no vuelve hasta 4 latidos consistentes
   (≈ 4–5 s).

El modelo [`model/ppg_model.py`](model/ppg_model.py) implementa lo mismo bit a
bit en Python; si se cambia un parámetro hay que cambiarlo en ambos lados.

## Protocolo UART (salida de la FPGA)

- UART 115200 baudios, 8N1, 3.3 V, pin `GPIO[2]` (JP1 pin 3, `PIN_V9`) hacia
  el RX del ESP32. Tierra común obligatoria.
- Una trama por segundo, siempre, haya o no medición válida.
- Trama ASCII de 36 bytes terminada en `\n` (sin `\r`):
  `HB1,SEQ=000012,BPM=075,IBI=0800,Q=1\n`

### Mediciones inválidas (Q=0)

Cuando `data_valid = 0` la FPGA envía **`BPM=000`, `IBI=0000` y `Q=0`**, por
ejemplo `HB1,SEQ=000013,BPM=000,IBI=0000,Q=0`. Nunca se envía un BPM con
`Q=0`, para que ningún consumidor pueda tomarlo por bueno. Q=0 aparece al
encender (los primeros 3–5 s, mientras se estabiliza), con el dedo retirado,
con saturación, con muestras perdidas y con señal sin pulso.

### Secuencia y reinicio de la FPGA

- `SEQ` arranca en `000000` al encender o al pulsar KEY0 (reset); la primera
  trama sale 1 s después.
- Aumenta en 1 en cada trama, incluidas las de Q=0, y pasa de `999999` a
  `000000` (cada 11.5 días a 1 trama/s).
- La FPGA no guarda la secuencia entre reinicios: tras un reset vuelve a
  `000000`.

Tras un reset físico, desconecta y vuelve a elegir el ESP32 en Android.
Dentro de una conexión sigue vigente la regla circular del
[contrato HB1](../shared/PROTOCOL.md).

## Simulación

Los testbenches son Verilog-2001 y corren en Icarus Verilog o en
ModelSim/Questa (incluido con Quartus Prime Lite). Los estímulos ya están en
`stim/`; para regenerarlos solo hace falta Python 3.

| Testbench | Qué verifica |
| --- | --- |
| `tb_ppg_processor` | 12 señales sintéticas: 60/75/100/120 BPM, ruido, onda dicrótica, doble pico, saturación, dedo retirado, muestras perdidas, `fifo_overflow` y señal plana. Escribe latidos y salidas por segundo; `model/compare_rtl.py` las compara con el modelo. |
| `tb_hb1_uart` | `hb1_framer` + `uart_tx` a 50 MHz y 115200 reales. Reconstruye 100 tramas con un receptor UART y compara cada carácter, incluidas tramas Q=0 e IBI > 9999. |
| `tb_healthband_top` | Sistema completo con el generador sintético (SW9 = 1) y los interruptores: 75 BPM, dedo retirado, recuperación, 120 BPM con ruido y saturación, leyendo las tramas del pin UART. |
| `tb_max30100_top` | Sistema completo con el sensor (SW9 = 0) usando `max30100_model`, un modelo I²C del MAX30100 con registros, FIFO, punteros y su propio reloj de muestreo (0.5 % más lento). Verifica la configuración escrita, PART_ID, el cambio de corriente con SW7..SW5, 72 y 90 BPM, dedo retirado, desconexión (NACK) y reconexión automática. |

Con Icarus (Git Bash):

```bash
bash fpga/sim/run_icarus.sh
```

Con ModelSim/Questa, desde la carpeta `fpga/`:

```bash
python3 -I model/gen_stimulus.py
python3 -I model/run_reference.py
vsim -c -do sim/run_questa.do
python3 -I model/compare_rtl.py
```

Para capturas de formas de onda: `vsim -do sim/wave_processor.do`.

Evidencias que quedan en `evidence/rtl/`: CSV de latidos y por segundo,
`compare.md` (RTL vs. modelo), `hb1_frames.txt` (listado de las 100 tramas),
`top_frames.txt` y `sim_log.txt`.

## Prueba en la placa

1. En un equipo con Quartus Prime Lite y soporte MAX 10, abre
   `quartus/healthband.qpf` y ejecuta **Processing → Start Compilation**, o
   ejecuta `quartus_sh --flow compile healthband` desde `fpga/quartus`.
   Revisa `output_files/healthband.fit.rpt` y `output_files/healthband.sta.rpt`,
   incluyendo recursos, reloj de 50 MHz y slack, antes de usar
   `output_files/healthband.sof` en el Programmer.
2. Conectar el MAX30100 y el ESP32 como se indica abajo.
3. Interruptores:

| SW | Función |
| --- | --- |
| SW9 | Fuente: 0 = MAX30100 (sensor real), 1 = generador sintético |
| SW8 | Display de depuración: HEX3..HEX0 = IR crudo en hexadecimal, HEX5..HEX4 = PART_ID del sensor (debe decir `11`) |
| SW7..SW5 | Corriente de los LEDs del sensor: 000 = 24 mA (por defecto), 001 = 11, 010 = 17.4, 011 = 24, 100 = 30.6, 101 = 37, 110 = 43.6, 111 = 50 mA |
| SW1..SW0 | Solo sintético: BPM 00 = 60, 01 = 75, 10 = 100, 11 = 120 |
| SW2 | Solo sintético: ruido |
| SW3 | Solo sintético: dedo retirado → Q=0 |
| SW4 | Solo sintético: saturación → Q=0 |

KEY0 es reset. HEX2..HEX0 muestran el BPM o `---`; LEDR0 parpadea con cada
latido, LEDR1 es Q, LEDR6..LEDR2 son `signal_quality`, LEDR7 indica UART
transmitiendo, LEDR8 = MAX30100 configurado y respondiendo por I²C y LEDR9 =
fuente sintética activa.

Prueba sin sensor: SW = 1000000001 (SW9 y SW0 arriba) → la app debería
mostrar 75 BPM a los ~5 s (prueba compartida 1).

Prueba con sensor: todos los SW abajo, dedo sobre el sensor sin apretar ni
moverlo. LEDR8 se activa tras configurar el sensor. Espera varios latidos antes de comparar el display.

## Conectar el MAX30100

| MAX30100 (módulo) | DE10-Lite | Señal en el diseño |
| --- | --- | --- |
| VIN | JP1 pin 29 ofrece 3,3 V. Usar solo si se confirma compatibilidad del breakout. | Alimentación según el módulo |
| GND | JP1 pin 30 (o pin 12) | — |
| SCL | JP1 pin 1 (`PIN_V10`) | `GPIO[0]` |
| SDA | JP1 pin 2 (`PIN_W10`) | `GPIO[1]` |
| INT, IRD, RD | sin conectar | — |

| ESP32 | DE10-Lite |
| --- | --- |
| RX (p. ej. GPIO16 / RX2) | JP1 pin 3 (`PIN_V9`, `GPIO[2]`, TX de la FPGA) |
| GND | JP1 pin 12 o 30 (tierra común obligatoria) |

Notas:

- El I²C va a 100 kHz. SCL y SDA son open drain y tienen el pull-up débil
  interno de la FPGA activado en el QSF; aun así conviene que el módulo tenga
  sus resistencias de pull-up (casi todos las traen).
- SCL se libera en open drain, pero el maestro no lee SCL y carece
  de clock stretching. El datasheet y el modelo usado permiten el flujo
  previsto con el MAX30100 a 100 kHz. Si SCL sigue bajo al liberarse,
  comprueba niveles, reposo y tiempos de subida con analizador lógico.
- Identifica en el breakout las alimentaciones y el rail de los pull-ups.
  Mide SDA/SCL en reposo y verifica umbrales de ambos extremos antes de
  decidir si se necesita adaptar niveles.
- Diagnóstico rápido con SW8 = 1: si HEX5..HEX4 muestran `11` el I²C funciona.
  Con el dedo puesto el IR crudo (HEX3..HEX0) debe estar más o menos entre
  `2000` y `F000` (8 000–61 000) y variar un poco con el pulso. Si está cerca de
  `FFFF` (saturado) bajar la corriente con SW7..SW5; si es menor que `1F40`
  (8 000, "sin contacto") subirla. Los umbrales están en `ppg_processor`
  (`CONTACT_MIN`, `SAT_LEVEL`).
- Si el sensor se desconecta, `max30100_ctrl` lo reintenta cada 100 ms y lo
  reconfigura solo al volver.

## Pendientes

- Compilar en Quartus, revisar warnings, TimeQuest y Power Analyzer (paso 5 de la guía).
- Probar el MAX30100 real en la placa (LEDR8, PART_ID = `11`, IR crudo con SW8).
- Ajustar `CONTACT_MIN`, `SAT_LEVEL` y `MIN_AMP` con el CSV real del MAX30100.
- SpO₂ queda fuera del MVP. El canal RED se adquiere para usos futuros.
- El QSF coincide con el mapa JP1 del manual Terasic, figura 3-18 y tabla 3-7.
  [Manual DE10-Lite](https://www.mouser.com/datasheet/3/996/1/DE10-Lite_User_Manual.pdf)
  [Datasheet MAX30100](https://www.analog.com/media/en/technical-documentation/data-sheets/MAX30100.pdf)
- Limitación conocida: si la deriva de la línea base es mayor que el pulso, o
  la onda dicrótica es casi tan alta como la sístole, el detector no logra
  estabilizarse y reporta Q=0 (caso `doublepeak075`). Es el comportamiento
  observado en ese escenario sintético.
