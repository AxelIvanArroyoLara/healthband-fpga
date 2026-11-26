// i2c_scan_top
// Diseño de diagnóstico para la DE10-Lite: busca el MAX30100/MAX30102
// (dirección I2C 0x57) en TODOS los pares de pines del header JP1 y muestra
// en los displays en qué pines lo encontró.
//
// Para cada par (SCL, SDA) de los 36 GPIO hace START, manda 0xAE (0x57 +
// escritura), lee el ACK y hace STOP. Los pines solo se jalan a 0 (open
// drain) y nunca se manejan en alto, así que no hay riesgo de cortocircuito
// con lo que esté conectado. Una vuelta completa tarda ~0.5 s y se repite
// siempre, así que se pueden mover cables con la placa encendida.
//
// Displays (número de pin del JP1, contando desde el pin 1):
//   HEX5-HEX4  pin donde está SCL      HEX3-HEX2  pin donde está SDA
//   HEX1-HEX0  "--" mientras no lo encuentra
// LEDs:
//   LEDR9  sensor encontrado en la última vuelta
//   LEDR0  cambia en cada vuelta completa (latido del escáner)
//   LEDR1  el sensor encontrado también respondió leyendo PART_ID
// HEX1-HEX0 muestran el PART_ID leído (11 = MAX30100, 15 = MAX30102).
//
// Con SW0 arriba: HEX5-HEX4 y HEX3-HEX2 = los dos primeros pines del JP1 que
// leen 0 estando sueltos, HEX1-HEX0 = cuántos son. Un sensor conectado pero SIN
// alimentación jala SDA/SCL a 0 con sus pull-ups, así que aparece aquí.

