// hb1_framer
// Cada 1/FRAME_HZ segundos toma una instantánea de la medición y envía por
// UART la trama de texto del protocolo HB1 (36 bytes ASCII):
//
//   HB1,SEQ=000012,BPM=075,IBI=0800,Q=1\n
//
//   SEQ  contador BCD de 6 dígitos; empieza en 000000 después de reset,
//        aumenta 1 por trama (también con Q=0) y pasa de 999999 a 000000.
//   BPM  3 dígitos; 000 cuando Q=0.
//   IBI  4 dígitos en ms; 0000 cuando Q=0. Se limita a 9999.
//   Q    1 = medición válida (data_valid), 0 = inválida.
//
// Se envía una trama por segundo aunque no haya señal, para que el ESP32 y
// la app distingan "sin medición válida" (Q=0) de "enlace caído".

module hb1_framer #(
    parameter CLK_HZ   = 50_000_000,
    parameter FRAME_HZ = 1
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire  [7:0] bpm,
    input  wire [15:0] ibi_ms,
    input  wire        data_valid,
    output reg   [7:0] tx_data,
    output reg         tx_start,
    input  wire        tx_busy
);

    localparam TICK_CYCLES = CLK_HZ / FRAME_HZ;
    localparam FRAME_LEN   = 36;

    reg [31:0] tick_cnt;
    reg        sending;
    reg  [5:0] idx;
    reg [23:0] seq;     // 6 dígitos BCD, seq[23:20] es el más significativo
    reg [11:0] bpm_d;   // 3 dígitos BCD
    reg [15:0] ibi_d;   // 4 dígitos BCD
    reg        q;

    wire        tick    = (tick_cnt == TICK_CYCLES - 1);
    wire [15:0] bpm_val = data_valid ? {8'd0, bpm} : 16'd0;
    wire [15:0] ibi_val = !data_valid         ? 16'd0 :
                          (ibi_ms > 16'd9999) ? 16'd9999 : ibi_ms;
    wire [19:0] bpm_bcd;
    wire [19:0] ibi_bcd;

    bin_to_bcd u_bpm_bcd (.bin(bpm_val), .bcd(bpm_bcd));
    bin_to_bcd u_ibi_bcd (.bin(ibi_val), .bcd(ibi_bcd));

    // Incremento BCD de 6 dígitos con acarreo; 999999 vuelve a 000000.
    function [23:0] bcd_inc;
        input [23:0] value;
        reg          carry;
        integer      k;
        begin
            carry = 1'b1;
            for (k = 0; k < 6; k = k + 1) begin
                if (carry && value[4*k +: 4] == 4'd9) begin
                    bcd_inc[4*k +: 4] = 4'd0;
                end else if (carry) begin
                    bcd_inc[4*k +: 4] = value[4*k +: 4] + 4'd1;
                    carry = 1'b0;
                end else begin
                    bcd_inc[4*k +: 4] = value[4*k +: 4];
                end
            end
        end
    endfunction

    function [7:0] digit;
        input [3:0] d;
        digit = 8'h30 + {4'd0, d};
    endfunction

    reg [7:0] ch;
    always @(*) begin
        case (idx)
            6'd0:  ch = "H";
            6'd1:  ch = "B";
            6'd2:  ch = "1";
            6'd3:  ch = ",";
            6'd4:  ch = "S";
            6'd5:  ch = "E";
            6'd6:  ch = "Q";
            6'd7:  ch = "=";
            6'd8:  ch = digit(seq[23:20]);
            6'd9:  ch = digit(seq[19:16]);
            6'd10: ch = digit(seq[15:12]);
            6'd11: ch = digit(seq[11:8]);
            6'd12: ch = digit(seq[7:4]);
            6'd13: ch = digit(seq[3:0]);
            6'd14: ch = ",";
            6'd15: ch = "B";
            6'd16: ch = "P";
            6'd17: ch = "M";
            6'd18: ch = "=";
            6'd19: ch = digit(bpm_d[11:8]);
            6'd20: ch = digit(bpm_d[7:4]);
            6'd21: ch = digit(bpm_d[3:0]);
            6'd22: ch = ",";
            6'd23: ch = "I";
            6'd24: ch = "B";
            6'd25: ch = "I";
            6'd26: ch = "=";
            6'd27: ch = digit(ibi_d[15:12]);
            6'd28: ch = digit(ibi_d[11:8]);
            6'd29: ch = digit(ibi_d[7:4]);
            6'd30: ch = digit(ibi_d[3:0]);
            6'd31: ch = ",";
            6'd32: ch = "Q";
            6'd33: ch = "=";
            6'd34: ch = q ? "1" : "0";
            default: ch = 8'h0A;  // '\n'
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tick_cnt <= 0;
            sending  <= 1'b0;
            idx      <= 6'd0;
            seq      <= 24'd0;
            bpm_d    <= 12'd0;
            ibi_d    <= 16'd0;
            q        <= 1'b0;
            tx_data  <= 8'd0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            tick_cnt <= tick ? 0 : tick_cnt + 1;

            if (!sending) begin
                if (tick) begin
                    // Instantánea de la medición para toda la trama.
                    q       <= data_valid;
                    bpm_d   <= bpm_bcd[11:0];
                    ibi_d   <= ibi_bcd[15:0];
                    idx     <= 6'd0;
                    sending <= 1'b1;
                end
            end else if (!tx_busy && !tx_start) begin
                tx_data  <= ch;
                tx_start <= 1'b1;
                if (idx == FRAME_LEN - 1) begin
                    sending <= 1'b0;
                    seq     <= bcd_inc(seq);
                end else begin
                    idx <= idx + 6'd1;
                end
            end
        end
    end

endmodule
