// seg7_bpm
// Muestra el BPM en tres displays de siete segmentos de la DE10-Lite
// (activos en bajo, bit 7 = punto decimal). Sin medición válida muestra "---".
// Las centenas se apagan cuando valen 0.

module seg7_bpm (
    input  wire [7:0] bpm,
    input  wire       valid,
    output wire [7:0] hex0,   // unidades
    output wire [7:0] hex1,   // decenas
    output wire [7:0] hex2    // centenas
);

    localparam [7:0] SEG_DASH  = 8'hBF;
    localparam [7:0] SEG_BLANK = 8'hFF;

    wire [19:0] bcd;

    bin_to_bcd u_bcd (.bin({8'd0, bpm}), .bcd(bcd));

    function [7:0] seg;
        input [3:0] d;
        case (d)
            4'd0: seg = 8'hC0;
            4'd1: seg = 8'hF9;
            4'd2: seg = 8'hA4;
            4'd3: seg = 8'hB0;
            4'd4: seg = 8'h99;
            4'd5: seg = 8'h92;
            4'd6: seg = 8'h82;
            4'd7: seg = 8'hF8;
            4'd8: seg = 8'h80;
            4'd9: seg = 8'h90;
            default: seg = SEG_BLANK;
        endcase
    endfunction

    assign hex0 = valid ? seg(bcd[3:0]) : SEG_DASH;
    assign hex1 = valid ? seg(bcd[7:4]) : SEG_DASH;
    assign hex2 = !valid ? SEG_DASH :
                  (bcd[11:8] == 4'd0) ? SEG_BLANK : seg(bcd[11:8]);

endmodule
