// pulse_detector
// Detecta un latido por periodo con umbral adaptativo, histéresis y periodo
// refractario.
//
//   env     sigue el máximo de la señal y decae env/2^ENV_DECAY_SHIFT por muestra
//   umbral  env/2
//   armado  la señal tiene que bajar de 0 antes de aceptar el siguiente latido
//   latido  armado && s > umbral && env >= MIN_AMP && han pasado REFRACT muestras
//
// interval es el número de muestras entre este latido y el anterior; solo es
// significativo cuando interval_ok = 1 (existe un latido previo).
// Modelo de referencia: fpga/model/ppg_model.py (PulseDetector).

module pulse_detector #(
    parameter ENV_DECAY_SHIFT = 7,
    parameter MIN_AMP         = 20,
    parameter REFRACT         = 25
) (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               restart,
    input  wire               in_valid,
    input  wire signed [17:0] s,
    output reg                beat,         // pulso de 1 ciclo por latido
    output reg                interval_ok,  // pulso de 1 ciclo junto con beat si hay latido previo
    output reg          [8:0] interval,     // muestras entre latidos
    output wire         [8:0] since,        // muestras desde el último latido (satura en 511)
    output wire               low_amp       // envolvente por debajo de MIN_AMP
);

    reg signed [17:0] env;
    reg               armed;
    reg               have_prev;
    reg         [8:0] cnt;

    wire signed [17:0] thr     = env >>> 1;
    wire         [8:0] cnt_inc = (cnt == 9'd511) ? cnt : cnt + 9'd1;
    wire               is_beat = armed && (s > thr) && (env >= MIN_AMP) && (cnt_inc >= REFRACT);

    assign since   = cnt;
    assign low_amp = (env < MIN_AMP);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            env         <= 18'sd0;
            armed       <= 1'b0;
            have_prev   <= 1'b0;
            cnt         <= 9'd0;
            beat        <= 1'b0;
            interval_ok <= 1'b0;
            interval    <= 9'd0;
        end else if (restart) begin
            env         <= 18'sd0;
            armed       <= 1'b0;
            have_prev   <= 1'b0;
            cnt         <= 9'd0;
            beat        <= 1'b0;
            interval_ok <= 1'b0;
            interval    <= 9'd0;
        end else begin
            beat        <= 1'b0;
            interval_ok <= 1'b0;
            if (in_valid) begin
                if (s > env)
                    env <= s;
                else
                    env <= env - (env >>> ENV_DECAY_SHIFT);

                if (is_beat) begin
                    beat        <= 1'b1;
                    interval_ok <= have_prev;
                    interval    <= cnt_inc;
                    have_prev   <= 1'b1;
                    armed       <= 1'b0;
                    cnt         <= 9'd0;
                end else begin
                    armed <= armed | s[17];
                    cnt   <= cnt_inc;
                end
            end
        end
    end

endmodule
