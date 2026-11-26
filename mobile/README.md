# HealthBand Android

Prototipo académico para recibir y visualizar mediciones PPG de HealthBand.
Se puede ejecutar en un emulador con el simulador HB1 o en un teléfono Android
con el puente ESP32 configurado.

## Auditoría inicial

La fase 1 ya tenía Compose, MVVM, un simulador y un parser HB1. Los archivos de
Gradle, el manifiesto y los recursos generados estaban presentes localmente.
La compilación inicial y la prueba de ejemplo pasaron con el JDK de Android
Studio. La revisión dio lugar a pruebas específicas del parser, estado de
secuencia por colección, descarte de líneas demasiado largas y limpieza de la
lectura al detener o interrumpir la adquisición.

## Instalación y ejecución

Abre la carpeta `mobile` en Android Studio. El proyecto usa Gradle 9.6, JDK 25,
AGP 9.4.1, Kotlin 2.2.10 y Compose BOM 2026.02.01. Instala la plataforma Android
37 para compilar. El SDK mínimo es 24 y `targetSdk` es 37. El identificador de
aplicación y el espacio de nombres son `com.example.healthband`.

Configura el SDK en Android Studio o indica su ruta con `ANDROID_HOME`. Si el
JDK de Android Studio es la única instalación de Java en macOS, selecciona
`JAVA_HOME` para los comandos de terminal.

```sh
# Ejemplo para Android Studio instalado en /Applications.
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug

# Con un emulador iniciado o un teléfono de pruebas conectado.
./gradlew :app:connectedDebugAndroidTest
```

El [paquete de pruebas](artifacts/README.md) incluye el APK debug instalable.
Desde `mobile/`, conecta un teléfono con depuración USB habilitada y acepta
su autorización. Comprueba la conexión con `adb devices` y ejecuta
`adb install -r artifacts/app-debug.apk`. Puedes instalar también desde el
gestor de archivos del teléfono si autorizas esa fuente.

La compilación genera `app/build/outputs/apk/debug/app-debug.apk`. Ejecuta
`./gradlew :app:assembleRelease` para generar el APK release, que requiere
firma antes de la instalación.

Para capturar logs, abre HealthBand y ejecuta desde la terminal:

```sh
pid=$(adb shell pidof -s com.example.healthband | tr -d '\r')
test -n "$pid" && adb logcat -d --pid="$pid" > healthband-android.log
```

Vuelve a obtener el PID si se reinicia la app. Para evidencias compartidas
utiliza simulación y elimina del log identificadores del teléfono o datos
personales.

## Monitor e historial

1. En **Monitor**, pulsa **Iniciar simulación** para recibir lecturas
   sintéticas válidas. Selecciona **Simular errores de comunicación** para
   probar duplicados, líneas incorrectas y Q=0. Para usar el puente,
   detén la simulación y abre **Configurar Bluetooth LE**.
2. Observa los contadores y la gráfica de hasta 60 posiciones. Q=0 retira los
   valores actuales y marca un corte. Si pasan cuatro segundos sin una trama
   aceptada, el monitor muestra datos obsoletos y conserva la gráfica.
3. Detén la fuente y abre **Historial**. Selecciona una sesión para consultar
   el intervalo, promedio, mínimo, máximo y la gráfica paginada. Se pueden
   eliminar sesiones o todo el historial con confirmación.

El historial empieza con la primera trama aceptada y solo guarda lecturas de
Q=1. Cada escritura confirma un punto de cierre recuperable. Si Android
termina el proceso abruptamente, la sesión queda guardada hasta la última
lectura confirmada. La adquisición usa el ciclo de vida de la actividad y
sobrevive a su recreación. Es una función de primer plano sin servicio de
monitoreo continuo.

Room 2.8.5 almacena el historial y sus episodios en una base privada.
KSP 2.3.12 genera las implementaciones de Room. La base queda excluida del
respaldo y la transferencia, y las reglas de Git ignoran los archivos SQLite.

### Publicación en vivo y confirmación de Room

El monitor publica las tramas interpretadas antes de enviarlas al escritor.
El contador de lecturas guardadas avanza cuando Room confirma la transacción.
Los avisos del historial aparecen por separado y la recepción sigue activa
si falla la lectura de la línea base, si Room falla al escribir o si se satura
la cola de grabación. Si la referencia tarda en cargarse, el análisis empieza
al disponer de ella y continúa con esa referencia durante el resto de la captura.

