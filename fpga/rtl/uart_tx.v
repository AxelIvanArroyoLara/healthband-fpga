// uart_tx
// Transmisor UART 8N1: bit de inicio, 8 datos (LSB primero) y bit de parada.
// Con CLK_HZ = 50 MHz y BAUD = 115200 el divisor es 434 (error 0.01 %).
// Para enviar un byte: poner data y dar un pulso de start mientras busy = 0.

module uart_tx #(
    parameter CLK_HZ = 50_000_000,
    parameter BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       reset_n,
    input  wire [7:0] data,
    input  wire       start,
    output reg        busy,
    output reg        tx
);

    localparam DIV = (CLK_HZ + BAUD / 2) / BAUD;

    reg [15:0] cnt;
    reg  [3:0] bitn;
    reg  [8:0] shreg;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy  <= 1'b0;
            tx    <= 1'b1;
            cnt   <= 16'd0;
            bitn  <= 4'd0;
            shreg <= 9'h1FF;
        end else if (!busy) begin
            tx <= 1'b1;
            if (start) begin
                shreg <= {1'b1, data};   // datos y bit de parada
                tx    <= 1'b0;           // bit de inicio
                cnt   <= DIV - 1;
                bitn  <= 4'd0;
                busy  <= 1'b1;
            end
        end else if (cnt != 0) begin
            cnt <= cnt - 16'd1;
        end else if (bitn == 4'd9) begin
            busy <= 1'b0;                // terminó el bit de parada
        end else begin
            tx    <= shreg[0];
            shreg <= {1'b1, shreg[8:1]};
            bitn  <= bitn + 4'd1;
            cnt   <= DIV - 1;
        end
    end

endmodule
