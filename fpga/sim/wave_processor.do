# Abre tb_ppg_processor en la interfaz gráfica de ModelSim / Questa con las
# señales principales, para tomar capturas de formas de onda (evidencia).
# Ejecutar desde fpga/ después de run_questa.do (usa la biblioteca work):
#
#   vsim -do sim/wave_processor.do
#
# Cambiar el estímulo editando STIM abajo (por ejemplo stim/nocontact.hex).

set STIM stim/bpm075.hex

file mkdir build
vsim -onfinish stop work.tb_ppg_processor +STIM=$STIM \
    +BEATS_OUT=build/wave_beats.csv +HZ_OUT=build/wave_1hz.csv

add wave -divider "Entrada"
add wave -radix unsigned /tb_ppg_processor/dut/ir_sample
add wave /tb_ppg_processor/dut/sample_valid
add wave /tb_ppg_processor/dut/fifo_overflow
add wave -divider "Filtro y detector"
add wave -format analog-step -height 100 -min -400 -max 400 -radix decimal /tb_ppg_processor/dut/filt
add wave -format analog-step -height 60 -min 0 -max 400 -radix decimal /tb_ppg_processor/dut/u_det/env
add wave /tb_ppg_processor/dut/beat_valid
add wave -radix unsigned /tb_ppg_processor/dut/u_det/interval
add wave -divider "Salidas"
add wave -radix unsigned /tb_ppg_processor/dut/bpm
add wave -radix unsigned /tb_ppg_processor/dut/ibi_ms
add wave /tb_ppg_processor/dut/data_valid
add wave -radix binary /tb_ppg_processor/dut/signal_quality

run -all
wave zoom full
