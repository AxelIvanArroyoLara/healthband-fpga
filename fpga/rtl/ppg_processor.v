// ppg_processor
// Bloque de procesamiento PPG con la interfaz acordada en la guía (paso 1).
// Recibe muestras crudas del MAX30100 (o del generador sintético) y entrega
// BPM, IBI, validez y banderas de calidad. La especificación completa de
// puertos y unidades está en fpga/README.md.
//
// Cualquier falla (saturación, falta de contacto, fifo_overflow o muestras
// perdidas) descarta la muestra y reinicia filtro, detector y cálculo, de modo
// que data_valid baja de inmediato y solo vuelve tras STABLE_BEATS latidos
// consistentes. Las banderas de falla se conservan hasta que la medición
// vuelve a ser válida, para que se vean en LEDs y en depuración.
//
// Por ahora solo se procesa el canal IR; red_sample se conserva en la
// interfaz para la extensión experimental de SpO2.

module ppg_processor #(
    parameter        GAP_CYCLES      = 750_000,  // 1.5 periodos de muestra (50 MHz / 100 Hz)
    parameter [15:0] SAT_LEVEL       = 16'hFF00,
    parameter [15:0] CONTACT_MIN     = 16'd8000,
    parameter        BASE_SHIFT      = 5,
    parameter        AVG_LOG2        = 3,
    parameter        ENV_DECAY_SHIFT = 7,
    parameter        MIN_AMP         = 20,
    parameter        REFRACT         = 25,
    parameter        MIN_N           = 25,
    parameter        MAX_N           = 200,
    parameter        STABLE_BEATS    = 4
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [15:0] ir_sample,
    input  wire [15:0] red_sample,
    input  wire        sample_valid,
    input  wire        fifo_overflow,
    output wire  [7:0] bpm,
    output wire [15:0] ibi_ms,
    output wire        beat_valid,
    output wire        data_valid,
    output wire  [4:0] signal_quality
);

    localparam Q_SAT     = 0;
    localparam Q_CONTACT = 1;
    localparam Q_FIFO    = 2;
    localparam Q_GAP     = 3;

    reg        restart;
    reg        s_valid;
    reg [15:0] s_data;
    reg  [3:0] flags;
    reg        valid_d;
    reg [31:0] gap_cnt;

    wire gap_event = !sample_valid && (gap_cnt == GAP_CYCLES - 1);

    // Etapa de entrada: validación de muestras y detección de fallas.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            restart <= 1'b0;
            s_valid <= 1'b0;
            s_data  <= 16'd0;
            gap_cnt <= 0;
        end else begin
            restart <= 1'b0;
            s_valid <= 1'b0;

            if (sample_valid)
                gap_cnt <= 0;
            else if (gap_cnt != GAP_CYCLES)
                gap_cnt <= gap_cnt + 1;

            if (gap_event || fifo_overflow)
                restart <= 1'b1;
            else if (sample_valid) begin
                if (ir_sample >= SAT_LEVEL || ir_sample < CONTACT_MIN)
                    restart <= 1'b1;
                else begin
                    s_valid <= 1'b1;
                    s_data  <= ir_sample;
                end
            end
        end
    end

    // Banderas persistentes: se limpian cuando la medición vuelve a ser válida.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            flags   <= 4'd0;
            valid_d <= 1'b0;
        end else begin
            valid_d <= data_valid;
            if (data_valid && !valid_d)
                flags <= 4'd0;
            if (gap_event)
                flags[Q_GAP] <= 1'b1;
            if (fifo_overflow)
                flags[Q_FIFO] <= 1'b1;
            else if (sample_valid) begin
                if (ir_sample >= SAT_LEVEL)
                    flags[Q_SAT] <= 1'b1;
                else if (ir_sample < CONTACT_MIN)
                    flags[Q_CONTACT] <= 1'b1;
            end
        end
    end

    wire signed [17:0] filt;
    wire               filt_valid;
    wire               det_interval_ok;
    wire         [8:0] det_interval;
    wire         [8:0] det_since;
    wire               low_amp;
    wire               calc_valid;

    ppg_filter #(
        .BASE_SHIFT (BASE_SHIFT),
        .AVG_LOG2   (AVG_LOG2)
    ) u_filter (
        .clk       (clk),
        .reset_n   (reset_n),
        .restart   (restart),
        .in_valid  (s_valid),
        .x         (s_data),
        .y         (filt),
        .out_valid (filt_valid)
    );

    pulse_detector #(
        .ENV_DECAY_SHIFT (ENV_DECAY_SHIFT),
        .MIN_AMP         (MIN_AMP),
        .REFRACT         (REFRACT)
    ) u_det (
        .clk         (clk),
        .reset_n     (reset_n),
        .restart     (restart),
        .in_valid    (filt_valid),
        .s           (filt),
        .beat        (beat_valid),
        .interval_ok (det_interval_ok),
        .interval    (det_interval),
        .since       (det_since),
        .low_amp     (low_amp)
    );

    bpm_calc #(
        .MIN_N        (MIN_N),
        .MAX_N        (MAX_N),
        .STABLE_BEATS (STABLE_BEATS)
    ) u_calc (
        .clk      (clk),
        .reset_n  (reset_n),
        .restart  (restart),
        .beat_in  (det_interval_ok),
        .interval (det_interval),
        .since    (det_since),
        .bpm      (bpm),
        .ibi_ms   (ibi_ms),
        .valid    (calc_valid)
    );

    assign data_valid     = calc_valid && !low_amp;
    assign signal_quality = {low_amp, flags};

endmodule
