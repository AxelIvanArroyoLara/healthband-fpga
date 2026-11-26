// max30100_model
// Modelo de comportamiento (solo simulación) del MAX30100 o del MAX30102 como
// esclavo I2C (IS102 = 0 o 1).
//
//                      MAX30100              MAX30102
//   PART_ID (0xFF)     0x11                  0x15
//   INT_EN             0x01                  0x02
//   WR/OVF/RD_PTR      0x02/0x03/0x04        0x04/0x05/0x06
//   FIFO_DATA          0x05                  0x07
//   FIFO_CONFIG        -                     0x08
//   MODE               0x06                  0x09
//   SPO2_CONFIG        0x07                  0x0A
//   LED                0x09 {RED,IR}         0x0C (RED), 0x0D (IR)
//   FIFO               16 x 4 bytes          32 x 6 bytes
//                      IR[15:0], RED[15:0]   RED[17:0], IR[17:0] (3 bytes c/u)
//
// - El puntero de registro se autoincrementa, excepto en FIFO_DATA.
// - Escribir 0x40 en MODE reinicia los registros.
// - Con modo HR o SpO2 genera una muestra cada SAMPLE_CLKS ciclos de clk
//   (su propio "oscilador", distinto del de la FPGA) con una forma de onda PPG:
//   nivel DC alto que baja en cada sístole, más una onda dicrótica y ruido.
//
// Controles desde el testbench: bpm (real), finger (dedo puesto),
// connected (0 = no responde ACK, como si estuviera desconectado).

`timescale 1ns / 1ps

module max30100_model #(
    parameter SAMPLE_CLKS = 11_578,
    parameter IS102       = 0
) (
    input  wire clk,
    input  wire scl,
    inout  wire sda
);

    localparam [7:0] R_INTEN = IS102 ? 8'h02 : 8'h01;
    localparam [7:0] R_WR    = IS102 ? 8'h04 : 8'h02;
    localparam [7:0] R_OVF   = IS102 ? 8'h05 : 8'h03;
    localparam [7:0] R_RD    = IS102 ? 8'h06 : 8'h04;
    localparam [7:0] R_FIFO  = IS102 ? 8'h07 : 8'h05;
    localparam [7:0] R_MODE  = IS102 ? 8'h09 : 8'h06;
    localparam [7:0] R_SPO2  = IS102 ? 8'h0A : 8'h07;
    localparam [7:0] R_LED   = IS102 ? 8'h0C : 8'h09;
    localparam [7:0] PART    = IS102 ? 8'h15 : 8'h11;
    localparam       DEPTH   = IS102 ? 32 : 16;
    localparam       NBYTES  = IS102 ? 6 : 4;
    localparam real  SCALE   = IS102 ? 4.0 : 1.0;   // 18 bits contra 16 bits

    real    bpm       = 72.0;
    reg     finger    = 1'b1;
    reg     connected = 1'b1;

    reg sda_low = 1'b0;
    assign sda = sda_low ? 1'b0 : 1'bz;

    // Registros visibles para el testbench.
    reg [7:0] mode_reg = 8'h00;
    reg [7:0] spo2_reg = 8'h00;
    reg [7:0] led_reg  = 8'h00;   // MAX30100: {RED,IR}; MAX30102: RED (0x0C)
    reg [7:0] led2_reg = 8'h00;   // MAX30102: IR (0x0D)
    reg [7:0] fcfg_reg = 8'hFF;   // MAX30102: FIFO_CONFIG
    reg [7:0] int_en   = 8'h00;
    integer   wr_ptr   = 0;
    integer   rd_ptr   = 0;
    integer   ovf_cnt  = 0;
    integer   count    = 0;
    integer   byte_idx = 0;
    integer   fifo_ir  [0:31];
    integer   fifo_red [0:31];
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
                    ir_val  = $rtoi(SCALE * (30000.0 - ac)) + ($random % 8);
                    red_val = $rtoi(SCALE * (22000.0 - ac / 2.0)) + ($random % 8);
                end else begin
                    ir_val  = $rtoi(SCALE * 600.0) + ($random % 50);
                    red_val = $rtoi(SCALE * 400.0) + ($random % 50);
                end
                if (count == DEPTH) begin
                    if (ovf_cnt != 31) ovf_cnt = ovf_cnt + 1;
                end else begin
                    fifo_ir[wr_ptr]  = ir_val;
                    fifo_red[wr_ptr] = red_val;
                    wr_ptr = (wr_ptr + 1) % DEPTH;
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
            peek = 8'h00;
            if (a == R_INTEN)           peek = int_en;
            else if (a == R_WR)         peek = wr_ptr;
            else if (a == R_OVF)        peek = ovf_cnt;
            else if (a == R_RD)         peek = rd_ptr;
            else if (a == R_MODE)       peek = mode_reg;
            else if (a == R_SPO2)       peek = spo2_reg;
            else if (a == R_LED)        peek = led_reg;
            else if (IS102 && a == 8'h0D) peek = led2_reg;
            else if (IS102 && a == 8'h08) peek = fcfg_reg;
            else if (a == 8'hFF)        peek = PART;
        end
    endfunction

    function [7:0] fifo_byte;
        input integer idx;
        input integer bi;
        reg [23:0] w;
        begin
            if (IS102) begin
                w = (bi < 3) ? fifo_red[idx] : fifo_ir[idx];
                w = w & 24'h03FFFF;
                case (bi % 3)
                    0: fifo_byte = w[23:16];
                    1: fifo_byte = w[15:8];
                    default: fifo_byte = w[7:0];
                endcase
            end else begin
                w = (bi < 2) ? fifo_ir[idx] : fifo_red[idx];
                fifo_byte = (bi % 2 == 0) ? w[15:8] : w[7:0];
            end
        end
    endfunction

    task read_byte;
        output [7:0] d;
        begin
            if (ptr == R_FIFO) begin
                if (count == 0)
                    d = 8'h00;
                else begin
                    d = fifo_byte(rd_ptr, byte_idx);
                    byte_idx = byte_idx + 1;
                    if (byte_idx == NBYTES) begin
                        byte_idx = 0;
                        rd_ptr   = (rd_ptr + 1) % DEPTH;
                        count    = count - 1;
                        ovf_cnt  = 0;
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
            if (ptr == R_INTEN) int_en = d;
            else if (ptr == R_WR)  begin wr_ptr = d % DEPTH; count = (wr_ptr - rd_ptr + DEPTH) % DEPTH; byte_idx = 0; end
            else if (ptr == R_OVF) ovf_cnt = d;
            else if (ptr == R_RD)  begin rd_ptr = d % DEPTH; count = (wr_ptr - rd_ptr + DEPTH) % DEPTH; byte_idx = 0; end
            else if (ptr == R_MODE) begin
                if (d[6]) begin
                    mode_reg = 8'h00; spo2_reg = 8'h00; led_reg = 8'h00; led2_reg = 8'h00;
                    int_en = 8'h00; fcfg_reg = 8'hFF;
                    wr_ptr = 0; rd_ptr = 0; ovf_cnt = 0; count = 0; byte_idx = 0;
                    n_resets = n_resets + 1;
                end else
                    mode_reg = d;
            end
            else if (ptr == R_SPO2) spo2_reg = d;
            else if (ptr == R_LED)  led_reg  = d;
            else if (IS102 && ptr == 8'h0D) led2_reg = d;
            else if (IS102 && ptr == 8'h08) fcfg_reg = d;
            if (ptr != R_FIFO) ptr = ptr + 1;
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
