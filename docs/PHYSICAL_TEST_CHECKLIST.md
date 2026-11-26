# Checklist de integración física

Completar después de cada prueba. Registrar versión/commit, modelo de placa
y condiciones en la evidencia. Consulta [responsables y criterios de cierre](RESPONSIBILITIES.md). Repetir y fechar cuando cambien el cableado
o el binario. [Guía de ejecución](PHYSICAL_INTEGRATION_GUIDE.md)

| ID | Responsable | Precondiciones | Procedimiento | Resultado esperado | Resultado observado | Evidencia | Estado |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | Dani | APK debug y teléfono | Instalar, simular, detener y abrir historial | BPM/IBI, gráfica y lecturas confirmadas | | | Pendiente |
| A2 | Dani | Simulador funcional | Activar errores explícitos | Rechazos, Q=0 y corte | | | Pendiente |
| A3 | Dani | Tres sesiones de reposo con ≥20 válidas | Demostrar elevación, historial y contexto | Referencia, episodio y anotación guardados | | | Pendiente |
| A4 | Dani | Sesión de prueba guardada | Consultar, etiquetar episodio y eliminar una sesión de prueba | Contexto persiste y el borrado solo afecta la sesión elegida | | | Pendiente |
| B | Sebas | ESP32 identificado y perfil BLE_TEST | Flashear y comprobar anuncio/CCCD con escáner | Servicio Notify y fragmentos ≤7 bytes | | | Pendiente |
| C1 | Sebas | B y permisos BLE | Conectar y contar 100 tramas | SEQ ordenada y lecturas guardadas | | | Pendiente |
| C2 | Sebas | C1 y perfil Q=0 | Verificar Q=0, apagar y volver a elegir el puente | Corte, lectura vacía y parser fresco | | | Pendiente |
| D1 | Dani | Quartus MAX 10 y USB-Blaster | Compilar, revisar fit/STA y programar | SOF actual, temporización comprobada | | | Pendiente |
| D2 | Dani | D1, SW9 activo | 60/75/100/120, contacto/saturación y captura UART | Display coherente, 36 bytes, Q=0 y recuperación | | | Pendiente |
| E | Sebas y Dani | D2, UART_BRIDGE, niveles y GND verificados | Capturar UART de FPGA y comparar con Notify | Bytes y LF idénticos, orden preservado | | | Pendiente |
| F | Sebas y Dani | E y Android marcado sintético | Comparar display, UART e historial. Reset y nueva conexión | BPM/IBI coherentes, corte y sesión nueva | | | Pendiente |
| G | Sebas y Dani | Breakout, alimentación y pull-ups verificados | PART_ID, IR, contacto, pérdida y recuperación | `11`, muestras, Q y BPM coherentes | | | Pendiente |
| H | Sebas y Dani | A–G y modo real | Registrar estabilidad ≥10 min | Pérdidas contabilizadas y recuperación documentada | | | Pendiente |
