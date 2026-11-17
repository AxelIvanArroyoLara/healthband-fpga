// ppg_filter
// Quita la componente DC de la señal IR y la suaviza.
//
//   base[n] = acc >> BASE_SHIFT              (media exponencial, fc ~ 0.5 Hz a 100 Hz)
//   ac[n]   = base[n] - x[n]                 (invertida: la sístole queda positiva)
//   y[n]    = promedio de los últimos 2^AVG_LOG2 valores de ac
//
// Solo usa sumas y desplazamientos. La primera muestra después de restart
// inicializa la línea base para no esperar a que converja.
// Modelo de referencia: fpga/model/ppg_model.py (PpgFilter).

module ppg_filter #(
    parameter BASE_SHIFT = 5,
    parameter AVG_LOG2   = 3
) (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               restart,
    input  wire               in_valid,
    input  wire        [15:0] x,
    output reg  signed [17:0] y,
    output reg                out_valid
);

    localparam AVG_LEN = 1 << AVG_LOG2;
    localparam ACC_W   = 17 + BASE_SHIFT;  // x * 2^BASE_SHIFT más un bit de margen
    localparam SUM_W   = 18 + AVG_LOG2;    // suma de AVG_LEN valores de 18 bits

    reg        [ACC_W-1:0] acc;
    reg                    primed;
    reg signed      [17:0] win [0:AVG_LEN-1];
    reg signed [SUM_W-1:0] sum;

    wire       [ACC_W-1:0] base_w   = acc >> BASE_SHIFT;
    wire            [15:0] base     = base_w[15:0];
    wire signed     [17:0] ac       = primed ? ($signed({2'b00, base}) - $signed({2'b00, x}))
                                             : 18'sd0;
    wire signed [SUM_W-1:0] sum_next = sum + ac - win[AVG_LEN-1];

    integer i;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            acc       <= 0;
            primed    <= 1'b0;
            sum       <= 0;
            y         <= 0;
            out_valid <= 1'b0;
            for (i = 0; i < AVG_LEN; i = i + 1)
                win[i] <= 0;
        end else if (restart) begin
            acc       <= 0;
            primed    <= 1'b0;
            sum       <= 0;
            y         <= 0;
            out_valid <= 1'b0;
            for (i = 0; i < AVG_LEN; i = i + 1)
                win[i] <= 0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                if (primed)
                    acc <= acc + x - base;
                else
                    acc <= x << BASE_SHIFT;
                primed <= 1'b1;

                win[0] <= ac;
                for (i = 1; i < AVG_LEN; i = i + 1)
                    win[i] <= win[i-1];
                sum <= sum_next;
                y   <= sum_next >>> AVG_LOG2;
            end
        end
    end

endmodule
