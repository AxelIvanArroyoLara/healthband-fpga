# Fixture del contrato

`rtl-hb1-100.txt` contiene 100 líneas HB1 sintéticas, del SEQ 000000 al
000099. Incluye Q=0 y conserva LF. El script `bash shared/test_hb1.sh`
regenera la captura desde el UART del testbench con `CONTRACT=1`.
Compara el resultado con este fixture y consulta las
[notificaciones derivadas](../evidence/README.md).
