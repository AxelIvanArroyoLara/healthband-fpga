// ppg_synth
// Generador sintético de muestras PPG sintetizable, para probar la cadena
// FPGA -> UART -> ESP32 -> app sin el MAX30100 (integración, etapa 2).
// Imita la salida del sensor: nivel DC alto que baja en cada sístole.
//
//   rate_sel   00 = 60, 01 = 75, 10 = 100, 11 = 120 BPM
//   noise_en   suma ruido pseudoaleatorio de +-32 cuentas
//   no_contact simula el dedo retirado (IR muy bajo)  -> Q=0
//   saturate   simula saturación del ADC (IR = 0xFFFF) -> Q=0
//
// La forma de onda es una tabla de 64 puntos (sístole + onda dicrótica)
// recorrida con un acumulador de fase de 24 bits: inc = round(2^24 / N),
// donde N = 6000 / BPM es el número de muestras por latido a 100 Hz.

module ppg_synth #(
    parameter CLK_HZ    = 50_000_000,
    parameter SAMPLE_HZ = 100
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire  [1:0] rate_sel,
    input  wire        noise_en,
    input  wire        no_contact,
    input  wire        saturate,
    output reg  [15:0] ir_sample,
    output reg  [15:0] red_sample,
    output reg         sample_valid,
    output wire        fifo_overflow
);

    localparam DIV = CLK_HZ / SAMPLE_HZ;

    reg [31:0] div_cnt;
    reg [23:0] phase;
    reg [15:0] lfsr;
    reg [23:0] inc;
    reg  [7:0] shape;

    always @(*) begin
        case (rate_sel)
            2'd0:    inc = 24'd167772;  // N = 100 ->  60 BPM
            2'd1:    inc = 24'd209715;  // N =  80 ->  75 BPM
            2'd2:    inc = 24'd279620;  // N =  60 -> 100 BPM
            default: inc = 24'd335544;  // N =  50 -> 120 BPM
        endcase
    end

    always @(*) begin
        case (phase[23:18])
            6'd0 : shape = 8'd0  ;  6'd1 : shape = 8'd1  ;  6'd2 : shape = 8'd3  ;  6'd3 : shape = 8'd7  ;
            6'd4 : shape = 8'd13 ;  6'd5 : shape = 8'd25 ;  6'd6 : shape = 8'd44 ;  6'd7 : shape = 8'd71 ;
            6'd8 : shape = 8'd106;  6'd9 : shape = 8'd147;  6'd10: shape = 8'd189;  6'd11: shape = 8'd226;
            6'd12: shape = 8'd249;  6'd13: shape = 8'd255;  6'd14: shape = 8'd242;  6'd15: shape = 8'd212;
            6'd16: shape = 8'd173;  6'd17: shape = 8'd130;  6'd18: shape = 8'd91 ;  6'd19: shape = 8'd59 ;
            6'd20: shape = 8'd36 ;  6'd21: shape = 8'd20 ;  6'd22: shape = 8'd12 ;  6'd23: shape = 8'd9  ;
            6'd24: shape = 8'd12 ;  6'd25: shape = 8'd18 ;  6'd26: shape = 8'd30 ;  6'd27: shape = 8'd45 ;
            6'd28: shape = 8'd62 ;  6'd29: shape = 8'd77 ;  6'd30: shape = 8'd87 ;  6'd31: shape = 8'd89 ;
            6'd32: shape = 8'd82 ;  6'd33: shape = 8'd69 ;  6'd34: shape = 8'd52 ;  6'd35: shape = 8'd36 ;
            6'd36: shape = 8'd22 ;  6'd37: shape = 8'd13 ;  6'd38: shape = 8'd6  ;  6'd39: shape = 8'd3  ;
            6'd40: shape = 8'd1  ;
            default: shape = 8'd0;
        endcase
    end

    // Ruido de -32 a +31 sumado como (noise + 32) - 32 para operar sin signo.
    wire [15:0] noise = noise_en ? {10'd0, lfsr[5:0]} : 16'd32;

    assign fifo_overflow = 1'b0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            div_cnt      <= 0;
            phase        <= 24'd0;
            lfsr         <= 16'hACE1;
            ir_sample    <= 16'd0;
            red_sample   <= 16'd0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            if (div_cnt == DIV - 1) begin
                div_cnt      <= 0;
                phase        <= phase + inc;
                lfsr         <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                sample_valid <= 1'b1;
                if (saturate) begin
                    ir_sample  <= 16'hFFFF;
                    red_sample <= 16'hFFFF;
                end else if (no_contact) begin
                    ir_sample  <= 16'd300 + {10'd0, lfsr[5:0]};
                    red_sample <= 16'd250 + {10'd0, lfsr[5:0]};
                end else begin
                    ir_sample  <= 16'd40000 - {7'd0, shape, 1'b0} + noise - 16'd32;
                    red_sample <= 16'd30000 - {8'd0, shape} + noise - 16'd32;
                end
            end else begin
                div_cnt <= div_cnt + 1;
            end
        end
    end

endmodule
