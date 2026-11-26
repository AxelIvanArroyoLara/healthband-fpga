// Envoltura solo para la simulación post-síntesis: mismo diseño con relojes
// escalados (345 600 Hz, I2C 28 800 Hz) para que la simulación de compuertas sea corta.
module gate_top (
    input  wire       MAX10_CLK1_50,
    input  wire [1:0] KEY,
    input  wire [9:0] SW,
    output wire [9:0] LEDR,
    output wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout  wire [3:0] GPIO
);
    healthband_top #(.CLK_HZ(345_600), .BAUD(115_200), .I2C_HZ(28_800)) u (
        .MAX10_CLK1_50(MAX10_CLK1_50), .KEY(KEY), .SW(SW), .LEDR(LEDR),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
        .GPIO(GPIO));
endmodule
