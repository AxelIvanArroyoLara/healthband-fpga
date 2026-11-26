# Corre todas las simulaciones en ModelSim / Questa (incluido en Quartus Prime Lite).
# Ejecutar desde la carpeta fpga/:
#
#   vsim -c -do sim/run_questa.do
#
# Antes, generar estímulos y referencia con Python:
#   python -I model/gen_stimulus.py
#   python -I model/run_reference.py
# Después, comparar:
#   python -I model/compare_rtl.py

file mkdir evidence/rtl
if {[file exists work]} { vdel -lib work -all }
vlib work
vlog -work work rtl/bin_to_bcd.v rtl/ppg_filter.v rtl/pulse_detector.v rtl/bpm_calc.v \
     rtl/ppg_processor.v rtl/uart_tx.v rtl/hb1_framer.v rtl/seg7_bpm.v \
     rtl/ppg_synth.v rtl/i2c_master.v rtl/max30100_ctrl.v rtl/healthband_top.v \
     tb/tb_ppg_processor.v tb/tb_hb1_uart.v tb/tb_healthband_top.v \
     tb/max30100_model.v tb/tb_max30100_top.v

foreach stim [lsort [glob stim/*.hex]] {
    set name [file rootname [file tail $stim]]
    vsim -c -onfinish stop work.tb_ppg_processor +STIM=$stim \
        +BEATS_OUT=evidence/rtl/${name}_beats.csv +HZ_OUT=evidence/rtl/${name}_1hz.csv
    run -all
    quit -sim
}

vsim -c -onfinish stop work.tb_hb1_uart +FRAMES_OUT=evidence/rtl/hb1_frames.txt
run -all
quit -sim

vsim -c -onfinish stop work.tb_healthband_top +FRAMES_OUT=evidence/rtl/top_frames.txt
run -all
quit -sim

vsim -c -onfinish stop work.tb_max30100_top +FRAMES_OUT=evidence/rtl/max30100_frames.txt
run -all
quit -sim

quit -f
