// healthband_top
// Top-level para la Terasic DE10-Lite (MAX 10, 10M50DAF484C7G).
//
// Entradas de usuario
//   KEY[0]   reset (activo en bajo)
//   SW[1:0]  BPM del generador sintético: 00=60, 01=75, 10=100, 11=120
//   SW[2]    ruido en la señal sintética
//   SW[3]    simula dedo retirado (debe producir Q=0)
//   SW[4]    simula saturación del sensor (debe producir Q=0)
//
// Salidas
//   HEX2..HEX0  BPM, o "---" si no hay medición válida
//   LEDR[0]     parpadea con cada latido detectado
//   LEDR[1]     data_valid (Q=1)
//   LEDR[6:2]   signal_quality: saturación, sin contacto, FIFO, muestras perdidas, amplitud baja
//   LEDR[7]     UART transmitiendo
//   LEDR[9]     fuente sintética activa
//   GPIO[2]     UART TX hacia el RX del ESP32 (JP1 pin 3, PIN_V9), 115200 8N1, 3.3 V
//
// GPIO[0] (SCL, PIN_V10) y GPIO[1] (SDA, PIN_W10) quedan reservados para el
// controlador I2C del MAX30100 de Sebas. Para integrarlo, conectar sus salidas
// ir/red/sample_valid/fifo_overflow en lugar de las de ppg_synth (ver
// fpga/README.md); no hay que modificar ppg_processor.

module healthband_top #(
    parameter CLK_HZ    = 50_000_000,
    parameter BAUD      = 115_200,
    parameter SAMPLE_HZ = 100,
    parameter FRAME_HZ  = 1
) (
    input  wire       MAX10_CLK1_50,
    input  wire [1:0] KEY,
    input  wire [9:0] SW,
    output wire [9:0] LEDR,
    output wire [7:0] HEX0,
    output wire [7:0] HEX1,
    output wire [7:0] HEX2,
    output wire [7:0] HEX3,
    output wire [7:0] HEX4,
    output wire [7:0] HEX5,
    inout  wire [3:0] GPIO
);

    wire clk = MAX10_CLK1_50;

    // Reset: aserción asíncrona, liberación sincronizada.
    reg [1:0] rst_sync;
    always @(posedge clk or negedge KEY[0]) begin
        if (!KEY[0])
            rst_sync <= 2'b00;
        else
            rst_sync <= {rst_sync[0], 1'b1};
    end
    wire reset_n = rst_sync[1];

    // Sincronización de interruptores.
    reg [9:0] sw_meta, sw_sync;
    always @(posedge clk) begin
        sw_meta <= SW;
        sw_sync <= sw_meta;
    end

    // Fuente de muestras: generador sintético (el MAX30100 se conectará aquí).
    wire [15:0] ir_sample;
    wire [15:0] red_sample;
    wire        sample_valid;
    wire        fifo_overflow;

    ppg_synth #(
        .CLK_HZ    (CLK_HZ),
        .SAMPLE_HZ (SAMPLE_HZ)
    ) u_synth (
        .clk           (clk),
        .reset_n       (reset_n),
        .rate_sel      (sw_sync[1:0]),
        .noise_en      (sw_sync[2]),
        .no_contact    (sw_sync[3]),
        .saturate      (sw_sync[4]),
        .ir_sample     (ir_sample),
        .red_sample    (red_sample),
        .sample_valid  (sample_valid),
        .fifo_overflow (fifo_overflow)
    );

    // Procesamiento PPG.
    wire  [7:0] bpm;
    wire [15:0] ibi_ms;
    wire        beat_valid;
    wire        data_valid;
    wire  [4:0] signal_quality;

    ppg_processor #(
        .GAP_CYCLES (CLK_HZ / SAMPLE_HZ * 3 / 2)
    ) u_proc (
        .clk            (clk),
        .reset_n        (reset_n),
        .ir_sample      (ir_sample),
        .red_sample     (red_sample),
        .sample_valid   (sample_valid),
        .fifo_overflow  (fifo_overflow),
        .bpm            (bpm),
        .ibi_ms         (ibi_ms),
        .beat_valid     (beat_valid),
        .data_valid     (data_valid),
        .signal_quality (signal_quality)
    );

    // Trama HB1 por UART.
    wire [7:0] tx_data;
    wire       tx_start;
    wire       tx_busy;
    wire       uart_tx_pin;

    hb1_framer #(
        .CLK_HZ   (CLK_HZ),
        .FRAME_HZ (FRAME_HZ)
    ) u_framer (
        .clk        (clk),
        .reset_n    (reset_n),
        .bpm        (bpm),
        .ibi_ms     (ibi_ms),
        .data_valid (data_valid),
        .tx_data    (tx_data),
        .tx_start   (tx_start),
        .tx_busy    (tx_busy)
    );

    uart_tx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) u_uart (
        .clk     (clk),
        .reset_n (reset_n),
        .data    (tx_data),
        .start   (tx_start),
        .busy    (tx_busy),
        .tx      (uart_tx_pin)
    );

    assign GPIO[0] = 1'bz;          // SCL, reservado para el I2C de Sebas
    assign GPIO[1] = 1'bz;          // SDA, reservado para el I2C de Sebas
    assign GPIO[2] = uart_tx_pin;   // FPGA TX -> ESP32 RX
    assign GPIO[3] = 1'bz;          // FPGA RX, sin uso

    // Displays.
    seg7_bpm u_seg7 (
        .bpm   (bpm),
        .valid (data_valid),
        .hex0  (HEX0),
        .hex1  (HEX1),
        .hex2  (HEX2)
    );
    assign HEX3 = 8'hFF;
    assign HEX4 = 8'hFF;
    assign HEX5 = 8'hFF;

    // LED de latido: alarga el pulso de un ciclo a 100 ms.
    localparam BEAT_LED_CYCLES = CLK_HZ / 10;
    reg [31:0] beat_led_cnt;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            beat_led_cnt <= 0;
        else if (beat_valid)
            beat_led_cnt <= BEAT_LED_CYCLES;
        else if (beat_led_cnt != 0)
            beat_led_cnt <= beat_led_cnt - 1;
    end

    assign LEDR[0]   = (beat_led_cnt != 0);
    assign LEDR[1]   = data_valid;
    assign LEDR[6:2] = signal_quality;
    assign LEDR[7]   = tx_busy;
    assign LEDR[8]   = 1'b0;
    assign LEDR[9]   = 1'b1;

endmodule
