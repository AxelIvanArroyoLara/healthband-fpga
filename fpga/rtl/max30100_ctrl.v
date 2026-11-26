// max30100_ctrl
// Controlador del sensor MAX30100 por I2C (dirección 7 bits 0x57).
// Entrega las muestras con la misma interfaz que ppg_synth, así que
// ppg_processor no cambia: ir_sample/red_sample + pulso sample_valid de un
// ciclo por muestra (100 muestras/s) + pulso fifo_overflow.
//
// Secuencia:
//   1. Espera BOOT_MS tras el reset y libera el bus (9 pulsos de SCL + STOP).
//   2. Configura el sensor:
//        0x06 <- 0x40       reset del MAX30100 (y espera 10 ms)
//        0xFF -> part_id    debe leerse 0x11 en un MAX30100
//        0x01 <- 0x00       sin interrupciones
//        0x02..0x04 <- 0    vacía el FIFO (WR_PTR, OVF_COUNTER, RD_PTR)
//        0x07 <- SPO2_CFG   0x47: alta resolución, 100 muestras/s, 1600 us (16 bits)
//        0x09 <- led_cfg    corriente de los LEDs {RED_PA, IR_PA}
//        0x06 <- MODE_CFG   0x03: modo SpO2 (IR + RED); empieza a muestrear
//   3. Ciclo: lee WR_PTR, OVF_COUNTER y RD_PTR (0x02..0x04). Si hay muestras
//      en el FIFO lee una (4 bytes de 0x05: IR alto, IR bajo, RED alto,
//      RED bajo) y genera sample_valid. Si OVF_COUNTER != 0 genera
//      fifo_overflow. Si led_cfg cambia, reescribe 0x09.
//   4. Si el sensor no responde (NACK), baja sensor_ok, sube i2c_error,
//      espera RETRY_MS y vuelve al paso 1. Así el sensor puede conectarse
//      o reconectarse con la placa encendida.
//
// El MAX30100 muestrea con su propio oscilador; al leer según los punteros del
// FIFO no se pierden ni se duplican muestras aunque los relojes difieran.

