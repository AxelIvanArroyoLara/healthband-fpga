// Sustitutos de comportamiento para los modelos cifrados del MAX 10 (solo
// descifrables por ModelSim). Únicamente para simular el netlist post-síntesis
// con Icarus. Buffers de E/S: entrada = cable; salida = triestado u open drain.
// ADC y UFM: el diseño no los usa (Quartus los crea por defecto); salidas en 0.
`timescale 1 ps/1 ps

module fiftyfivenm_io_ibuf_encrypted (input i, input ibar, input nsleep, output o);
    parameter bus_hold = "false";
    parameter simulate_z_as = "Z";
    parameter listen_to_nsleep_signal = "false";
    parameter differential_mode = "false";
    parameter lpm_type = "fiftyfivenm_io_ibuf";
    assign o = i;
endmodule

module fiftyfivenm_io_obuf_encrypted (input i, input oe, input [15:0] seriesterminationcontrol,
                                      output o, output obar, input devoe);
    parameter open_drain_output = "false";
    parameter bus_hold = "false";
    parameter lpm_type = "fiftyfivenm_io_obuf";
    assign o = (open_drain_output == "true") ? ((oe && i === 1'b0) ? 1'b0 : 1'bz)
                                             : (oe ? i : 1'bz);
    assign obar = ~o;
endmodule

module fiftyfivenm_unvm_encrypted (input arclk, input arshft, input drclk, input drshft,
    input drdin, input nprogram, input nerase, input nosc_ena, input par_en, input xe_ye,
    input se, input [22:0] ardin, output busy, output osc, output bgpbusy, output se_pass,
    output sp_pass, output [31:0] drdout);
    parameter device_id = "02";
    parameter init_filename_sim = "";
    parameter identifier = "dummy";
    parameter part_name = "dummy";
    parameter is_dual_boot = "false";
    parameter is_eram_skip = "false";
    parameter is_compressed_image = "false";
    parameter init_filename = "dummy";
    parameter min_valid_addr = 1;
    parameter max_valid_addr = 1;
    parameter min_ufm_valid_addr = 1;
    parameter max_ufm_valid_addr = 1;
    parameter addr_range1_end_addr = 1;
    parameter addr_range2_end_addr = 1;
    parameter addr_range1_offset = 1;
    parameter addr_range2_offset = 1;
    parameter addr_range3_offset = 1;
    parameter reserve_block = "false";
    assign {busy, osc, bgpbusy, se_pass, sp_pass} = 5'b0;
    assign drdout = 32'd0;
endmodule

module fiftyfivenm_adcblock_encrypted (input clkin_from_pll_c0, input usr_pwd, input tsen,
    input [4:0] chsel, input soc, output eoc, output [11:0] dout, output clk_dft);
    parameter clkdiv = 1;
    parameter tsclkdiv = 0;
    parameter tsclksel = 0;
    parameter prescalar = 0;
    parameter refsel = 0;
    parameter pwd = 0;
    parameter testbits = 0;
    parameter device_partname_fivechar_prefix = "10M08";
    parameter is_this_first_or_second_adc = 1;
    parameter analog_input_pin_mask = 0;
    parameter reserve_block = "false";
    parameter enable_usr_sim = 0;
    parameter reference_voltage_sim = 65536;
    parameter simfilename_ch0 = "";  parameter simfilename_ch1 = "";  parameter simfilename_ch2 = "";
    parameter simfilename_ch3 = "";  parameter simfilename_ch4 = "";  parameter simfilename_ch5 = "";
    parameter simfilename_ch6 = "";  parameter simfilename_ch7 = "";  parameter simfilename_ch8 = "";
    parameter simfilename_ch9 = "";  parameter simfilename_ch10 = ""; parameter simfilename_ch11 = "";
    parameter simfilename_ch12 = ""; parameter simfilename_ch13 = ""; parameter simfilename_ch14 = "";
    parameter simfilename_ch15 = ""; parameter simfilename_ch16 = "";
    assign eoc = 1'b0;
    assign dout = 12'd0;
    assign clk_dft = 1'b0;
endmodule
