// tb_ppg_processor
// Alimenta ppg_processor con un archivo de estímulo de fpga/stim (generado por
// fpga/model/gen_stimulus.py) y registra:
//   BEATS_OUT  latidos detectados: sample,interval (0 = primer latido sin intervalo)
//   HZ_OUT     salidas cada 100 muestras: t_s,bpm,ibi_ms,data_valid,quality
// Los CSV tienen el mismo formato que los del modelo de referencia y se
// comparan con fpga/model/compare_rtl.py.
//
// Para que la simulación sea rápida cada muestra dura CLKS_PER_SAMPLE ciclos
// en lugar de 500 000; el procesamiento cuenta muestras, no tiempo, y la
// detección de huecos se escala con GAP_CYCLES.
//
// Uso (Icarus):
//   vvp tb_ppg_processor.vvp +STIM=../stim/bpm075.hex
//       +BEATS_OUT=bpm075_beats.csv +HZ_OUT=bpm075_1hz.csv

`timescale 1ns / 1ps

module tb_ppg_processor;

    parameter CLKS_PER_SAMPLE = 64;
    parameter MAX_SAMPLES     = 4096;
    parameter SAMPLE_HZ       = 100;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg         reset_n       = 1'b0;
    reg  [15:0] ir_sample     = 16'd0;
    reg  [15:0] red_sample    = 16'd0;
    reg         sample_valid  = 1'b0;
    reg         fifo_overflow = 1'b0;

    wire  [7:0] bpm;
    wire [15:0] ibi_ms;
    wire        beat_valid;
    wire        data_valid;
    wire  [4:0] signal_quality;

    ppg_processor #(
        .GAP_CYCLES (CLKS_PER_SAMPLE * 3 / 2)
    ) dut (
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

    reg   [39:0] stim [0:MAX_SAMPLES-1];
    reg [8*256-1:0] stim_file;
    reg [8*256-1:0] beats_file;
    reg [8*256-1:0] hz_file;
    integer fbeats;
    integer fhz;
    integer slot;
    integer n_beats;
    integer n_valid_s;
    integer n_errors;

    // Registro de latidos; se muestrea en flanco de bajada para evitar carreras.
    always @(negedge clk) begin
        if (reset_n && beat_valid) begin
            $fwrite(fbeats, "%0d,%0d\n", slot,
                    dut.u_det.interval_ok ? dut.u_det.interval : 0);
            n_beats = n_beats + 1;
        end
    end

    // Comprobación continua: nunca un BPM válido fuera del rango del protocolo.
    always @(negedge clk) begin
        if (reset_n && data_valid && (bpm < 30 || bpm > 240 || ibi_ms < 250 || ibi_ms > 2500)) begin
            $display("ERROR t=%0t: data_valid con BPM=%0d IBI=%0d fuera de rango", $time, bpm, ibi_ms);
            n_errors = n_errors + 1;
        end
    end

    initial begin
        if (!$value$plusargs("STIM=%s", stim_file)) begin
            $display("Falta +STIM=<archivo.hex>");
            $finish;
        end
        if (!$value$plusargs("BEATS_OUT=%s", beats_file)) beats_file = "beats.csv";
        if (!$value$plusargs("HZ_OUT=%s", hz_file))       hz_file = "1hz.csv";

        $readmemh(stim_file, stim);
        fbeats = $fopen(beats_file, "w");
        fhz    = $fopen(hz_file, "w");
        $fwrite(fbeats, "sample,interval\n");
        $fwrite(fhz, "t_s,bpm,ibi_ms,data_valid,quality\n");

        slot      = 0;
        n_beats   = 0;
        n_valid_s = 0;
        n_errors  = 0;

        repeat (5) @(negedge clk);
        reset_n = 1'b1;

        while (slot < MAX_SAMPLES && stim[slot][39] !== 1'b1) begin
            if (stim[slot][32] !== 1'b1) begin          // bit 0 de flags: muestra perdida
                ir_sample    = stim[slot][15:0];
                red_sample   = stim[slot][31:16];
                sample_valid = 1'b1;
            end
            fifo_overflow = (stim[slot][33] === 1'b1);  // bit 1 de flags
            @(negedge clk);
            sample_valid  = 1'b0;
            fifo_overflow = 1'b0;
            repeat (CLKS_PER_SAMPLE - 1) @(negedge clk);

            if ((slot + 1) % SAMPLE_HZ == 0) begin
                $fwrite(fhz, "%0d,%0d,%0d,%0d,%0d\n", (slot + 1) / SAMPLE_HZ,
                        bpm, ibi_ms, data_valid, signal_quality);
                if (data_valid) n_valid_s = n_valid_s + 1;
            end
            slot = slot + 1;
        end

        $fclose(fbeats);
        $fclose(fhz);
        $display("%0s: %0d muestras, %0d latidos, %0d s con Q=1, %0d errores",
                 stim_file, slot, n_beats, n_valid_s, n_errors);
        $finish;
    end

    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("tb_ppg_processor.vcd");
            $dumpvars(0, tb_ppg_processor);
        end
    end

endmodule