module max30100_ctrl #(
    parameter       CLK_HZ   = 50_000_000,
    parameter       I2C_HZ   = 100_000,
    parameter [7:0] SPO2_CFG = 8'h47,
    parameter [7:0] MODE_CFG = 8'h03,
    parameter       BOOT_MS  = 20,
    parameter       RESET_MS = 10,
    parameter       RETRY_MS = 100
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire  [7:0] led_cfg,
    output reg  [15:0] ir_sample,
    output reg  [15:0] red_sample,
    output reg         sample_valid,
    output reg         fifo_overflow,
    output reg         sensor_ok,     // configurado y respondiendo
    output reg         i2c_error,     // el último intento falló (NACK)
    output reg   [7:0] part_id,
    output wire        scl_oe,        // 1 = jalar SCL a 0
    output wire        sda_oe,        // 1 = jalar SDA a 0
    input  wire        sda_in
);

    localparam [6:0] ADDR = 7'h57;

    localparam [1:0] CMD_START = 2'd0,
                     CMD_WRITE = 2'd1,
                     CMD_READ  = 2'd2,
                     CMD_STOP  = 2'd3;

    localparam integer CYC_MS     = CLK_HZ / 1000;
    localparam integer BOOT_CYC   = BOOT_MS  * CYC_MS;
    localparam integer RESET_CYC  = RESET_MS * CYC_MS;
    localparam integer RETRY_CYC  = RETRY_MS * CYC_MS;
    localparam [3:0]   LAST_STEP  = 4'd8;

    // Estados principales y de transacción.
    localparam [4:0]
        S_BOOT        = 5'd0,
        S_RECOVER_RD  = 5'd1,
        S_RECOVER_SP  = 5'd2,
        S_CFG         = 5'd3,
        S_CFG_NEXT    = 5'd4,
        S_CFG_WAIT    = 5'd5,
        S_POLL        = 5'd6,
        S_POLL_EVAL   = 5'd7,
        S_SAMPLE      = 5'd8,
        S_ERROR       = 5'd9,
        T_START       = 5'd16,
        T_ADDRW       = 5'd17,
        T_REG         = 5'd18,
        T_WDATA       = 5'd19,
        T_RESTART     = 5'd20,
        T_ADDRR       = 5'd21,
        T_RDATA       = 5'd22,
        T_STOP        = 5'd23;

    // Maestro I2C.
    reg  [1:0] m_cmd;
    reg        m_go;
    reg  [7:0] m_wdata;
    reg        m_nack;
    wire       m_busy;
    wire       m_done;
    wire [7:0] m_rdata;
    wire       m_ack;

    i2c_master #(
        .CLK_HZ (CLK_HZ),
        .I2C_HZ (I2C_HZ)
    ) u_i2c (
        .clk     (clk),
        .reset_n (reset_n),
        .cmd     (m_cmd),
        .go      (m_go),
        .wdata   (m_wdata),
        .rd_nack (m_nack),
        .busy    (m_busy),
        .done    (m_done),
        .rdata   (m_rdata),
        .ack     (m_ack),
        .scl_oe  (scl_oe),
        .sda_oe  (sda_oe),
        .sda_in  (sda_in)
    );

    reg  [4:0] state;
    reg  [4:0] t_ret;      // a dónde volver al terminar la transacción
    reg        issued;     // ya se mandó el comando del estado actual
    reg [31:0] wait_cnt;
    reg  [3:0] step;
    reg        t_err;
    reg  [7:0] t_reg;
    reg  [7:0] t_wdata;
    reg        t_read;
    reg  [2:0] t_n;        // bytes a leer (1..4)
    reg  [2:0] t_i;
    reg  [7:0] rx0, rx1, rx2, rx3;
    reg  [7:0] led_w;      // último valor escrito en 0x09

    // Pasos de configuración: {lectura, registro, dato}.
    reg        cfg_read;
    reg  [7:0] cfg_reg;
    reg  [7:0] cfg_data;
    always @(*) begin
        cfg_read = 1'b0;
        case (step)
            4'd0:    begin cfg_reg = 8'h06; cfg_data = 8'h40;    end  // reset
            4'd1:    begin cfg_reg = 8'hFF; cfg_data = 8'h00; cfg_read = 1'b1; end
            4'd2:    begin cfg_reg = 8'h01; cfg_data = 8'h00;    end
            4'd3:    begin cfg_reg = 8'h02; cfg_data = 8'h00;    end
            4'd4:    begin cfg_reg = 8'h03; cfg_data = 8'h00;    end
            4'd5:    begin cfg_reg = 8'h04; cfg_data = 8'h00;    end
            4'd6:    begin cfg_reg = 8'h07; cfg_data = SPO2_CFG; end
            4'd7:    begin cfg_reg = 8'h09; cfg_data = led_cfg;  end
            default: begin cfg_reg = 8'h06; cfg_data = MODE_CFG; end
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= S_BOOT;
            t_ret         <= S_POLL;
            issued        <= 1'b0;
            wait_cnt      <= 0;
            step          <= 4'd0;
            t_err         <= 1'b0;
            t_reg         <= 8'd0;
            t_wdata       <= 8'd0;
            t_read        <= 1'b0;
            t_n           <= 3'd1;
            t_i           <= 3'd0;
            rx0           <= 8'd0;
            rx1           <= 8'd0;
            rx2           <= 8'd0;
            rx3           <= 8'd0;
            led_w         <= 8'd0;
            m_cmd         <= CMD_STOP;
            m_go          <= 1'b0;
            m_wdata       <= 8'd0;
            m_nack        <= 1'b0;
            ir_sample     <= 16'd0;
            red_sample    <= 16'd0;
            sample_valid  <= 1'b0;
            fifo_overflow <= 1'b0;
            sensor_ok     <= 1'b0;
            i2c_error     <= 1'b0;
            part_id       <= 8'd0;
        end else begin
            m_go          <= 1'b0;
            sample_valid  <= 1'b0;
            fifo_overflow <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                // Arranque y recuperación del bus
                S_BOOT: begin
                    if (wait_cnt >= BOOT_CYC - 1) begin
                        wait_cnt <= 0;
                        state    <= S_RECOVER_RD;
                    end else
                        wait_cnt <= wait_cnt + 1;
                end

                S_RECOVER_RD: begin           // 9 pulsos de SCL con SDA suelta
                    if (!issued) begin
                        m_cmd  <= CMD_READ;
                        m_nack <= 1'b1;
                        m_go   <= 1'b1;
                        issued <= 1'b1;
                    end else if (m_done) begin
                        issued <= 1'b0;
                        state  <= S_RECOVER_SP;
                    end
                end

                S_RECOVER_SP: begin
                    if (!issued) begin
                        m_cmd  <= CMD_STOP;
                        m_go   <= 1'b1;
                        issued <= 1'b1;
                    end else if (m_done) begin
                        issued <= 1'b0;
                        step   <= 4'd0;
                        state  <= S_CFG;
                    end
                end

                // ---------------------------------------------------------
                // Configuración
                S_CFG: begin
                    t_reg   <= cfg_reg;
                    t_wdata <= cfg_data;
                    t_read  <= cfg_read;
                    t_n     <= 3'd1;
                    t_ret   <= S_CFG_NEXT;
                    if (step == 4'd7)
                        led_w <= led_cfg;
                    state   <= T_START;
                end

                S_CFG_NEXT: begin
                    if (step == 4'd1)
                        part_id <= rx0;
                    if (step == LAST_STEP) begin
                        sensor_ok <= 1'b1;
                        i2c_error <= 1'b0;
                        state     <= S_POLL;
                    end else begin
                        step  <= step + 4'd1;
                        state <= (step == 4'd0) ? S_CFG_WAIT : S_CFG;
                    end
                end

                S_CFG_WAIT: begin             // el MAX30100 se está reiniciando
                    if (wait_cnt >= RESET_CYC - 1) begin
                        wait_cnt <= 0;
                        state    <= S_CFG;
                    end else
                        wait_cnt <= wait_cnt + 1;
                end

                // ---------------------------------------------------------
                // Lectura continua
                S_POLL: begin
                    t_n <= 3'd3;
                    if (led_cfg != led_w) begin
                        led_w   <= led_cfg;
                        t_reg   <= 8'h09;
                        t_wdata <= led_cfg;
                        t_read  <= 1'b0;
                        t_ret   <= S_POLL;
                    end else begin
                        t_reg   <= 8'h02;     // WR_PTR, OVF_COUNTER, RD_PTR
                        t_read  <= 1'b1;
                        t_ret   <= S_POLL_EVAL;
                    end
                    state <= T_START;
                end

                S_POLL_EVAL: begin
                    if (rx1 != 8'd0)
                        fifo_overflow <= 1'b1;
                    if (rx0[3:0] != rx2[3:0] || rx1 != 8'd0) begin
                        t_reg  <= 8'h05;      // FIFO_DATA
                        t_read <= 1'b1;
                        t_n    <= 3'd4;
                        t_ret  <= S_SAMPLE;
                        state  <= T_START;
                    end else
                        state <= S_POLL;
                end

                S_SAMPLE: begin
                    ir_sample    <= {rx0, rx1};
                    red_sample   <= {rx2, rx3};
                    sample_valid <= 1'b1;
                    state        <= S_POLL;
                end

                S_ERROR: begin
                    sensor_ok <= 1'b0;
                    i2c_error <= 1'b1;
                    if (wait_cnt >= RETRY_CYC - 1) begin
                        wait_cnt <= 0;
                        state    <= S_RECOVER_RD;
                    end else
                        wait_cnt <= wait_cnt + 1;
                end

                // ---------------------------------------------------------
                // Transacción: START, dirección+W, registro, y luego
                //   escritura: dato, STOP
                //   lectura:   START repetido, dirección+R, t_n bytes, STOP
                T_START: begin
                    if (!issued) begin
                        t_err  <= 1'b0;
                        m_cmd  <= CMD_START;
                        m_go   <= 1'b1;
                        issued <= 1'b1;
                    end else if (m_done) begin
                        issued <= 1'b0;
                        state  <= T_ADDRW;
                    end
                end

                T_ADDRW: begin
                    if (!issued) begin
                        m_cmd   <= CMD_WRITE;
                        m_wdata <= {ADDR, 1'b0};
                        m_go    <= 1'b1;
                        issued  <= 1'b1;
                    end else if (m_done) begin
                        issued <= 1'b0;
                        if (!m_ack) begin
                            t_err <= 1'b1;
                            state <= T_STOP;
                        end else
                            state <= T_REG;
                    end
                end

                T_REG: begin
                    if (!issued) begin
                        m_cmd   <= CMD_WRITE;
                        m_wdata <= t_reg;
                        m_go    <= 1'b1;
                        issued  <= 1'b1;
                    end else if (m_done) begin
                        issued <= 1'b0;
                        if (!m_ack) begin
                            t_err <= 1'b1;
                            state <= T_STOP;
                        end else
                            state <= t_read ? T_RESTART : T_WDATA;
                    end
                end

                T_WDATA: begin
                    if (!issued) begin
                        m_cmd   <= CMD_WRITE;
                        m_wdata <= t_wdata;
                        m_go    <= 1'b1;
                        issued  <= 1'b1;
                    end else if (m_done) begin
                        issued <= 1'b0;
                        if (!m_ack)
                            t_err <= 1'b1;
                        state <= T_STOP;
                    end
                end

                T_RESTART: begin
                    if (!issued) begin
                        m_cmd  <= CMD_START;
                        m_go   <= 1'b1;
                        issued <= 1'b1;
                    end else if (m_done) begin
                        issued <= 1'b0;
                        state  <= T_ADDRR;
                    end
                end

                T_ADDRR: begin
                    if (!issued) begin
                        m_cmd   <= CMD_WRITE;
                        m_wdata <= {ADDR, 1'b1};
                        m_go    <= 1'b1;
                        issued  <= 1'b1;
                    end else if (m_done) begin
                        issued <= 1'b0;
                        t_i    <= 3'd0;
                        if (!m_ack) begin
                            t_err <= 1'b1;
                            state <= T_STOP;
                        end else
                            state <= T_RDATA;
                    end
                end

                T_RDATA: begin
                    if (!issued) begin
                        m_cmd  <= CMD_READ;
                        m_nack <= (t_i == t_n - 3'd1);   // NACK en el último byte
                        m_go   <= 1'b1;
                        issued <= 1'b1;
                    end else if (m_done) begin
                        issued <= 1'b0;
                        case (t_i)
                            3'd0:    rx0 <= m_rdata;
                            3'd1:    rx1 <= m_rdata;
                            3'd2:    rx2 <= m_rdata;
                            default: rx3 <= m_rdata;
                        endcase
                        if (t_i == t_n - 3'd1)
                            state <= T_STOP;
                        else
                            t_i <= t_i + 3'd1;
                    end
                end

                T_STOP: begin
                    if (!issued) begin
                        m_cmd  <= CMD_STOP;
                        m_go   <= 1'b1;
                        issued <= 1'b1;
                    end else if (m_done) begin
                        issued   <= 1'b0;
                        wait_cnt <= 0;
                        state    <= t_err ? S_ERROR : t_ret;
                    end
                end

                default: state <= S_BOOT;
            endcase
        end
    end

endmodule
