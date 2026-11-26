// tb_max30100_top
// (Con -P tb_max30100_top.IS102=1 se prueba igual con el modelo del MAX30102.)
// Prueba de sistema del top-level con el sensor real (SW[9] = 0):
// MAX30100 (modelo I2C) -> max30100_ctrl -> ppg_processor -> hb1_framer
// -> uart_tx -> pin GPIO[2]. Decodifica las tramas como lo haría el ESP32.
//
// Escalado para que la simulación sea corta: CLK_HZ = 1 152 000 (divisor UART
// exacto de 10) e I2C a 48 kHz (6 ciclos por cuarto de bit). El modelo del
// sensor muestrea con su propio reloj, 0.5 % más lento que 100 Hz, para probar
// que la lectura por punteros del FIFO no pierde ni duplica muestras.
//
// Escenario:
//   0-10 s   dedo puesto, 72 BPM         -> Q=1, BPM 71..73
//  10-13 s   dedo retirado               -> Q=0
//  13-23 s   dedo puesto, 90 BPM         -> Q=1, BPM 89..91
//  23-25 s   sensor desconectado (NACK)  -> Q=0, LEDR[8] = 0
//  25-35 s   sensor reconectado, 90 BPM  -> se reconfigura solo, Q=1, BPM 89..91
// Además: configuración escrita (modo 0x03, SpO2 0x47, LEDs 0x77 y luego 0xBB
// al mover SW[7:5]), PART_ID leído = 0x11, LEDR[8] y SEQ continuo.

