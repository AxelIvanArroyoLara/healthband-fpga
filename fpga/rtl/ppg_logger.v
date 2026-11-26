// ppg_logger
// Grabador de depuración: guarda una palabra de 32 bits por muestra (100/s) en
// una RAM de 4096 posiciones (~41 s) que se lee desde la PC por JTAG con el
// In-System Memory Content Editor de Quartus (instancia "PPG").
// Graba desde el reset (KEY0) hasta llenarse; para volver a grabar, KEY0.
//
// Palabra: [15:0]  ir_sample (fuente seleccionada)
//          [16]    hubo latido (beat_valid) desde la muestra anterior
//          [17]    data_valid
//          [22:18] signal_quality
//          [23]    fifo_overflow desde la muestra anterior
//          [31:24] bpm
// La dirección 4095 nunca se escribe con datos: al terminar guarda 0xA5A5_0FFF
// como marca de "grabación completa".

module ppg_logger (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        sample_valid,
    input  wire [15:0] ir_sample,
    input  wire        beat,
    input  wire        fifo_overflow,
    input  wire        data_valid,
    input  wire  [4:0] quality,
    input  wire  [7:0] bpm
);

    reg  [11:0] addr;
    reg         done;
    reg         beat_seen, ovf_seen;
    reg         we;
    reg  [31:0] wdata;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            addr <= 12'd0; done <= 1'b0; beat_seen <= 1'b0; ovf_seen <= 1'b0;
            we <= 1'b0; wdata <= 32'd0;
        end else begin
            we <= 1'b0;
            if (beat)          beat_seen <= 1'b1;
            if (fifo_overflow) ovf_seen  <= 1'b1;
            if (!done && sample_valid) begin
                we    <= 1'b1;
                if (addr == 12'd4095) begin
                    wdata <= 32'hA5A5_0FFF;
                    done  <= 1'b1;
                end else
                    wdata <= {bpm, ovf_seen | fifo_overflow, quality, data_valid,
                              beat_seen | beat, ir_sample};
                beat_seen <= 1'b0;
                ovf_seen  <= 1'b0;
            end
            if (we && !done)
                addr <= addr + 12'd1;
        end
    end

    wire [11:0] waddr = done ? 12'd4095 : addr;

`ifdef ALTERA_RESERVED_QIS
    altsyncram #(
        .operation_mode         ("SINGLE_PORT"),
        .width_a                (32),
        .widthad_a              (12),
        .numwords_a             (4096),
        .outdata_reg_a          ("UNREGISTERED"),
        .intended_device_family ("MAX 10"),
        .lpm_type               ("altsyncram"),
        .lpm_hint               ("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=PPG"),
        .power_up_uninitialized ("FALSE"),
        .read_during_write_mode_port_a ("NEW_DATA_NO_NBE_READ")
    ) u_ram (
        .clock0    (clk),
        .address_a (waddr),
        .data_a    (wdata),
        .wren_a    (we),
        .q_a       ()
    );
`endif

endmodule
