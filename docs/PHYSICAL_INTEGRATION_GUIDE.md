# Guía de integración física

Sebas y Dani realizan las pruebas A–H en orden y registran la evidencia en el
[checklist](PHYSICAL_TEST_CHECKLIST.md). El objetivo es verificar adquisición,
transporte y estabilidad del prototipo académico.

## Material y archivos

- Terasic DE10-Lite, breakout MAX30100 identificado, placa ESP32S identificada
  y teléfono Android con BLE.
- Cables USB de datos, jumpers, alimentación apropiada, multímetro y, si están
  disponibles, analizador lógico o adaptador UART TTL de 3,3 V.
- Computadora con Quartus Prime Lite, soporte MAX 10 y controlador USB-Blaster.
  Computadora con ESP-IDF v5.5.6 para ESP32 clásico.
- [Manifiesto de binarios y evidencias](ARTIFACTS_MANIFEST.md).
  [Contrato y UUID HB1](../shared/PROTOCOL.md).
  [Fuentes y evidencias FPGA](../fpga/README.md).
  [Configuraciones y carga ESP32](../esp32/README.md).

Desde la raíz del repositorio, `cd mobile && ./gradlew assembleDebug` genera
`mobile/app/build/outputs/apk/debug/app-debug.apk` relativo a la raíz.
Desde `fpga/quartus/`, `quartus_sh --flow compile healthband` genera
`output_files/healthband.sof` y los reportes. Abre la revisión `healthband`
del proyecto `healthband.qpf`. Comprueba asignaciones, dispositivo
10M50DAF484C7G, utilización y TimeQuest a 50 MHz. Registra advertencias.
Power Analyzer requiere actividad representativa y estima potencia FPGA.
Mide consumo del sistema con instrumentos.

## Verificación eléctrica

Identifica variante ESP32S, revisión DE10-Lite y referencia del breakout.
Con placas apagadas, confirma numeración del JP1 y continuidad de tierra.
Antes de unir señales, mide las alimentaciones y los niveles de reposo por
separado. Confirma que el RX del ESP32 y el bus I²C son compatibles con los
niveles medidos. Documenta el rail y los pull-ups de SDA/SCL y verifica sus
tiempos de subida a 100 kHz. Desenergiza antes de cablear. Usa las entradas
de alimentación indicadas por cada fabricante. Mantén JP1 pin 11 (5 V)
apartado de las señales y evita alimentar la FPGA por GPIO.

| Conexión | Confirmado por QSF/manual | Depende de la placa física |
| --- | --- | --- |
| MAX30100 SCL | JP1 pin 1, GPIO[0], PIN_V10, open drain | Pin SCL y nivel alto del breakout |
| MAX30100 SDA | JP1 pin 2, GPIO[1], PIN_W10, open drain | Pin SDA y nivel alto del breakout |
| FPGA TX → ESP32 RX | JP1 pin 3, GPIO[2], PIN_V9, LVTTL 3,3 V | RX configurado en UART2/GPIO16 por defecto. Confirmar disponibilidad o cambiar en menuconfig |
| GND común | JP1 pin 30 o 12 | Pines GND reales de los módulos |
| Alimentación del breakout | JP1 pin 29 ofrece 3,3 V | Usarlo solo si el breakout admite esa entrada y su corriente cabe en el presupuesto. El IC desnudo usa rails distintos |
| ESP32 TX y sensor INT | Sin conexión para este flujo | — |

