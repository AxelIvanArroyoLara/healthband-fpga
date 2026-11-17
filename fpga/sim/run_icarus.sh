#!/usr/bin/env bash
# Corre todas las simulaciones con Icarus Verilog y guarda las evidencias en
# fpga/evidence/rtl/. Requiere iverilog/vvp y Python 3 en el PATH.
#
#   bash fpga/sim/run_icarus.sh
#
# Para ver formas de onda en GTKWave, agregar +VCD al vvp de tb_ppg_processor
# o tb_hb1_uart (los .vcd no se suben al repositorio).
set -euo pipefail

cd "$(dirname "$0")/.."   # fpga/

RTL="rtl/bin_to_bcd.v rtl/ppg_filter.v rtl/pulse_detector.v rtl/bpm_calc.v
     rtl/ppg_processor.v rtl/uart_tx.v rtl/hb1_framer.v rtl/seg7_bpm.v
     rtl/ppg_synth.v rtl/healthband_top.v"
BUILD=build/sim
OUT=evidence/rtl
mkdir -p "$BUILD" "$OUT"
: > "$OUT/sim_log.txt"

echo "== Estímulos y modelo de referencia"
python -I model/gen_stimulus.py
python -I model/run_reference.py

echo "== tb_ppg_processor (procesamiento con señales sintéticas)"
iverilog -g2005 -Wall -o "$BUILD/tb_ppg_processor.vvp" tb/tb_ppg_processor.v $RTL
for stim in stim/*.hex; do
    name=$(basename "$stim" .hex)
    vvp -n "$BUILD/tb_ppg_processor.vvp" +STIM="$stim" \
        +BEATS_OUT="$OUT/${name}_beats.csv" +HZ_OUT="$OUT/${name}_1hz.csv" | tee -a "$OUT/sim_log.txt"
done
python -I model/compare_rtl.py

echo "== tb_hb1_uart (100 tramas a 115200 8N1)"
iverilog -g2005 -Wall -o "$BUILD/tb_hb1_uart.vvp" tb/tb_hb1_uart.v $RTL
vvp -n "$BUILD/tb_hb1_uart.vvp" +FRAMES_OUT="$OUT/hb1_frames.txt" | tee -a "$OUT/sim_log.txt"

echo "== tb_healthband_top (sistema completo con generador sintético)"
iverilog -g2005 -Wall -o "$BUILD/tb_healthband_top.vvp" tb/tb_healthband_top.v $RTL
vvp -n "$BUILD/tb_healthband_top.vvp" +FRAMES_OUT="$OUT/top_frames.txt" | tee -a "$OUT/sim_log.txt"

if grep -qE "FAIL|ERROR" "$OUT/sim_log.txt"; then
    echo "Hay fallas: revisar $OUT/sim_log.txt"
    exit 1
fi
echo "Todas las simulaciones pasaron. Evidencias en fpga/$OUT/"