module i2c_scan_top (
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
    inout  wire [35:0] GPIO
);

    wire clk = MAX10_CLK1_50;

    reg [1:0] rst_sync;
    always @(posedge clk or negedge KEY[0])
        if (!KEY[0]) rst_sync <= 2'b00;
        else         rst_sync <= {rst_sync[0], 1'b1};
    wire reset_n = rst_sync[1];

    // Maestro I2C compartido.
    localparam [1:0] CMD_START = 2'd0, CMD_WRITE = 2'd1, CMD_READ = 2'd2, CMD_STOP = 2'd3;
    reg  [1:0] m_cmd;
    reg        m_go;
    reg  [7:0] m_wdata;
    reg        m_nack;
    wire       m_busy, m_done, m_ack, scl_oe, sda_oe;
    wire [7:0] m_rdata;

    reg  [5:0] scl_idx, sda_idx;
    wire       sda_in = GPIO[sda_idx];

    i2c_master #(.CLK_HZ(50_000_000), .I2C_HZ(100_000)) u_i2c (
        .clk(clk), .reset_n(reset_n), .cmd(m_cmd), .go(m_go), .wdata(m_wdata),
        .rd_nack(m_nack), .busy(m_busy), .done(m_done), .rdata(m_rdata), .ack(m_ack),
        .scl_oe(scl_oe), .sda_oe(sda_oe), .sda_in(sda_in));

    genvar k;
    generate
        for (k = 0; k < 36; k = k + 1) begin : g_od
            assign GPIO[k] = ((scl_oe && scl_idx == k) || (sda_oe && sda_idx == k)) ? 1'b0 : 1'bz;
        end
    endgenerate

    // Secuencia de una prueba: [espera] START, 0xAE, (si ACK: 0xFF, START, 0xAF,
    // leer 1 byte con NACK) STOP.
    localparam [3:0] S_WAIT = 0, S_START = 1, S_ADDR = 2, S_REG = 3, S_RS = 4,
                     S_ADDRR = 5, S_READ = 6, S_STOP = 7, S_NEXT = 8;
    reg  [3:0]  st;
    reg         issued;
    reg  [15:0] wait_cnt;
    reg         acked, got_id;
    reg  [7:0]  id_rx;

    // Resultado de la vuelta en curso y de la última vuelta completa.
    reg         pass_found, shown_found, shown_id_ok, heartbeat;
    reg  [5:0]  pass_scl, pass_sda, shown_scl, shown_sda;
    reg  [7:0]  pass_id, shown_id;
    reg         pass_id_ok;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            st <= S_WAIT; issued <= 1'b0; wait_cnt <= 0;
            scl_idx <= 6'd0; sda_idx <= 6'd0;
            m_cmd <= CMD_STOP; m_go <= 1'b0; m_wdata <= 8'd0; m_nack <= 1'b0;
            acked <= 1'b0; got_id <= 1'b0; id_rx <= 8'd0;
            pass_found <= 1'b0; pass_scl <= 0; pass_sda <= 0; pass_id <= 0; pass_id_ok <= 1'b0;
            shown_found <= 1'b0; shown_scl <= 0; shown_sda <= 0; shown_id <= 0; shown_id_ok <= 1'b0;
            heartbeat <= 1'b0;
        end else begin
            m_go <= 1'b0;
            case (st)
                S_WAIT: begin                       // 200 us con el bus libre
                    if (scl_idx == sda_idx) begin
                        wait_cnt <= 0; st <= S_NEXT;   // mismo pin: no se prueba
                    end else if (wait_cnt == 16'd9999) begin
                        wait_cnt <= 0; st <= S_START;
                    end else
                        wait_cnt <= wait_cnt + 16'd1;
                end
                S_START, S_RS: begin
                    if (!issued) begin m_cmd <= CMD_START; m_go <= 1'b1; issued <= 1'b1; end
                    else if (m_done) begin issued <= 1'b0; st <= (st == S_START) ? S_ADDR : S_ADDRR; end
                end
                S_ADDR: begin
                    if (!issued) begin m_cmd <= CMD_WRITE; m_wdata <= 8'hAE; m_go <= 1'b1; issued <= 1'b1; end
                    else if (m_done) begin
                        issued <= 1'b0; acked <= m_ack; got_id <= 1'b0;
                        st <= m_ack ? S_REG : S_STOP;
                    end
                end
                S_REG: begin
                    if (!issued) begin m_cmd <= CMD_WRITE; m_wdata <= 8'hFF; m_go <= 1'b1; issued <= 1'b1; end
                    else if (m_done) begin issued <= 1'b0; st <= m_ack ? S_RS : S_STOP; end
                end
                S_ADDRR: begin
                    if (!issued) begin m_cmd <= CMD_WRITE; m_wdata <= 8'hAF; m_go <= 1'b1; issued <= 1'b1; end
                    else if (m_done) begin issued <= 1'b0; st <= m_ack ? S_READ : S_STOP; end
                end
                S_READ: begin
                    if (!issued) begin m_cmd <= CMD_READ; m_nack <= 1'b1; m_go <= 1'b1; issued <= 1'b1; end
                    else if (m_done) begin issued <= 1'b0; id_rx <= m_rdata; got_id <= 1'b1; st <= S_STOP; end
                end
                S_STOP: begin
                    if (!issued) begin m_cmd <= CMD_STOP; m_go <= 1'b1; issued <= 1'b1; end
                    else if (m_done) begin issued <= 1'b0; st <= S_NEXT; end
                end
                S_NEXT: begin
                    // Resultado de esta prueba (acked solo puede venir de un par válido).
                    if (acked && !pass_found) begin
                        pass_found <= 1'b1; pass_scl <= scl_idx; pass_sda <= sda_idx;
                        pass_id <= id_rx; pass_id_ok <= got_id;
                    end
                    acked <= 1'b0;
                    if (scl_idx == 6'd35 && sda_idx == 6'd35) begin
                        // Fin de vuelta (35,35 nunca se prueba): publicar y reiniciar.
                        shown_found <= pass_found;
                        shown_scl   <= pass_scl;
                        shown_sda   <= pass_sda;
                        shown_id    <= pass_id;
                        shown_id_ok <= pass_id_ok;
                        pass_found  <= 1'b0;
                        heartbeat   <= ~heartbeat;
                        scl_idx <= 6'd0;
                        sda_idx <= 6'd0;
                    end else if (sda_idx == 6'd35) begin
                        sda_idx <= 6'd0;
                        scl_idx <= scl_idx + 6'd1;
                    end else
                        sda_idx <= sda_idx + 6'd1;
                    st <= S_WAIT;
                end
                default: st <= S_WAIT;
            endcase
        end
    end

    // Número de pin del JP1 a partir del índice GPIO (11/12 y 29/30 son alimentación).
    function [5:0] jp1_pin;
        input [5:0] idx;
        jp1_pin = (idx <= 6'd9) ? idx + 6'd1 : (idx <= 6'd25) ? idx + 6'd3 : idx + 6'd5;
    endfunction

    function [7:0] seg;
        input [3:0] d;
        case (d)
            4'h0: seg = 8'hC0; 4'h1: seg = 8'hF9; 4'h2: seg = 8'hA4; 4'h3: seg = 8'hB0;
            4'h4: seg = 8'h99; 4'h5: seg = 8'h92; 4'h6: seg = 8'h82; 4'h7: seg = 8'hF8;
            4'h8: seg = 8'h80; 4'h9: seg = 8'h90; 4'hA: seg = 8'h88; 4'hB: seg = 8'h83;
            4'hC: seg = 8'hC6; 4'hD: seg = 8'hA1; 4'hE: seg = 8'h86; default: seg = 8'h8E;
        endcase
    endfunction

    // Pines del JP1 que leen 0 con todo suelto (solo hay pull-up débil de la FPGA):
    // indica un cable a GND o un sensor SIN alimentación (sus pull-ups quedan en 0 V).
    reg [35:0] gpio_m, gpio_s, low_mask;
    always @(posedge clk) begin
        gpio_m <= GPIO;
        gpio_s <= gpio_m;
        if (st == S_WAIT && wait_cnt == 16'd9000)   // bus suelto desde hace 180 us
            low_mask[sda_idx] <= ~gpio_s[sda_idx];
    end
    reg [5:0] low_a, low_b, low_n;
    reg       has_a, has_b;
    integer n;
    always @(*) begin
        has_a = 1'b0; has_b = 1'b0; low_a = 6'd0; low_b = 6'd0; low_n = 6'd0;
        for (n = 0; n < 36; n = n + 1)
            if (low_mask[n]) begin
                low_n = low_n + 6'd1;
                if (!has_a)      begin has_a = 1'b1; low_a = n; end
                else if (!has_b) begin has_b = 1'b1; low_b = n; end
            end
    end
    wire [5:0] p_la = jp1_pin(low_a);
    wire [5:0] p_lb = jp1_pin(low_b);
    wire       show_low = SW[0];

    localparam [7:0] DASH = 8'hBF;
    wire [5:0] p_scl = jp1_pin(shown_scl);
    wire [5:0] p_sda = jp1_pin(shown_sda);

    assign HEX5 = show_low ? (has_a ? seg(p_la / 10) : DASH) : shown_found ? seg(p_scl / 10) : DASH;
    assign HEX4 = show_low ? (has_a ? seg(p_la % 10) : DASH) : shown_found ? seg(p_scl % 10) : DASH;
    assign HEX3 = show_low ? (has_b ? seg(p_lb / 10) : DASH) : shown_found ? seg(p_sda / 10) : DASH;
    assign HEX2 = show_low ? (has_b ? seg(p_lb % 10) : DASH) : shown_found ? seg(p_sda % 10) : DASH;
    assign HEX1 = show_low ? seg(low_n / 10) : (shown_found && shown_id_ok) ? seg(shown_id[7:4]) : DASH;
    assign HEX0 = show_low ? seg(low_n % 10) : (shown_found && shown_id_ok) ? seg(shown_id[3:0]) : DASH;

    assign LEDR[0]   = heartbeat;
    assign LEDR[1]   = shown_found && shown_id_ok;
    assign LEDR[8:2] = 7'd0;
    assign LEDR[9]   = shown_found;

endmodule