Cada adquisición tiene una cola FIFO de hasta 32 muestras válidas, más una
escritura en curso. Room abre la sesión y confirma su primera muestra válida
en una transacción. Las posteriores comparten esa sesión y confirman juntos
la lectura, su episodio si lo hay y el cierre recuperable. Si la cola se
llena, el escritor conserva el prefijo ya encolado y deja de aceptar muestras
de esa adquisición. Si una escritura falla, se descarta lo pendiente y se
conserva el prefijo ya confirmado.

Al detenerse o desconectarse, la captura libera su fuente y retira la lectura
actual. Se espera hasta cinco segundos por el drenaje. La actualización final
de Room tiene su propio límite de dos segundos. Esos plazos usan cancelación
cooperativa. Una operación nativa que tarde en devolver el control puede
retrasar el reinicio. Durante el cierre se mantiene deshabilitado el borrado
del historial. Un reinicio solicitado queda en espera, con su estado
propio, hasta que termine el cierre anterior. Una cancelación del ámbito o
una terminación del proceso puede perder las muestras todavía en cola. Un
cierre incompleto conserva la fecha de la última transacción confirmada.

### Calidad histórica

`startsSegment` y las marcas de tiempo de las muestras válidas permiten
separar segmentos tras Q=0, saltos de secuencia o caducidad de la lectura.
Una desconexión finaliza la adquisición y la reconexión guarda sus muestras
en otra sesión. Los datos guardados permiten identificar huecos entre dos muestras
válidas. El esquema actual omite el motivo exacto, el número de tramas Q=0
y el inicio preciso de un hueco sin muestras válidas que lo delimiten.
La gráfica histórica presenta muestras en orden y cortes, con un eje por muestra.

## Detección experimental

Marca **Registrar como sesión de reposo** antes de iniciar el monitor. Cada
fuente se calibra con al menos tres sesiones de reposo y veinte muestras válidas
por sesión. Usa hasta doce sesiones recientes, con hasta 300 lecturas por
sesión, y excluye las sesiones con episodios confirmados. La referencia es la
mediana de las medianas de sesión. La MAD también pondera cada sesión por igual.

El umbral suma a la referencia el mayor valor entre 12 BPM, 15 % de la
referencia y tres MAD escaladas con el factor 1,4826. Una elevación se confirma
al alcanzar al menos 15 segundos y diez muestras sobre el umbral. Una lectura
inválida o una interrupción superior a 2,5 segundos corta la ventana. La
referencia se fija al comenzar cada adquisición. Los valores están en
`AnomalyConfig`.

Para reproducir un episodio sin hardware, guarda tres sesiones simuladas de
reposo de al menos 30 segundos cada una. Pulsa **Simular elevación sostenida**
y espera hasta que se confirme el episodio. La fuente genera 105 BPM durante
23 muestras a partir de la sexta trama. Detén la sesión y abre el episodio
en **Historial** para consultar su duración, pico y diferencia respecto a
la referencia. Pulsa **Añadir contexto**, elige la opción y vuelve a abrir
la sesión para comprobar el guardado. Usa **Eliminar sesión** para probar
el borrado con una sesión de demostración.

