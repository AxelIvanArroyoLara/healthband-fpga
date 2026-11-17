// bin_to_bcd
// Conversión combinacional de binario de 16 bits a 5 dígitos BCD
// (algoritmo double dabble: sumar 3 a cada dígito >= 5 antes de desplazar).
// bcd[3:0] son las unidades y bcd[19:16] las decenas de millar.

module bin_to_bcd (
    input  wire [15:0] bin,
    output wire [19:0] bcd
);

    function [19:0] double_dabble;
        input [15:0] value;
        reg   [35:0] z;
        integer      i;
        begin
            z = {20'd0, value};
            for (i = 0; i < 16; i = i + 1) begin
                if (z[19:16] > 4'd4) z[19:16] = z[19:16] + 4'd3;
                if (z[23:20] > 4'd4) z[23:20] = z[23:20] + 4'd3;
                if (z[27:24] > 4'd4) z[27:24] = z[27:24] + 4'd3;
                if (z[31:28] > 4'd4) z[31:28] = z[31:28] + 4'd3;
                if (z[35:32] > 4'd4) z[35:32] = z[35:32] + 4'd3;
                z = z << 1;
            end
            double_dabble = z[35:16];
        end
    endfunction

    assign bcd = double_dabble(bin);

endmodule
