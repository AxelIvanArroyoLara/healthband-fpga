// tb_hb1_uart
// Verifica hb1_framer + uart_tx a 50 MHz y 115200 baudios reales.
// Un receptor UART de comportamiento reconstruye cada carácter (muestreando a
// mitad de bit y comprobando bits de inicio y parada) y compara cada trama con
// la esperada, calculada aquí de forma independiente del RTL.
//
// Envía N_FRAMES tramas con valores que cambian en cada una, incluidas tramas
// con Q=0 (BPM=000, IBI=0000) y un IBI mayor que 9999 (debe enviarse 9999).
// Para no simular 100 s, FRAME_HZ se sube a 250 tramas por segundo; cada trama
// tarda 3.1 ms, así que caben en el periodo de 4 ms.
//
// Salida: FRAMES_OUT (por defecto hb1_frames.txt) con el listado de tramas.

`timescale 1ns / 1ps

module tb_hb1_uart;

    parameter CLK_HZ   = 50_000_000;
    parameter BAUD     = 115_200;
    parameter FRAME_HZ = 250;
    parameter N_FRAMES = 100;

    localparam BIT_CLKS  = (CLK_HZ + BAUD / 2) / BAUD;
    localparam FRAME_LEN = 36;

    reg clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz

    reg         reset_n    = 1'b0;
    reg   [7:0] bpm        = 8'd0;
    reg  [15:0] ibi_ms     = 16'd0;
    reg         data_valid = 1'b0;

    wire  [7:0] tx_data;
    wire        tx_start;
    wire        tx_busy;
    wire        tx;

    hb1_framer #(.CLK_HZ(CLK_HZ), .FRAME_HZ(FRAME_HZ)) u_framer (
        .clk        (clk),
        .reset_n    (reset_n),
        .bpm        (bpm),
        .ibi_ms     (ibi_ms),
        .data_valid (data_valid),
        .tx_data    (tx_data),
        .tx_start   (tx_start),
        .tx_busy    (tx_busy)
    );

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk     (clk),
        .reset_n (reset_n),
        .data    (tx_data),
        .start   (tx_start),
        .busy    (tx_busy),
        .tx      (tx)
    );

    // Valores de prueba para la trama k.
    task set_inputs;
        input integer k;
        begin
            bpm        = 30 + (k * 37) % 211;          // 30..240
            ibi_ms     = 250 + (k * 97) % 2251;        // 250..2500
            data_valid = (k % 7 != 3);                 // algunas tramas con Q=0
            if (k == 50) ibi_ms = 16'd12000;           // debe saturar a 9999
        end
    endtask

    // Carácter esperado en la posición pos de la trama k.
    function [7:0] expected_char;
        input integer k;
        input integer pos;
        integer b, i, q, v;
        reg [8*36-1:0] tmpl;
        begin
            b = 30 + (k * 37) % 211;
            i = (k == 50) ? 9999 : 250 + (k * 97) % 2251;
            q = (k % 7 != 3);
            if (!q) begin b = 0; i = 0; end
            tmpl = "HB1,SEQ=______,BPM=___,IBI=____,Q=_";
            if (pos == 35)
                expected_char = 8'h0A;
            else if (pos >= 8 && pos <= 13) begin
                v = k;
                repeat (13 - pos) v = v / 10;
                expected_char = "0" + v % 10;
            end else if (pos >= 19 && pos <= 21) begin
                v = b;
                repeat (21 - pos) v = v / 10;
                expected_char = "0" + v % 10;
            end else if (pos >= 27 && pos <= 30) begin
                v = i;
                repeat (30 - pos) v = v / 10;
                expected_char = "0" + v % 10;
            end else if (pos == 34)
                expected_char = q ? "1" : "0";
            else
                expected_char = tmpl[8 * (35 - pos) - 1 -: 8];
        end
    endfunction

    // Receptor UART: espera el bit de inicio y muestrea a mitad de cada bit.
    task uart_receive;
        output [7:0] data;
        output       framing_ok;
        integer n;
        begin
            @(negedge tx);
            repeat (BIT_CLKS / 2) @(posedge clk);
            framing_ok = (tx == 1'b0);
            for (n = 0; n < 8; n = n + 1) begin
                repeat (BIT_CLKS) @(posedge clk);
                data[n] = tx;
            end
            repeat (BIT_CLKS) @(posedge clk);
            framing_ok = framing_ok && (tx == 1'b1);
        end
    endtask

    reg [8*256-1:0] frames_file;
    integer ffr;
    integer frame;
    integer pos;
    integer errors;
    integer frame_errors;
    reg [7:0] c;
    reg       ok;

    initial begin
        if (!$value$plusargs("FRAMES_OUT=%s", frames_file)) frames_file = "hb1_frames.txt";
        ffr    = $fopen(frames_file, "w");
        errors = 0;

        set_inputs(0);
        repeat (5) @(negedge clk);
        reset_n = 1'b1;

        for (frame = 0; frame < N_FRAMES; frame = frame + 1) begin
            frame_errors = 0;
            for (pos = 0; pos < FRAME_LEN; pos = pos + 1) begin
                uart_receive(c, ok);
                $fwrite(ffr, "%c", c);
                if (!ok) begin
                    $display("ERROR trama %0d pos %0d: bit de inicio/parada incorrecto", frame, pos);
                    frame_errors = frame_errors + 1;
                end
                if (c !== expected_char(frame, pos)) begin
                    $display("ERROR trama %0d pos %0d: recibido 0x%02h, esperado 0x%02h",
                             frame, pos, c, expected_char(frame, pos));
                    frame_errors = frame_errors + 1;
                end
            end
            // La siguiente instantánea ocurre en el próximo tick (~0.9 ms después).
            set_inputs(frame + 1);
            errors = errors + frame_errors;
        end

        $fclose(ffr);
        if (errors == 0)
            $display("PASS: %0d tramas HB1 recibidas sin caracteres incorrectos (%0d bytes)",
                     N_FRAMES, N_FRAMES * FRAME_LEN);
        else
            $display("FAIL: %0d errores en %0d tramas", errors, N_FRAMES);
        $finish;
    end

    // Límite de seguridad por si el DUT deja de transmitir.
    initial begin
        #((N_FRAMES + 2) * 1_000_000_000.0 / FRAME_HZ);
        $display("FAIL: tiempo agotado, el DUT dejó de transmitir");
        $finish;
    end

    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("tb_hb1_uart.vcd");
            $dumpvars(0, tb_hb1_uart);
        end
    end

endmodule
