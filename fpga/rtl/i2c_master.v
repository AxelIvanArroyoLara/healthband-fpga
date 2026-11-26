// i2c_master
// Maestro I2C a nivel de byte (open drain) para el MAX30100.
//
// Cada comando se ejecuta en cuartos de periodo de SCL (QDIV ciclos de clk):
//   CMD_START  condición de START; sirve también como START repetido.
//              Funciona con SCL en alto (bus libre) o en bajo (tras un byte).
//   CMD_WRITE  envía wdata (MSB primero) y lee el ACK del esclavo -> ack.
//   CMD_READ   recibe un byte -> rdata y responde ACK, o NACK si rd_nack = 1.
//              Con rd_nack = 1 sirve además para liberar el bus: da 9 pulsos
//              de SCL con SDA suelta (recuperación si el esclavo quedó a medias).
//   CMD_STOP   condición de STOP; deja el bus libre (SCL y SDA en alto).
//
// Después de START, WRITE y READ, SCL queda en bajo.
// scl_oe/sda_oe = 1 jalan la línea a 0; con 0 la línea queda en alta impedancia
// y la sube la resistencia de pull-up (la del módulo y la débil de la FPGA).

module i2c_master #(
    parameter CLK_HZ = 50_000_000,
    parameter I2C_HZ = 100_000
) (
    input  wire       clk,
    input  wire       reset_n,
    input  wire [1:0] cmd,
    input  wire       go,        // pulso de 1 ciclo con busy = 0
    input  wire [7:0] wdata,
    input  wire       rd_nack,
    output reg        busy,
    output reg        done,      // pulso de 1 ciclo al terminar el comando
    output reg  [7:0] rdata,
    output reg        ack,       // 1 = el esclavo respondió ACK al último WRITE
    output reg        scl_oe,
    output reg        sda_oe,
    input  wire       sda_in
);

    localparam [1:0] CMD_START = 2'd0,
                     CMD_WRITE = 2'd1,
                     CMD_READ  = 2'd2,
                     CMD_STOP  = 2'd3;

    localparam QDIV = (CLK_HZ / (4 * I2C_HZ)) < 2 ? 2 : (CLK_HZ / (4 * I2C_HZ));

    reg [15:0] qcnt;
    reg  [1:0] q;        // cuarto de periodo dentro del bit
    reg  [3:0] bitn;     // 0..7 datos, 8 = ACK/NACK
    reg  [1:0] op;
    reg  [7:0] sh;
    reg        nack_r;
    reg  [1:0] sda_s;    // sincronizador de SDA

    wire qtick = (qcnt == QDIV - 1);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy   <= 1'b0;
            done   <= 1'b0;
            rdata  <= 8'd0;
            ack    <= 1'b0;
            scl_oe <= 1'b0;
            sda_oe <= 1'b0;
            qcnt   <= 16'd0;
            q      <= 2'd0;
            bitn   <= 4'd0;
            op     <= CMD_STOP;
            sh     <= 8'd0;
            nack_r <= 1'b0;
            sda_s  <= 2'b11;
        end else begin
            done  <= 1'b0;
            sda_s <= {sda_s[0], sda_in};

            if (!busy) begin
                qcnt <= 16'd0;
                if (go) begin
                    busy   <= 1'b1;
                    op     <= cmd;
                    sh     <= wdata;
                    nack_r <= rd_nack;
                    q      <= 2'd0;
                    bitn   <= 4'd0;
                end
            end else if (!qtick) begin
                qcnt <= qcnt + 16'd1;
            end else begin
                qcnt <= 16'd0;
                q    <= q + 2'd1;

                case (op)
                    CMD_START: case (q)
                        2'd0: sda_oe <= 1'b0;   // SDA arriba (SCL puede estar abajo)
                        2'd1: scl_oe <= 1'b0;   // SCL arriba
                        2'd2: sda_oe <= 1'b1;   // SDA baja con SCL arriba: START
                        2'd3: scl_oe <= 1'b1;   // SCL abajo
                    endcase

                    CMD_STOP: case (q)
                        2'd0: sda_oe <= 1'b1;   // SDA abajo con SCL abajo
                        2'd1: scl_oe <= 1'b0;   // SCL arriba
                        2'd2: sda_oe <= 1'b0;   // SDA sube con SCL arriba: STOP
                        2'd3: ;
                    endcase

                    default: case (q)          // CMD_WRITE / CMD_READ
                        2'd0: begin
                            if (bitn != 4'd8)
                                sda_oe <= (op == CMD_WRITE) ? ~sh[7] : 1'b0;
                            else
                                sda_oe <= (op == CMD_WRITE) ? 1'b0 : ~nack_r;
                        end
                        2'd1: scl_oe <= 1'b0;
                        2'd2: begin
                            if (bitn != 4'd8)
                                sh <= {sh[6:0], (op == CMD_READ) ? sda_s[1] : 1'b0};
                            else if (op == CMD_WRITE)
                                ack <= ~sda_s[1];
                        end
                        2'd3: scl_oe <= 1'b1;
                    endcase
                endcase

                if (q == 2'd3) begin
                    if (op == CMD_START || op == CMD_STOP || bitn == 4'd8) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        if (op == CMD_READ)
                            rdata <= sh;
                    end else begin
                        bitn <= bitn + 4'd1;
                    end
                end
            end
        end
    end

endmodule
