// bpm_calc
// Convierte intervalos entre latidos en BPM e IBI con indicador de validez.
//
//   - Acepta intervalos de MIN_N a MAX_N muestras (240 a 30 BPM a 100 Hz).
//   - Un intervalo que difiere más de 25 % del anterior reinicia la cuenta de
//     estabilidad (rechaza doble pico y latidos perdidos).
//   - valid = 1 solo con STABLE_BEATS intervalos consistentes seguidos.
//   - bpm    = round(6000 / promedio de los últimos 4 intervalos)
//            = round(24000 / suma), con un divisor secuencial de 15 ciclos.
//   - ibi_ms = 10 * último intervalo (1 muestra = 10 ms).
//   - Más de MAX_N muestras sin latido (pérdida de contacto) invalida la medición.
// Modelo de referencia: fpga/model/ppg_model.py (BpmCalc).

module bpm_calc #(
    parameter MIN_N        = 25,
    parameter MAX_N        = 200,
    parameter STABLE_BEATS = 4
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        restart,
    input  wire        beat_in,   // interval_ok del detector
    input  wire  [8:0] interval,
    input  wire  [8:0] since,
    output reg   [7:0] bpm,
    output reg  [15:0] ibi_ms,
    output reg         valid
);

    reg  [8:0] h0, h1, h2, h3;
    reg  [8:0] last_n;
    reg  [3:0] stable;

    // Divisor restaurador: quo = num / den.
    reg        busy;
    reg  [3:0] step;
    reg [14:0] num;
    reg  [9:0] den;
    reg [14:0] quo;
    reg [10:0] rem;
    reg [15:0] ibi_pending;

    wire        in_range   = (interval >= MIN_N) && (interval <= MAX_N);
    wire  [8:0] diff       = (interval > last_n) ? (interval - last_n) : (last_n - interval);
    wire        consistent = (diff <= (last_n >> 2));
    wire  [3:0] stable_inc = (stable == 4'd15) ? stable : stable + 4'd1;
    wire  [3:0] stable_new = (stable == 4'd0 || !consistent) ? 4'd1 : stable_inc;
    wire [10:0] sum_new    = interval + h0 + h1 + h2;
    wire [10:0] rem_sh     = {rem[9:0], num[14]};
    wire        rem_ge     = (rem_sh >= {1'b0, den});

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            h0 <= 0; h1 <= 0; h2 <= 0; h3 <= 0;
            last_n      <= 0;
            stable      <= 0;
            bpm         <= 0;
            ibi_ms      <= 0;
            valid       <= 1'b0;
            busy        <= 1'b0;
            step        <= 0;
            num         <= 0;
            den         <= 0;
            quo         <= 0;
            rem         <= 0;
            ibi_pending <= 0;
        end else if (restart) begin
            h0 <= 0; h1 <= 0; h2 <= 0; h3 <= 0;
            last_n <= 0;
            stable <= 0;
            bpm    <= 0;
            ibi_ms <= 0;
            valid  <= 1'b0;
            busy   <= 1'b0;
        end else if (beat_in) begin
            last_n <= interval;
            if (!in_range) begin
                stable <= 0;
                valid  <= 1'b0;
                busy   <= 1'b0;
            end else begin
                h0 <= interval; h1 <= h0; h2 <= h1; h3 <= h2;
                stable <= stable_new;
                if (stable_new >= STABLE_BEATS) begin
                    // El valor anterior sigue publicado mientras se divide.
                    num         <= 15'd24000 + (sum_new >> 1);
                    den         <= sum_new[9:0];
                    quo         <= 0;
                    rem         <= 0;
                    step        <= 4'd15;
                    busy        <= 1'b1;
                    ibi_pending <= {interval, 3'b000} + {interval, 1'b0};
                end else begin
                    valid <= 1'b0;
                    busy  <= 1'b0;
                end
            end
        end else if (since > MAX_N && stable != 0) begin
            stable <= 0;
            valid  <= 1'b0;
            busy   <= 1'b0;
        end else if (busy) begin
            if (step != 0) begin
                rem  <= rem_ge ? (rem_sh - {1'b0, den}) : rem_sh;
                quo  <= {quo[13:0], rem_ge};
                num  <= num << 1;
                step <= step - 4'd1;
            end else begin
                bpm    <= quo[7:0];
                ibi_ms <= ibi_pending;
                valid  <= 1'b1;
                busy   <= 1'b0;
            end
        end
    end

endmodule
