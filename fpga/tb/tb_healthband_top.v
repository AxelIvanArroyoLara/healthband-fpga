// tb_healthband_top
// Prueba de sistema del top-level de la DE10-Lite con el generador sintético
// (SW[9] = 1):
// ppg_synth -> ppg_processor -> hb1_framer -> uart_tx -> pin GPIO[2].
// Decodifica las tramas UART del pin y comprueba lo mismo que verá el ESP32.
//
// Para que la simulación sea corta se usa CLK_HZ = 576 000 (divisor UART 5,
// 5760 ciclos por muestra). El tiempo simulado sigue siendo real en segundos
// de señal: 100 muestras y 1 trama por segundo.
//
// Escenario (SW como en la placa):
//   0-12 s   75 BPM           -> al final Q=1 y BPM 74..76
//  12-15 s   dedo retirado    -> Q=0 y BPM=000 en <= 2 tramas
//  15-27 s   75 BPM de nuevo  -> vuelve a Q=1 y BPM 74..76
//  27-37 s   120 BPM + ruido  -> Q=1 y BPM 118..122
//  37-40 s   saturación       -> Q=0
// Además verifica que SEQ aumente de 1 en 1 desde 000000.

`timescale 1ns / 1ps

module tb_healthband_top;

    parameter CLK_HZ = 576_000;
    parameter BAUD   = 115_200;

    localparam BIT_CLKS = (CLK_HZ + BAUD / 2) / BAUD;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg  [1:0] key = 2'b10;
    reg  [9:0] sw  = 10'b10_0000_0001;   // SW9=1 generador sintético, 75 BPM
    wire [9:0] ledr;
    wire [7:0] hex0, hex1, hex2, hex3, hex4, hex5;
    wire [3:0] gpio;

    pullup (gpio[0]);   // I2C del MAX30100 (sin sensor en esta prueba)
    pullup (gpio[1]);

    healthband_top #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) dut (
        .MAX10_CLK1_50 (clk),
        .KEY           (key),
        .SW            (sw),
        .LEDR          (ledr),
        .HEX0          (hex0),
        .HEX1          (hex1),
        .HEX2          (hex2),
        .HEX3          (hex3),
        .HEX4          (hex4),
        .HEX5          (hex5),
        .GPIO          (gpio)
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

    // Recepción continua de tramas.
    reg [7:0] line [0:63];
    integer len;
    integer n_frames = 0;
    integer last_seq = -1;
    integer last_bpm = 0;
    integer last_q   = 0;
    integer errors   = 0;
    integer ffr;
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
        if (!$value$plusargs("FRAMES_OUT=%s", frames_file)) frames_file = "top_frames.txt";
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

    // Espera a que termine la trama del segundo s (se envía al cumplirse cada segundo).
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

    initial begin
        repeat (10) @(posedge clk);
        key[0] = 1'b1;

        wait_seconds(12);
        expect_frame(1, 74, 76, "75 BPM estable");
        sw[3] = 1'b1;                       // dedo retirado
        wait_seconds(2);
        expect_frame(0, 0, 0, "dedo retirado");
        wait_seconds(1);
        sw[3] = 1'b0;
        wait_seconds(12);
        expect_frame(1, 74, 76, "recuperacion 75 BPM");
        sw[1:0] = 2'b11;                    // 120 BPM
        sw[2]   = 1'b1;                     // con ruido
        wait_seconds(10);
        expect_frame(1, 118, 122, "120 BPM con ruido");
        sw[4] = 1'b1;                       // saturación
        wait_seconds(2);
        expect_frame(0, 0, 0, "saturacion");

        $fclose(ffr);
        if (errors == 0)
            $display("PASS: %0d tramas, SEQ continuo, sin errores", n_frames);
        else
            $display("FAIL: %0d errores en %0d tramas", errors, n_frames);
        $finish;
    end

endmodule
