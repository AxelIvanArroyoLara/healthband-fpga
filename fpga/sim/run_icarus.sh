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
     rtl/ppg_synth.v rtl/i2c_master.v rtl/max30100_ctrl.v rtl/healthband_top.v"
BUILD=build/sim
OUT=evidence/rtl
mkdir -p "$BUILD" "$OUT"
: > "$OUT/sim_log.txt"

# Los bancos Verilog-2001 reportan fallos por texto, incluso si vvp retorna 0.
run_simulation() {
    vvp -n "$@" | tee -a "$OUT/sim_log.txt" | awk '
        { print }
        /^(FAIL|ERROR)/ { failed = 1 }
        END { exit failed }
    '
}

echo "== Estímulos y modelo de referencia"
python3 -I model/gen_stimulus.py
python3 -I model/run_reference.py

echo "== tb_ppg_processor (procesamiento con señales sintéticas)"
iverilog -g2005 -Wall -o "$BUILD/tb_ppg_processor.vvp" tb/tb_ppg_processor.v $RTL
for stim in stim/*.hex; do
    name=$(basename "$stim" .hex)
    run_simulation "$BUILD/tb_ppg_processor.vvp" +STIM="$stim" \
        +BEATS_OUT="$OUT/${name}_beats.csv" +HZ_OUT="$OUT/${name}_1hz.csv"
done
python3 -I model/compare_rtl.py

echo "== tb_hb1_uart (100 tramas a 115200 8N1)"
iverilog -g2005 -Wall -o "$BUILD/tb_hb1_uart.vvp" tb/tb_hb1_uart.v $RTL
run_simulation "$BUILD/tb_hb1_uart.vvp" +FRAMES_OUT="$OUT/hb1_frames.txt"
iverilog -g2005 -Wall -Ptb_hb1_uart.WRAP=1 -Ptb_hb1_uart.N_FRAMES=3 \
    -o "$BUILD/tb_hb1_wrap.vvp" tb/tb_hb1_uart.v $RTL
run_simulation "$BUILD/tb_hb1_wrap.vvp" +FRAMES_OUT="$BUILD/hb1_wrap.txt"

echo "== tb_healthband_top (sistema completo con generador sintético)"
iverilog -g2005 -Wall -o "$BUILD/tb_healthband_top.vvp" tb/tb_healthband_top.v $RTL
run_simulation "$BUILD/tb_healthband_top.vvp" +FRAMES_OUT="$OUT/top_frames.txt"

echo "== tb_max30100_top (sistema completo con el MAX30100 por I2C, modelo del sensor)"
iverilog -g2005 -Wall -o "$BUILD/tb_max30100_top.vvp" tb/tb_max30100_top.v tb/max30100_model.v $RTL
run_simulation "$BUILD/tb_max30100_top.vvp" +FRAMES_OUT="$OUT/max30100_frames.txt"

echo "== tb_max30100_top con el modelo del MAX30102 (mismos módulos, otro mapa de registros)"
iverilog -g2005 -Wall -P tb_max30100_top.IS102=1 -o "$BUILD/tb_max30102_top.vvp" tb/tb_max30100_top.v tb/max30100_model.v $RTL
run_simulation "$BUILD/tb_max30102_top.vvp" +FRAMES_OUT="$OUT/max30102_frames.txt"

echo "Todas las simulaciones pasaron. Evidencias en fpga/$OUT/"
