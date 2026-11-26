# Entregables Quartus

La síntesis final, la temporización y el SOF están pendientes. Dani los
genera con Quartus Prime Lite y soporte para MAX 10. El proyecto
[healthband.qpf](../quartus/healthband.qpf) selecciona la revisión
`healthband` para el 10M50DAF484C7G de la DE10-Lite.

1. Abre el proyecto y ejecuta **Processing → Start Compilation**. La
   alternativa desde `fpga/quartus/` es `quartus_sh --flow compile healthband`.
2. Revisa recursos y avisos en los informes de síntesis y ajuste
   (`healthband.map.rpt`, `healthband.fit.rpt`). Revisa slack, reloj de
   50 MHz y rutas sin restricciones en `healthband.sta.rpt`.
   Genera Power Analyzer cuando dispongas de actividad representativa.
3. Tras revisar el resultado, copia desde `fpga/quartus/output_files/`
   el SOF recién generado a `fpga/artifacts/healthband.sof`. Registra
   el commit de RTL, la versión de Quartus y la suma SHA-256 con el
   comando `shasum -a 256 healthband.sof` desde `fpga/artifacts/`.
4. Conecta el USB-Blaster. En **Tools → Programmer**, selecciona el
   hardware, carga el SOF, marca **Program/Configure** y pulsa **Start**.
   La prueba inicial usa SW9 activo para PPG sintética. Consulta las
   [asignaciones de controles](../README.md#prueba-en-la-placa).
5. Guarda los reportes con la evidencia de banco y actualiza el
   [manifiesto](../../docs/ARTIFACTS_MANIFEST.md) y el
   [checklist](../../docs/PHYSICAL_TEST_CHECKLIST.md).