Conserva el breakout sin modificaciones hasta confirmar el esquema y medir
los niveles. Ante incompatibilidad, usa la adaptación de nivel correspondiente.
[Manual Terasic, figura 3-18 y tabla 3-7](https://www.mouser.com/datasheet/3/996/1/DE10-Lite_User_Manual.pdf)
[Datasheet MAX30100](https://www.analog.com/media/en/technical-documentation/data-sheets/MAX30100.pdf)

## A. Android independiente · Dani

1. Instala el [APK debug](../mobile/artifacts/app-debug.apk) en el teléfono.
   En **Monitor**, pulsa **Iniciar simulación**. Verifica BPM (pulsos por
   minuto), IBI (milisegundos entre pulsos), gráfica y tramas aceptadas.
   Detén la adquisición y comprueba las lecturas guardadas en **Historial**.
2. Pulsa **Simular errores de comunicación** durante 20 s. Comprueba
   duplicado y formato incorrecto en rechazadas. En la trama 15, Q=0 deja
   la lectura vacía, abre un corte de gráfica y queda fuera de estadísticas.
3. Para demostrar el análisis, guarda tres sesiones independientes con
   **Registrar como sesión de reposo** y simulación normal. Espera al menos
   20 lecturas confirmadas en cada una. Desmarca reposo y activa
   **Simular elevación sostenida**. Confirma que aparece la referencia de
   tres sesiones y un episodio alrededor de la trama 21. La elevación es
   de 105 BPM entre las tramas 6 y 28. Detén, abre **Historial**, selecciona
   la sesión y pulsa **Añadir contexto** en el episodio. Vuelve a abrirla
   para comprobar que se guardó la anotación. Usa una sesión de prueba
   separada para verificar **Eliminar sesión**. Para comprobar un pico
   breve, inicia otra elevación simulada y detén la adquisición pocos
   segundos después de que aparezcan 105 BPM. Consulta el historial y
   confirma que la sesión breve no contiene un episodio sostenido.
4. El algoritmo exige al menos tres sesiones con 20 lecturas válidas por
   sesión. El umbral suma a la mediana el mayor incremento entre 12 BPM,
   15 % y 3 veces la MAD escalada por 1,4826. Exige 15 s y 10 muestras
   consecutivas con separación de hasta 2,5 s. Un hueco confirmado por
   SEQ o Q=0 corta la continuidad. Las sesiones con episodios guardados
   quedan fuera de la referencia. La referencia de simulación es independiente
   de la física.

## B. ESP32 independiente · Sebas

1. Identifica el ESP32 clásico y su puerto. Verifica y flashea el paquete
   [BLE_TEST](../esp32/artifacts/ble-test/README.md) y abre el monitor serie.
2. Abre el monitor. Debe anunciar `HealthBand-Test`. Si hay escáner BLE
   genérico, comprueba servicio, característica Notify y CCCD. Suscríbete y
   confirma fragmentos de hasta 7 bytes y una trama completa por segundo.
3. Cierra el escáner genérico para liberar la conexión antes de utilizar Android.

## C. ESP32 → Android · Sebas

1. Activa Bluetooth, abre **Configurar Bluetooth LE** y concede
   los permisos solicitados. Comprueba los [UUID HB1](../shared/PROTOCOL.md)
   y pulsa **Buscar dispositivos**. Elige `HealthBand-Test` o activa
   **Fuente BLE sintética** si el anuncio no tiene nombre. Espera la
   confirmación GATT y la primera trama.
2. Registra 100 tramas consecutivas. Compara SEQ, aceptadas y guardadas
   al cerrar. Repite con Q=0 desde el perfil BLE_TEST y verifica que la
   gráfica se corta y BPM/IBI quedan vacíos.
3. Fuerza una desconexión apagando el ESP32. Confirma que Android retira
   la lectura. Enciende de nuevo y selecciona el periférico. Debe iniciar
   una sesión nueva. Con UART_BRIDGE también puedes detener solo la fuente
   UART durante cuatro segundos y comprobar caducidad con el enlace activo.

## D. FPGA independiente · Dani

1. [Compila y programa el SOF](../fpga/artifacts/README.md) correspondiente
   a la revisión actual.
2. Activa SW9, deja SW8 apagado. Usa SW1–0 `00/01/10/11` para
   60/75/100/120 BPM. Espera estabilización y compara display con captura
   UART. El divisor 434 a 50 MHz da aproximadamente 115207 baudios.
3. Activa SW3 (sin contacto) y SW4 (saturación) por separado. Verifica
   guiones, LEDR1 apagado y tramas Q=0 con SEQ creciente. Desactívalos y
   verifica recuperación. SW2 agrega ruido. KEY0 reinicia SEQ.

## E. FPGA → ESP32 · Sebas y Dani

1. Flashea el paquete [UART_BRIDGE](../esp32/artifacts/uart-bridge/README.md). Apaga las placas, conecta JP1 pin 3 al RX verificado
   del ESP32 y GND común, y alimenta ambas placas.
2. Comprueba que el monitor registra líneas UART y, tras suscripción,
   tramas aceptadas por la pila. Captura FPGA TX a 115200 8N1 y verifica
   36 bytes incluido LF. Compara con el stream de notificaciones reconstruido.

## F. FPGA sintética → Android · Sebas y Dani

Mantén SW9 activo y marca **Fuente BLE sintética** antes de conectar.
Compara display, SEQ y Q con la captura UART, Android y el historial.
Considera la ventana de procesamiento PPG y el retardo de transporte.
Cambia el BPM y provoca Q=0. Tras KEY0, desconecta Android y vuelve a
elegir el puente para empezar con SEQ inicial.

## G. MAX30100 físico · Sebas y Dani

1. Verifica alimentación, niveles I²C y la corriente LED admitida. Apaga,
   fija SW7–5 según la corriente validada, conecta GND, SCL y SDA y
   energiza. Selecciona SW9=0. Con SW8=1 espera LEDR8 y `11` en HEX5–4.
   El controlador usa I²C a 100 kHz, dirección de 7 bits `0x57`,
   PART_ID `0x11`, modo IR+RED, 100 muestras/s y FIFO de 4 bytes por muestra.
2. Observa IR crudo en HEX3–0. Usa una corriente validada para ese breakout.
   Si hay que ajustar SW7–5, registra posición y corriente, y mantente
   dentro de los límites eléctricos del módulo. El modo por defecto da
   24 mA por LED y SW7–5=`001` selecciona 11 mA.
3. Desactiva SW8, coloca el dedo sin movimiento y espera estabilización.
   Comprueba BPM y Q. Retira el dedo, verifica Q=0 y recuperación al volver.
   Los parámetros `CONTACT_MIN`, `SAT_LEVEL` y `MIN_AMP` de
   `ppg_processor` requieren caracterización con el hardware de mesa.

## H. Sistema real · Sebas y Dani

Inicia una adquisición nueva con fuente BLE física. Verifica diez minutos
de extremo a extremo. Anota BPM, IBI, calidad, primeras y últimas secuencias,
aceptadas, rechazadas, guardadas, pérdidas e incidencias. Calcula pérdidas a
partir de huecos de SEQ dentro de cada conexión. Cuenta Q=0 como trama recibida.
Registra reinicios, temperatura, corriente y potencia cuando haya instrumentos.
Usa capturas de protocolo sintéticas o resultados agregados en el repositorio.

## Diagnóstico

| Síntoma | Qué revisar y aislar | Condición para avanzar |
| --- | --- | --- |
| FPGA no enciende | Cable de datos/alimentación, LED de alimentación y fuente indicada por Terasic. Desconecta periféricos para aislar la placa | Alimentación estable y placa activa |
| Quartus no reconoce la placa | USB-Blaster, controlador, cable de datos y selección en Hardware Setup. Ejecuta `jtagconfig` | MAX 10 listado en la cadena |
| MAX30100 no responde | LEDR8, GND, niveles de SCL/SDA, rail de pull-ups y ACK a 0x57. Si SCL sigue bajo, comprueba el bus con analizador | ACK y LEDR8 activo |
| PART_ID incorrecto | SW8, HEX5–4 y lectura del registro 0xFF. Verifica el marcado del IC | `11` estable |
| IR saturado o bajo | SW8 y HEX3–0. Aísla luz, contacto, alimentación y ajuste de corriente validado. Compara con `SAT_LEVEL`/ `CONTACT_MIN` | IR con margen y variación reproducible |
| BPM inestable, guiones o Q=0 | Prueba sintética conocida, LEDR6–2, luego contacto, FIFO, pérdidas y amplitud. Espera estabilización | Display y Q=1 coherentes en sintético y luego en señal real |
| UART sin bytes | JP1 pin 3, GND común, RX y perfil UART_BRIDGE. Mide TX antes del ESP32 | Una trama por segundo en el pin |
| UART ilegible | Velocidad, 8N1, referencia común, nivel TTL y lectura del LF en captura | HB1 ASCII estable |
| ESP32 sin anuncio | Monitor, perfil, alimentación y anuncio tras desconectar el cliente anterior | `HealthBand` o `HealthBand-Test` escaneable |
| Android no descubre | Permisos, Bluetooth activo, cercanía y escáner genérico como control | Periférico visible |
| GATT conecta sin Notify | UUID, estado CCCD, MTU, perfil, contador UART y suscripción en monitor | Confirmación CCCD y conteo de aceptadas creciente |
| Tramas malformadas | Compara UART bruto y fragmentos BLE en orden. Revisa LF, desbordes y fallos Notify | Reconstrucción byte a byte |
| SEQ rechazada después de reset | Confirma la captura UART y vuelve a seleccionar el puente en Android | Nueva adquisición acepta SEQ inicial |
| Huecos o pérdida de muestras | Compara contador UART, BLE y SEQ de Android con LEDR de FIFO y de muestras perdidas | Causa localizada y recuperación repetible |
| Room no almacena | Compara aceptadas, guardadas, Q y aviso de historial. Espera el cierre y abre Historial | Q=1 confirmadas y consultables |
| Detector sin referencia | Revisa origen físico/sintético, reposo, 20 válidas y exclusión de sesiones con episodios | Tres sesiones elegibles del mismo origen |
