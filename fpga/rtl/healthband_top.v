// healthband_top
// Top-level para la Terasic DE10-Lite (MAX 10, 10M50DAF484C7G).
//
// Entradas de usuario
//   KEY[0]   reset (activo en bajo)
//   SW[9]    fuente de muestras: 0 = sensor MAX30100 por I2C, 1 = generador sintético
//   SW[8]    display de depuración: HEX3..HEX0 = IR crudo (hex), HEX5..HEX4 = PART_ID
//   SW[7:5]  corriente de los LEDs del MAX30100: 000 = 24 mA (por defecto),
//            001 = 11, 010 = 17.4, 011 = 24, 100 = 30.6, 101 = 37, 110 = 43.6, 111 = 50 mA
//   Solo con SW[9] = 1 (generador sintético):
//   SW[1:0]  BPM: 00=60, 01=75, 10=100, 11=120
//   SW[2]    ruido en la señal sintética
//   SW[3]    simula dedo retirado (debe producir Q=0)
//   SW[4]    simula saturación del sensor (debe producir Q=0)
//
// Salidas
//   HEX2..HEX0  BPM, o "---" si no hay medición válida (con SW[8] = 0)
//   LEDR[0]     parpadea con cada latido detectado
//   LEDR[1]     data_valid (Q=1)
//   LEDR[6:2]   signal_quality: saturación, sin contacto, FIFO, muestras perdidas, amplitud baja
//   LEDR[7]     UART transmitiendo
//   LEDR[8]     MAX30100 configurado y respondiendo por I2C
//   LEDR[9]     fuente sintética activa
//
// Header JP1 (GPIO)
//   GPIO[0]  JP1 pin 1 (PIN_V10)  SCL del MAX30100 (open drain)
//   GPIO[1]  JP1 pin 2 (PIN_W10)  SDA del MAX30100 (open drain)
//   GPIO[2]  JP1 pin 3 (PIN_V9)   UART TX hacia el RX del ESP32, 115200 8N1, 3.3 V
//   GPIO[3]  JP1 pin 4 (PIN_W9)   sin uso
//   JP1 pin 29 = 3.3 V (verificar alimentación del breakout), JP1 pin 12 o 30 = GND

module healthband_top #(
    parameter CLK_HZ    = 50_000_000,
    parameter BAUD      = 115_200,
    parameter SAMPLE_HZ = 100,
    parameter FRAME_HZ  = 1,
    parameter I2C_HZ    = 100_000,
    parameter BOOT_MS   = 20
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

    wire use_synth = sw_sync[9];

    // ------------------------------------------------------------------
    // Fuente 1: generador sintético (prueba sin sensor).
    wire [15:0] syn_ir, syn_red;
    wire        syn_valid, syn_ovf;

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
        .ir_sample     (syn_ir),
        .red_sample    (syn_red),
        .sample_valid  (syn_valid),
        .fifo_overflow (syn_ovf)
    );

    // ------------------------------------------------------------------
    // Fuente 2: sensor MAX30100 por I2C.
    wire [15:0] max_ir, max_red;
    wire        max_valid, max_ovf;
    wire        sensor_ok, i2c_error;
    wire  [7:0] part_id;
    wire        scl_oe, sda_oe;

    // Corriente de LEDs: el código de 4 bits del MAX30100 es {SW[7:5], 1}.
    wire [3:0] led_pa  = (sw_sync[7:5] == 3'd0) ? 4'h7 : {sw_sync[7:5], 1'b1};
    wire [7:0] led_cfg = {led_pa, led_pa};

    max30100_ctrl #(
        .CLK_HZ  (CLK_HZ),
        .I2C_HZ  (I2C_HZ),
        .BOOT_MS (BOOT_MS)
    ) u_max (
        .clk           (clk),
        .reset_n       (reset_n),
        .led_cfg       (led_cfg),
        .ir_sample     (max_ir),
        .red_sample    (max_red),
        .sample_valid  (max_valid),
        .fifo_overflow (max_ovf),
        .sensor_ok     (sensor_ok),
        .i2c_error     (i2c_error),
        .part_id       (part_id),
        .scl_oe        (scl_oe),
        .sda_oe        (sda_oe),
        .is_max30102   (),
        .sda_in        (GPIO[1])
    );

    assign GPIO[0] = scl_oe ? 1'b0 : 1'bz;   // SCL open drain
    assign GPIO[1] = sda_oe ? 1'b0 : 1'bz;   // SDA open drain

    // Selección de fuente.
    wire [15:0] ir_sample     = use_synth ? syn_ir    : max_ir;
    wire [15:0] red_sample    = use_synth ? syn_red   : max_red;
    wire        sample_valid  = use_synth ? syn_valid : max_valid;
    wire        fifo_overflow = use_synth ? syn_ovf   : max_ovf;

    // ------------------------------------------------------------------
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

    assign GPIO[2] = uart_tx_pin;   // FPGA TX -> ESP32 RX
    assign GPIO[3] = 1'bz;          // FPGA RX, sin uso

    // ------------------------------------------------------------------
    // Displays.
    wire [7:0] bpm_hex0, bpm_hex1, bpm_hex2;

    seg7_bpm u_seg7 (
        .bpm   (bpm),
        .valid (data_valid),
        .hex0  (bpm_hex0),
        .hex1  (bpm_hex1),
        .hex2  (bpm_hex2)
    );

    function [7:0] seg_hex;
        input [3:0] d;
        case (d)
            4'h0: seg_hex = 8'hC0;  4'h1: seg_hex = 8'hF9;
            4'h2: seg_hex = 8'hA4;  4'h3: seg_hex = 8'hB0;
            4'h4: seg_hex = 8'h99;  4'h5: seg_hex = 8'h92;
            4'h6: seg_hex = 8'h82;  4'h7: seg_hex = 8'hF8;
            4'h8: seg_hex = 8'h80;  4'h9: seg_hex = 8'h90;
            4'hA: seg_hex = 8'h88;  4'hB: seg_hex = 8'h83;
            4'hC: seg_hex = 8'hC6;  4'hD: seg_hex = 8'hA1;
            4'hE: seg_hex = 8'h86;  default: seg_hex = 8'h8E;
        endcase
    endfunction

    wire debug = sw_sync[8];

    assign HEX0 = debug ? seg_hex(ir_sample[3:0])   : bpm_hex0;
    assign HEX1 = debug ? seg_hex(ir_sample[7:4])   : bpm_hex1;
    assign HEX2 = debug ? seg_hex(ir_sample[11:8])  : bpm_hex2;
    assign HEX3 = debug ? seg_hex(ir_sample[15:12]) : 8'hFF;
    assign HEX4 = debug ? seg_hex(part_id[3:0])     : 8'hFF;
    assign HEX5 = debug ? seg_hex(part_id[7:4])     : 8'hFF;

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
    assign LEDR[8]   = sensor_ok;
    assign LEDR[9]   = use_synth;

endmodule
