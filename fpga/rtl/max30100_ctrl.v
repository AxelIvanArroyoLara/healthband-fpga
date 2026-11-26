// max30100_ctrl
// Controlador del sensor de pulso por I2C (dirección 7 bits 0x57).
// Funciona con el MAX30100 y con el MAX30102/MAX30101, que muchas veces se
// venden en módulos idénticos: lee PART_ID (registro 0xFF) y elige el mapa de
// registros que corresponde (0x11 = MAX30100, 0x15 = MAX30102/MAX30101).
//
// Entrega las muestras con la misma interfaz que ppg_synth, así que
// ppg_processor no cambia: ir_sample/red_sample de 16 bits + pulso
// sample_valid de un ciclo por muestra (100 muestras/s) + pulso fifo_overflow.
//
// Secuencia:
//   1. Espera BOOT_MS tras el reset y libera el bus (9 pulsos de SCL + STOP).
//   2. Lee PART_ID y configura:
//                         MAX30100                MAX30102
//        reset            0x06 <- 0x40            0x09 <- 0x40   (y espera 10 ms)
//        interrupciones   0x01 <- 0x00            0x02 <- 0x00
//        vaciar FIFO      0x02..0x04 <- 0         0x04..0x06 <- 0
//        muestreo         0x07 <- 0x47            0x0A <- 0x67
//                         (alta res., 100 Hz,     (16384 nA, 100 Hz,
//                          1600 us, 16 bits)       411 us, 18 bits)
//        LEDs             0x09 <- led_cfg         0x0C, 0x0D <- led_cfg
//        FIFO             -                       0x08 <- 0x00 (sin promedio)
//        modo             0x06 <- 0x03 (SpO2)     0x09 <- 0x03 (SpO2)
//   3. Ciclo: lee WR_PTR, OVF_COUNTER y RD_PTR. Si hay muestras en el FIFO
//      lee una del registro FIFO_DATA y genera sample_valid:
//        MAX30100: 4 bytes, IR[15:0] y luego RED[15:0]
//        MAX30102: 6 bytes, RED[17:0] y luego IR[17:0] (se toman los 16 bits
//                  altos para que la escala sea parecida a la del MAX30100)
//      Si OVF_COUNTER != 0 genera fifo_overflow. Si led_cfg cambia (SW7..SW5)
//      reescribe la corriente de los LEDs.
//   4. Si el sensor no responde (NACK), baja sensor_ok, sube i2c_error,
//      espera RETRY_MS y vuelve al paso 1. Así el sensor puede conectarse
//      o reconectarse con la placa encendida.
//
// El sensor muestrea con su propio oscilador; al leer según los punteros del
// FIFO no se pierden ni se duplican muestras aunque los relojes difieran.

