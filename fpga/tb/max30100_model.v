// max30100_model
// Modelo de comportamiento (solo simulación) del MAX30100 como esclavo I2C.
//
// - Dirección 0x57. Registros 0x00..0xFF, PART_ID (0xFF) = 0x11.
// - El puntero de registro se autoincrementa, excepto en FIFO_DATA (0x05).
// - FIFO de 16 muestras de 4 bytes (IR alto, IR bajo, RED alto, RED bajo);
//   WR_PTR (0x02), OVF_COUNTER (0x03) y RD_PTR (0x04) como en la hoja de datos.
// - Escribir 0x40 en MODE (0x06) reinicia los registros.
// - Con MODE = 0x02 o 0x03 genera una muestra cada SAMPLE_CLKS ciclos de clk
//   (su propio "oscilador", distinto del de la FPGA) con una forma de onda PPG:
//   nivel DC alto que baja en cada sístole, más una onda dicrótica y ruido.
//
// Controles desde el testbench: bpm (real), finger (dedo puesto),
// connected (0 = no responde ACK, como si estuviera desconectado).

`timescale 1ns / 1ps

module max30100_model #(
    parameter SAMPLE_CLKS = 11_578
) (
    input  wire clk,
    input  wire scl,
    inout  wire sda
);

    real    bpm       = 72.0;
    reg     finger    = 1'b1;
    reg     connected = 1'b1;

    reg sda_low = 1'b0;
    assign sda = sda_low ? 1'b0 : 1'bz;

    // Registros visibles para el testbench.
    reg [7:0] mode_reg = 8'h00;
    reg [7:0] spo2_reg = 8'h00;
    reg [7:0] led_reg  = 8'h00;
    reg [7:0] int_en   = 8'h00;
    reg [3:0] wr_ptr   = 4'd0;
    reg [3:0] rd_ptr   = 4'd0;
    reg [4:0] ovf_cnt  = 5'd0;
    reg [4:0] count    = 5'd0;   // muestras en el FIFO (0..16)
    reg [1:0] byte_idx = 2'd0;
    reg [15:0] fifo_ir  [0:15];
    reg [15:0] fifo_red [0:15];
    integer   n_samples = 0;
    integer   n_resets  = 0;

    // ---------------------------------------------------------------
    // Generación de muestras
    real phase = 0.0;
    real g1, g2, ac;
    integer clk_cnt = 0;
    integer ir_val, red_val;

    always @(posedge clk) begin
        if (mode_reg[2:0] == 3'd2 || mode_reg[2:0] == 3'd3) begin
            if (clk_cnt == SAMPLE_CLKS - 1) begin
                clk_cnt = 0;
                phase = phase + bpm / 6000.0;
                if (phase >= 1.0) phase = phase - 1.0;
                g1 = $exp(-((phase - 0.15) * (phase - 0.15)) / (2.0 * 0.05 * 0.05));
                g2 = 0.3 * $exp(-((phase - 0.45) * (phase - 0.45)) / (2.0 * 0.05 * 0.05));
                ac = 400.0 * (g1 + g2);
                if (finger) begin
                    ir_val  = 30000 - $rtoi(ac) + ($random % 8);
                    red_val = 22000 - $rtoi(ac / 2.0) + ($random % 8);
                end else begin
                    ir_val  = 600 + ($random % 50);
                    red_val = 400 + ($random % 50);
                end
                if (count == 5'd16) begin
                    if (ovf_cnt != 5'd31) ovf_cnt = ovf_cnt + 1;
                end else begin
                    fifo_ir[wr_ptr]  = ir_val[15:0];
                    fifo_red[wr_ptr] = red_val[15:0];
                    wr_ptr = wr_ptr + 1;
                    count  = count + 1;
                end
                n_samples = n_samples + 1;
            end else
                clk_cnt = clk_cnt + 1;
        end else
            clk_cnt = 0;
    end

    // ---------------------------------------------------------------
    // Lectura y escritura de registros
    reg [7:0] ptr = 8'h00;

    function [7:0] peek;
        input [7:0] a;
        begin
            case (a)
                8'h01: peek = int_en;
                8'h02: peek = {4'd0, wr_ptr};
                8'h03: peek = {3'd0, ovf_cnt};
                8'h04: peek = {4'd0, rd_ptr};
                8'h06: peek = mode_reg;
                8'h07: peek = spo2_reg;
                8'h09: peek = led_reg;
                8'hFF: peek = 8'h11;
                default: peek = 8'h00;
            endcase
        end
    endfunction

    task read_byte;
        output [7:0] d;
        begin
            if (ptr == 8'h05) begin
                if (count == 5'd0)
                    d = 8'h00;
                else begin
                    case (byte_idx)
                        2'd0: d = fifo_ir[rd_ptr][15:8];
                        2'd1: d = fifo_ir[rd_ptr][7:0];
                        2'd2: d = fifo_red[rd_ptr][15:8];
                        default: d = fifo_red[rd_ptr][7:0];
                    endcase
                    byte_idx = byte_idx + 1;
                    if (byte_idx == 2'd0) begin
                        rd_ptr  = rd_ptr + 1;
                        count   = count - 1;
                        ovf_cnt = 5'd0;
                    end
                end
            end else begin
                d   = peek(ptr);
                ptr = ptr + 1;
            end
        end
    endtask

    task write_byte;
        input [7:0] d;
        begin
            case (ptr)
                8'h01: int_en = d;
                8'h02: begin wr_ptr = d[3:0]; count = {1'b0, wr_ptr - rd_ptr}; byte_idx = 0; end
                8'h03: ovf_cnt = d[4:0];
                8'h04: begin rd_ptr = d[3:0]; count = {1'b0, wr_ptr - rd_ptr}; byte_idx = 0; end
                8'h06: begin
                    if (d[6]) begin
                        mode_reg = 8'h00; spo2_reg = 8'h00; led_reg = 8'h00; int_en = 8'h00;
                        wr_ptr = 0; rd_ptr = 0; ovf_cnt = 0; count = 0; byte_idx = 0;
                        n_resets = n_resets + 1;
                    end else
                        mode_reg = d;
                end
                8'h07: spo2_reg = d;
                8'h09: led_reg  = d;
                default: ;
            endcase
            if (ptr != 8'h05) ptr = ptr + 1;
        end
    endtask

    // ---------------------------------------------------------------
    // Esclavo I2C
    localparam IDLE = 0, ADDR = 1, REG = 2, WDATA = 3, RDATA = 4;
    integer   st   = IDLE;
    integer   bitn = 0;
    reg [7:0] shreg;
    reg [7:0] txb;
    reg       mack;
    reg       acked;
    reg       rw;

    always @(negedge sda) if (scl === 1'b1) begin   // START o START repetido
        st      = ADDR;
        bitn    = -1;                // el flanco de bajada de SCL del START no es un bit
        sda_low = 1'b0;
    end

    always @(posedge sda) if (scl === 1'b1) begin   // STOP
        st      = IDLE;
        sda_low = 1'b0;
    end

    always @(posedge scl) if (st != IDLE) begin
        if (bitn < 8 && st != RDATA)
            shreg = {shreg[6:0], (sda === 1'b0) ? 1'b0 : 1'b1};
        if (bitn == 8 && st == RDATA)
            mack = (sda === 1'b0);
    end

    always @(negedge scl) if (st != IDLE) begin
        if (bitn < 7) begin
            bitn = bitn + 1;
            if (st == RDATA) sda_low = !txb[7 - bitn];
        end else if (bitn == 7) begin
            bitn = 8;
            acked = 1'b0;
            case (st)
                ADDR: if (connected && shreg[7:1] == 7'h57) begin
                          acked = 1'b1;
                          rw    = shreg[0];
                      end
                REG:   begin ptr = shreg; acked = 1'b1; end
                WDATA: begin write_byte(shreg); acked = 1'b1; end
                default: ;
            endcase
            if (st == RDATA)
                sda_low = 1'b0;          // el maestro responde ACK/NACK
            else if (acked)
                sda_low = 1'b1;
            else begin
                sda_low = 1'b0;
                st      = IDLE;          // NACK: ignora hasta el próximo START
            end
        end else begin                   // fin del bit de ACK
            bitn    = 0;
            sda_low = 1'b0;
            case (st)
                ADDR: if (rw) begin
                          st = RDATA;
                          read_byte(txb);
                          sda_low = !txb[7];
                      end else
                          st = REG;
                REG:   st = WDATA;
                WDATA: st = WDATA;
                RDATA: if (mack) begin
                           read_byte(txb);
                           sda_low = !txb[7];
                       end else
                           st = IDLE;
                default: ;
            endcase
        end
    end

endmodule