`timescale 1ns / 1ps

module tb_gate;

    parameter CLK_HZ = 345_600;
    parameter BAUD   = 115_200;
    parameter I2C_HZ = 28_800;
    parameter IS102  = 0;          // 1 = probar con el modelo del MAX30102

    localparam [7:0] PART = IS102 ? 8'h15 : 8'h11;
    localparam [7:0] SPO2 = IS102 ? 8'h67 : 8'h47;

    localparam BIT_CLKS = (CLK_HZ + BAUD / 2) / BAUD;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg  [1:0] key = 2'b10;
    reg  [9:0] sw  = 10'b00_0000_0000;   // sensor real, display normal
    wire [9:0] ledr;
    wire [7:0] hex0, hex1, hex2, hex3, hex4, hex5;
    wire [3:0] gpio;

    pullup (gpio[0]);
    pullup (gpio[1]);

    gate_top dut (
        .MAX10_CLK1_50 (clk), .KEY (key), .SW (sw), .LEDR (ledr),
        .HEX0 (hex0), .HEX1 (hex1), .HEX2 (hex2), .HEX3 (hex3), .HEX4 (hex4), .HEX5 (hex5),
        .GPIO (gpio)
    );

    max30100_model #(
        .SAMPLE_CLKS (CLK_HZ / 100 * 1005 / 1000),
        .IS102       (IS102)
    ) sensor (
        .clk (clk),
        .scl (gpio[0]),
        .sda (gpio[1])
    );

    wire tx = gpio[2];

    task uart_receive;
        output [7:0] data;
        integer n;
        begin
            @(negedge tx);
            repeat (BIT_CLKS / 2) @(posedge clk);
            for (n = 0; n < 8; n = n + 1) begin
                repeat (BIT_CLKS) @(posedge clk);
                data[n] = tx;
            end
            repeat (BIT_CLKS) @(posedge clk);
        end
    endtask

    reg [7:0] line [0:63];
    integer len;
    integer n_frames = 0;
    integer last_seq = -1;
    integer last_bpm = 0;
    integer last_q   = 0;
    integer errors   = 0;
    integer ffr;
    integer k;
    reg [7:0] c;
    reg [8*256-1:0] frames_file;

    function integer dec;
        input integer first;
        input integer count;
        integer j;
        begin
            dec = 0;
            for (j = 0; j < count; j = j + 1)
                dec = dec * 10 + (line[first + j] - "0");
        end
    endfunction

    initial begin
        if (!$value$plusargs("FRAMES_OUT=%s", frames_file)) frames_file = "max30100_frames.txt";
        ffr = $fopen(frames_file, "w");
        forever begin
            len = 0;
            c = 8'h00;
            while (c != 8'h0A) begin
                uart_receive(c);
                if (len < 64) line[len] = c;
                len = len + 1;
                $fwrite(ffr, "%c", c);
            end
            if (len != 36 || line[0] != "H" || line[1] != "B" || line[2] != "1") begin
                $display("ERROR: trama mal formada de %0d bytes", len);
                errors = errors + 1;
            end else begin
                if (dec(8, 6) != last_seq + 1) begin
                    $display("ERROR: SEQ %0d después de %0d", dec(8, 6), last_seq);
                    errors = errors + 1;
                end
                last_seq = dec(8, 6);
                last_bpm = dec(19, 3);
                last_q   = line[34] - "0";
                if (last_q == 0 && (last_bpm != 0 || dec(27, 4) != 0)) begin
                    $display("ERROR: trama Q=0 con BPM/IBI distinto de cero");
                    errors = errors + 1;
                end
            end
            n_frames = n_frames + 1;
        end
    end

    task wait_seconds;
        input integer s;
        begin
            repeat (s * CLK_HZ) @(posedge clk);
            repeat (60 * 10 * BIT_CLKS) @(posedge clk);
        end
    endtask

    task expect_frame;
        input integer q;
        input integer bpm_min;
        input integer bpm_max;
        input [8*40-1:0] what;
        begin
            if (last_q != q || (q == 1 && (last_bpm < bpm_min || last_bpm > bpm_max))) begin
                $display("FAIL %0s: SEQ=%0d BPM=%0d Q=%0d", what, last_seq, last_bpm, last_q);
                errors = errors + 1;
            end else
                $display("OK   %0s: SEQ=%0d BPM=%0d Q=%0d", what, last_seq, last_bpm, last_q);
        end
    endtask

    task check;
        input cond;
        input [8*48-1:0] what;
        begin
            if (cond)
                $display("OK   %0s", what);
            else begin
                $display("FAIL %0s", what);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        key[0] = 1'b1;

        wait_seconds(1);
        check(ledr[8] == 1'b1,              "LEDR[8] sensor configurado");
        check(sensor.mode_reg  == 8'h03,    "MODE = 0x03 (SpO2)");
        check(sensor.spo2_reg  == SPO2,     "SPO2_CONFIG (100 Hz)");
        check(sensor.led_reg   == 8'h77,    "corriente de LEDs 0x77 (24 mA)");
        check(!IS102 || sensor.led2_reg == 8'h77, "LED IR 0x0D = 0x77 (MAX30102)");
        check(!IS102 || sensor.fcfg_reg == 8'h00, "FIFO_CONFIG = 0x00 (MAX30102)");
        check(sensor.n_resets  == 1,        "un reset del sensor al arrancar");

        sw[8] = 1'b1;                       // display de depuración
        repeat (CLK_HZ / 20) @(posedge clk);
        check(hex5 == 8'hF9 && hex4 == (IS102 ? 8'h92 : 8'hF9), "HEX5..HEX4 muestran el PART_ID");
        check(hex3 != 8'hFF,                "HEX3..HEX0 muestran el IR crudo");
        sw[8] = 1'b0;

        sw[7:5] = 3'b101;                   // 37 mA
        repeat (CLK_HZ / 20) @(posedge clk);
        check(sensor.led_reg == 8'hBB && (!IS102 || sensor.led2_reg == 8'hBB),
                                            "LEDs = 0xBB al mover SW[7:5]");
        sw[7:5] = 3'b000;

        wait_seconds(9);
        expect_frame(1, 71, 73, "72 BPM sensor");

        sensor.finger = 1'b0;
        wait_seconds(3);
        expect_frame(0, 0, 0, "dedo retirado");

        $fclose(ffr);
        if (errors == 0) $display("PASS (compuertas): %0d tramas, %0d muestras", n_frames, sensor.n_samples);
        else             $display("FAIL (compuertas): %0d errores", errors);
        $finish;
        sensor.finger = 1'b1;
        sensor.bpm    = 90.0;
        wait_seconds(10);
        expect_frame(1, 89, 91, "90 BPM sensor");

        $fclose(ffr);
        if (errors == 0) $display("PASS (compuertas): %0d tramas, %0d muestras", n_frames, sensor.n_samples);
        else             $display("FAIL (compuertas): %0d errores", errors);
        $finish;
        sensor.connected = 1'b0;
        wait_seconds(2);
        expect_frame(0, 0, 0, "sensor desconectado");
        check(ledr[8] == 1'b0,              "LEDR[8] apagado sin sensor");

        sensor.connected = 1'b1;
        wait_seconds(10);
        expect_frame(1, 89, 91, "reconectado 90 BPM");
        check(ledr[8] == 1'b1,              "LEDR[8] encendido al reconectar");
        check(sensor.mode_reg == 8'h03,     "reconfigurado tras reconexion");

        $fclose(ffr);
        if (errors == 0)
            $display("PASS: %0d tramas, %0d muestras del sensor, SEQ continuo, sin errores",
                     n_frames, sensor.n_samples);
        else
            $display("FAIL: %0d errores en %0d tramas", errors, n_frames);
        $finish;
    end

endmodule
