# Contrato provisional HB1 en Android

Este documento registra el comportamiento del receptor Android para coordinar
las pruebas con el puente. [Propuesta del equipo](../shared/PROTOCOL.md)

```text
HB1,SEQ=000012,BPM=075,IBI=0800,Q=1
```

| Campo | Formato que acepta Android |
| --- | --- |
| `SEQ` | Seis dígitos, de 000000 a 999999. |
| `BPM` | Tres dígitos. Para Q=1 se acepta de 30 a 240. |
| `IBI` | Cuatro dígitos en milisegundos. Para Q=1 se acepta de 250 a 2500. |
| `Q` | Un dígito, 1 para lectura válida y 0 para lectura inválida. |

- Envía texto ASCII con LF al final de cada trama. Se admite CRLF. Una
  notificación GATT puede contener una parte de una trama o varias completas.
- Se acumulan hasta 128 caracteres de una línea. Una línea mayor produce un
  error y se descarta hasta el siguiente LF. La siguiente línea se procesa
  normalmente.
- La primera trama aceptada fija la secuencia. El avance circular se calcula
  módulo 1 000 000. Un avance cero es un duplicado y un avance de 500 000 o
  mayor se rechaza como fuera de orden. El salto 999999 → 000000 se acepta.
  Un salto menor hacia delante se conserva y se abre un segmento de gráfica
  tras el hueco. El orden inicial se restablece al abrir una nueva conexión.
- Una trama rechazada incrementa el contador de errores. Una trama Q=0 con
  formato y secuencia correctos incrementa el contador de aceptadas, oculta BPM
  e IBI y corta la gráfica. El historial almacena muestras de Q=1.
- Cuatro segundos sin tramas aceptadas retiran BPM e IBI del monitor. El
  tiempo se mide con reloj monotónico. Las fechas de historial se guardan como
  milisegundos Unix.
- Para GATT se requieren los UUID que confirme el equipo del puente. En el
  enlace FPGA → ESP32 se espera UART a 115200, 8N1, con una trama por segundo.


## Reinicio de secuencia de la FPGA

La regla circular sigue siendo provisional. Dentro de una misma colección,
el receptor no interpreta un salto de secuencia como reinicio. Por ejemplo,
`001000 → 000001` se rechaza por orden y `999990 → 000010` se acepta como
avance circular. Ambos casos podrían corresponder a un reinicio real.

Para probar un reinicio conocido, detén la adquisición y vuelve a seleccionar
el periférico para iniciar un parser nuevo. Queda por acordar con el equipo
si el puente debe reiniciar el enlace al reiniciar la FPGA o si una revisión
de HB1 debe anunciar un nuevo arranque explícitamente. La caducidad visual
también puede ocurrir por pérdida de datos y no reinicia el contador.
