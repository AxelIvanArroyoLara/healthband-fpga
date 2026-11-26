# Reloj de 50 MHz de la DE10-Lite.
create_clock -name clk50 -period 20.000 [get_ports {MAX10_CLK1_50}]
derive_clock_uncertainty

# Entradas de usuario asíncronas (se sincronizan en el diseño) y salidas lentas.
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] GPIO[*]}]
# SDA del MAX30100 (I2C a 100 kHz, se sincroniza en el diseño).
set_false_path -from [get_ports {GPIO[*]}]