module max30100_ctrl #(
    parameter       CLK_HZ   = 50_000_000,
    parameter       I2C_HZ   = 100_000,
    parameter [7:0] SPO2_100 = 8'h47,   // MAX30100: 0x07
    parameter [7:0] SPO2_102 = 8'h67,   // MAX30102: 0x0A
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
    output reg         is_max30102,
    output wire        scl_oe,        // 1 = jalar SCL a 0
    output wire        sda_oe,        // 1 = jalar SDA a 0
    input  wire        sda_in
);

    localparam [6:0] ADDR = 7'h57;

    localparam [1:0] CMD_START = 2'd0,
                     CMD_WRITE = 2'd1,
                     CMD_READ  = 2'd2,
                     CMD_STOP  = 2'd3;

    localparam integer CYC_MS    = CLK_HZ / 1000;
    localparam integer BOOT_CYC  = BOOT_MS  * CYC_MS;
    localparam integer RESET_CYC = RESET_MS * CYC_MS;
    localparam integer RETRY_CYC = RETRY_MS * CYC_MS;

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
        S_LED2        = 5'd10,
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
    reg  [2:0] t_n;        // bytes a leer (1..6)
    reg  [2:0] t_i;
    reg  [7:0] rx0, rx1, rx2, rx3, rx4, rx5;
    reg  [7:0] led_w;      // último valor escrito en los registros de LEDs

    // Registros según el sensor.
    wire [7:0] reg_ptr  = is_max30102 ? 8'h04 : 8'h02;   // WR_PTR, OVF, RD_PTR
    wire [7:0] reg_fifo = is_max30102 ? 8'h07 : 8'h05;   // FIFO_DATA
    wire [2:0] n_fifo   = is_max30102 ? 3'd6  : 3'd4;    // bytes por muestra
    wire [7:0] reg_led  = is_max30102 ? 8'h0C : 8'h09;   // LED (RED en el 102)
    wire [3:0] last_step = is_max30102 ? 4'd10 : 4'd8;

    // Pasos de configuración: {lectura, registro, dato}.
    reg        cfg_read;
    reg  [7:0] cfg_reg;
    reg  [7:0] cfg_data;
    always @(*) begin
        cfg_read = 1'b0;
        cfg_reg  = 8'h00;
        cfg_data = 8'h00;
        case (step)
            4'd0: begin cfg_reg = 8'hFF; cfg_read = 1'b1; end                       // PART_ID
            4'd1: begin cfg_reg = is_max30102 ? 8'h09 : 8'h06; cfg_data = 8'h40; end // reset
            4'd2: cfg_reg = is_max30102 ? 8'h02 : 8'h01;                             // sin interrupciones
            4'd3: cfg_reg = is_max30102 ? 8'h04 : 8'h02;                             // WR_PTR
            4'd4: cfg_reg = is_max30102 ? 8'h05 : 8'h03;                             // OVF_COUNTER
            4'd5: cfg_reg = is_max30102 ? 8'h06 : 8'h04;                             // RD_PTR
            4'd6: begin cfg_reg = is_max30102 ? 8'h0A : 8'h07;
                        cfg_data = is_max30102 ? SPO2_102 : SPO2_100; end            // muestreo
            4'd7: begin cfg_reg = reg_led; cfg_data = led_cfg; end                   // LED
            4'd8: begin
                if (is_max30102) begin cfg_reg = 8'h0D; cfg_data = led_cfg; end      // LED IR (102)
                else             begin cfg_reg = 8'h06; cfg_data = 8'h03;   end      // modo SpO2 (100)
            end
            4'd9:    cfg_reg = 8'h08;                                                // FIFO_CONFIG (102)
            default: begin cfg_reg = 8'h09; cfg_data = 8'h03; end                    // modo SpO2 (102)
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
            rx4           <= 8'd0;
            rx5           <= 8'd0;
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
            is_max30102   <= 1'b0;
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
                    if (step == 4'd0) begin
                        part_id     <= rx0;
                        is_max30102 <= (rx0 == 8'h15);
                    end
                    if (step == last_step) begin
                        sensor_ok <= 1'b1;
                        i2c_error <= 1'b0;
                        state     <= S_POLL;
                    end else begin
                        step  <= step + 4'd1;
                        state <= (step == 4'd1) ? S_CFG_WAIT : S_CFG;
                    end
                end

                S_CFG_WAIT: begin             // el sensor se está reiniciando
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
                        t_reg   <= reg_led;
                        t_wdata <= led_cfg;
                        t_read  <= 1'b0;
                        t_ret   <= is_max30102 ? S_LED2 : S_POLL;
                    end else begin
                        t_reg   <= reg_ptr;   // WR_PTR, OVF_COUNTER, RD_PTR
                        t_read  <= 1'b1;
                        t_ret   <= S_POLL_EVAL;
                    end
                    state <= T_START;
                end

                S_LED2: begin                 // MAX30102: también el LED IR
                    t_reg   <= 8'h0D;
                    t_wdata <= led_w;
                    t_read  <= 1'b0;
                    t_ret   <= S_POLL;
                    state   <= T_START;
                end

                S_POLL_EVAL: begin
                    if (rx1 != 8'd0)
                        fifo_overflow <= 1'b1;
                    if (rx0[4:0] != rx2[4:0] || rx1 != 8'd0) begin
                        t_reg  <= reg_fifo;
                        t_read <= 1'b1;
                        t_n    <= n_fifo;
                        t_ret  <= S_SAMPLE;
                        state  <= T_START;
                    end else
                        state <= S_POLL;
                end

                S_SAMPLE: begin
                    if (is_max30102) begin
                        red_sample <= {rx0[1:0], rx1, rx2[7:2]};
                        ir_sample  <= {rx3[1:0], rx4, rx5[7:2]};
                    end else begin
                        ir_sample  <= {rx0, rx1};
                        red_sample <= {rx2, rx3};
                    end
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
                            3'd3:    rx3 <= m_rdata;
                            3'd4:    rx4 <= m_rdata;
                            default: rx5 <= m_rdata;
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