El análisis describe desviaciones estadísticas del reposo. Los contextos son
anotaciones del usuario y este prototipo carece de validación clínica.
[MAD en el manual de estadística de NIST](https://www.itl.nist.gov/div898/handbook/eda/section3/eda356.htm)

## Configurar el ESP32 real

1. Confirma el modelo ESP32 clásico y el perfil flasheado. La característica
   de salida admite Notify con descriptor CCCD.
2. Enciende Bluetooth y abre **Configurar Bluetooth LE**. Los UUID iniciales
   coinciden con el puente. Puedes editarlos para otro periférico compatible.
   Marca **Fuente BLE sintética** para PPG sintética desde la FPGA o para
   un puente de prueba cuando el escaneo no muestre `HealthBand-Test`.
3. Pulsa **Buscar dispositivos**, concede los permisos solicitados y elige el
   ESP32. El escaneo dura hasta diez segundos y la suscripción hasta quince.
4. Tras una desconexión, vuelve a seleccionar el periférico para iniciar una
   sesión y un parser nuevos. La app mantiene las direcciones únicamente en
   memoria. Los permisos de ubicación solo se solicitan en Android 11 y
   anteriores para el escaneo de primer plano. Una terminación previa a la
   confirmación CCCD se presenta como fallo de conexión. Cuando el descriptor
   ya se confirmó, la terminación se presenta como desconexión.

Si reinicias la FPGA, desconecta y vuelve a elegir el periférico.
El simulador normal emite valores válidos. Usa **Simular errores de
comunicación** para duplicados, líneas malformadas y Q=0.
[Contrato HB1 de la app](PROTOCOL.md)
[Permisos Bluetooth de Android](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
[Conexión GATT en Android](https://developer.android.com/reference/android/bluetooth/BluetoothDevice)

## Validación

| Recorrido | Verificación |
| --- | --- |
| Fragmentos HB1 → parser → estado | Pruebas JVM con lotes de 100 válidas y 10 malformadas, fragmentos de 19 caracteres, duplicados, fuera de orden, salto de secuencia, Q=0, caducidad y colección nueva. |
| Simulador → dashboard → Room | Prueba instrumentada de Compose. Inicia la fuente, verifica la lectura, recrea la actividad, detiene y comprueba la sesión guardada. |
| Simulador → detector → Room | Prueba instrumentada con reloj monotónico controlado, referencia de tres sesiones y escenario de 105 BPM. Pruebas JVM para ruido, pico breve, pérdida, continuidad y calibración insuficiente. |
| Persistencia local | Pruebas instrumentadas para reapertura, estadísticas, borrado en cascada, actualización de contexto y migración v1 a v2. Una transacción retenida y fallos inyectados verifican la lectura en vivo, la cola acotada, la cancelación del drenaje y la separación de sesiones. |
| Desconexión y reconexión | Prueba instrumentada con fuente de transporte controlada y fragmento incompleto antes de reconectar. |
| ESP32 → BLE → Android | Pendiente de hardware. El emulador y el transporte controlado cubren lógica de Android sin alcanzar el enlace físico. |
| FPGA / MAX30100 → ESP32 → Android | Pendiente de hardware. |

La auditoría inicial reprodujo 13 pruebas JVM, 7 instrumentadas y Lint con
0 errores y 11 advertencias. Después de la estabilización pasaron 20 pruebas
JVM y 14 instrumentadas en el emulador de Android 17 (API 37). Lint volvió a
reportar 0 errores y 11 advertencias de versiones y recursos de plantilla.

### Hallazgos de la estabilización

| Clasificación | Hallazgo y resolución |
| --- | --- |
| Error reproducible, gravedad alta | Una transacción retenida en Room impedía publicar una segunda lectura ya disponible. La prueba falló con el código anterior y pasó con la escritura desacoplada. |
| Riesgo técnico confirmado, gravedad alta | Una excepción de Room recorría el mismo manejo que un fallo de transporte. Una prueba con excepción inyectada confirma que ahora BLE sigue entregando lecturas y Room conserva las transacciones previas. |
| Riesgo técnico confirmado, gravedad media | Una terminación GATT previa al CCCD figuraba como desconexión y el timeout podía competir con la confirmación. Se separaron los estados y se serializó la confirmación con el timeout. |
| Limitación pendiente de hardware | Faltan confirmar el modelo físico y las pruebas de radio. HB1 carece de identificador de arranque para reconocer de forma inequívoca un reinicio de la FPGA. |
| Mejora opcional | Un registro de eventos de calidad permitiría atribuir los huecos. Los segmentos y tiempos del esquema actual cubren la gráfica del MVP. |

### Procedimiento con hardware

1. **ESP32 con datos sintéticos.** Flashea BLE_TEST con fragmentación y
   registra 100 tramas a 1 Hz. Cambia al escenario Q=0 y verifica el corte
   de gráfica. Para inyectar duplicados, saltos y líneas malformadas en el
   puente, usa UART_BRIDGE con adaptador UART y tramas de prueba.
2. **Interrupción.** Pausa más de cuatro segundos con el enlace vivo. Verifica
   que los valores actuales desaparecen y regresan con la siguiente trama.
   Apaga el periférico, comprueba el estado desconectado y vuelve a
   seleccionarlo. Envía una trama con secuencia inicial y verifica que arranca
   una sesión independiente. En un intento separado, usa temporalmente un
   UUID de característica ajeno y comprueba que el monitor muestra un fallo
   de conexión antes de confirmar el CCCD. Restablece el UUID correcto y
   verifica que se pueden recibir notificaciones de nuevo.
3. **FPGA con señal sintética.** Inyecta una señal PPG de periodo conocido.
   Captura la salida UART a 115200, 8N1 y compara campos y secuencias con las
   lecturas Android. Repite con señal inválida y confirma que Q=0 queda fuera
   de las estadísticas.
4. **MAX30100 real.** Registra una sesión breve con las tres etapas físicas
   activas. Contrasta tramas UART y lectura visible, provoca pérdida de
   contacto, restablece señal y verifica el cierre y reapertura del historial.
   Usa esta prueba para comprobar el recorrido de datos y la calidad de señal.

[Pruebas de mesa y responsables](../docs/RESPONSIBILITIES.md) · [Reportes de Android](evidence/README.md)
