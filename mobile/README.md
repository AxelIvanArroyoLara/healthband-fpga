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

El APK de depuración queda en `app/build/outputs/apk/debug/app-debug.apk`.
Ejecuta la configuración `app` de Android Studio o instala el APK con
`adb install -r app/build/outputs/apk/debug/app-debug.apk`.

## Monitor e historial

1. En **Monitor**, pulsa **Iniciar simulación**. La fuente de prueba envía BPM
   e IBI, tramas fragmentadas, duplicados, tramas incorrectas y lecturas Q=0.
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
la referencia, y para registrar el contexto.

El análisis describe desviaciones estadísticas del reposo. Los contextos son
anotaciones del usuario y este prototipo carece de validación clínica.
[MAD en el manual de estadística de NIST](https://www.itl.nist.gov/div898/handbook/eda/section3/eda356.htm)

## Configurar el ESP32 real

1. Confirma el modelo con BLE, el UUID del servicio y el UUID de la
   característica con el equipo del puente. La característica debe admitir
   notificaciones o indicaciones con descriptor CCCD.
2. Enciende Bluetooth, abre **Configurar Bluetooth LE** e introduce ambos UUID
   completos. La app muestra **BLE sin configurar** mientras falte un UUID.
3. Pulsa **Buscar dispositivos**, concede los permisos solicitados y elige el
   ESP32. El escaneo dura hasta diez segundos y la suscripción hasta quince.
4. Tras una desconexión, vuelve a seleccionar el periférico para iniciar una
   sesión y un parser nuevos. La app mantiene las direcciones únicamente en
   memoria. Los permisos de ubicación solo se solicitan en Android 11 y
   anteriores para el escaneo de primer plano.

La política de reinicio del contador dentro de una conexión y los rangos
definitivos dependen del acuerdo con firmware y FPGA.
[Contrato HB1 de la app](PROTOCOL.md)
[Permisos Bluetooth de Android](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
[Conexión GATT en Android](https://developer.android.com/reference/android/bluetooth/BluetoothDevice)

## Validación

| Recorrido | Verificación |
| --- | --- |
| Fragmentos HB1 → parser → estado | Pruebas JVM con lotes de 100 válidas y 10 malformadas, fragmentos de 19 caracteres, duplicados, fuera de orden, salto de secuencia, Q=0, caducidad y colección nueva. |
| Simulador → dashboard → Room | Prueba instrumentada de Compose. Inicia la fuente, verifica la lectura, recrea la actividad, detiene y comprueba la sesión guardada. |
| Simulador → detector → Room | Prueba instrumentada con reloj monotónico controlado, referencia de tres sesiones y escenario de 105 BPM. Pruebas JVM para ruido, pico breve, pérdida, continuidad y calibración insuficiente. |
| Persistencia local | Pruebas instrumentadas para reapertura, estadísticas, borrado en cascada, actualización de contexto y migración de Room de v1 a v2. |
| Desconexión y reconexión | Prueba instrumentada con fuente de transporte controlada y fragmento incompleto antes de reconectar. |
| ESP32 → BLE → Android | Pendiente de hardware. El emulador y el transporte controlado cubren lógica de Android sin alcanzar el enlace físico. |
| FPGA / MAX30100 → ESP32 → Android | Pendiente de hardware. |

### Procedimiento con hardware

1. **ESP32 con datos sintéticos.** Configura el puente con los UUID acordados.
   Emite 100 tramas válidas a 1 Hz, intercala 10 líneas malformadas y reparte
   algunas tramas en fragmentos de distintos tamaños. Compara el contador
   de aceptadas y errores con la secuencia enviada. Agrega por separado un
   duplicado, un salto y una trama Q=0 para verificar sus efectos.
2. **Interrupción.** Pausa más de cuatro segundos con el enlace vivo. Verifica
   que los valores actuales desaparecen y regresan con la siguiente trama.
   Apaga el periférico, comprueba el estado desconectado y vuelve a
   seleccionarlo. Envía una trama con secuencia inicial y verifica que arranca
   una sesión independiente.
3. **FPGA con señal sintética.** Inyecta una señal PPG de periodo conocido.
   Captura la salida UART a 115200, 8N1 y compara campos y secuencias con las
   lecturas Android. Repite con señal inválida y confirma que Q=0 queda fuera
   de las estadísticas.
4. **MAX30100 real.** Registra una sesión breve con las tres etapas físicas
   activas. Contrasta tramas UART y lectura visible, provoca pérdida de
   contacto, restablece señal y verifica el cierre y reapertura del historial.
   Usa esta prueba para comprobar el recorrido de datos y la calidad de señal.
