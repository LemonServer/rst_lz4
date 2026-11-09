`timescale 1ps / 1ps
`default_nettype none

package experimental_huffman_pkg;
    import rst_pkg::*;

    localparam int EXPERIMENTAL_FREE_DICT_ENTRIES = 2;
    localparam int EXPERIMENTAL_REUSE_CODE_START = 63;
    localparam int EXPERIMENTAL_REUSE_CODE_COUNT = 8;
    localparam int EXPERIMENTAL_CODE_MAX_LEN = 12;
    localparam int EXPERIMENTAL_DICT_MIN_CODE_LEN = 4;
    localparam int EXPERIMENTAL_DICT_MAX_CODE_LEN = 12;
    localparam int EXPERIMENTAL_CHUNK_MIN_CODE_LEN = 5;
    localparam int EXPERIMENTAL_CHUNK_MAX_CODE_LEN = 10;
    localparam int EXPERIMENTAL_DICT_BITS_MAX = DICT_STORAGE_BITS;
    localparam int EXPERIMENTAL_CHUNK_BITS_MAX = CHUNK_WIDTH * EXPERIMENTAL_CHUNK_MAX_CODE_LEN;
    localparam int EXPERIMENTAL_CHUNK_BIT_COUNT_W = $clog2(EXPERIMENTAL_CHUNK_BITS_MAX + 1);
    localparam int EXPERIMENTAL_DICT_MAX_DECODE_TOKENS =
        (EXPERIMENTAL_DICT_BITS_MAX + EXPERIMENTAL_DICT_MIN_CODE_LEN - 1)
        / EXPERIMENTAL_DICT_MIN_CODE_LEN;
    localparam int EXPERIMENTAL_CHUNK_MAX_DECODE_TOKENS =
        (EXPERIMENTAL_CHUNK_BITS_MAX + EXPERIMENTAL_CHUNK_MIN_CODE_LEN - 1)
        / EXPERIMENTAL_CHUNK_MIN_CODE_LEN;
    localparam int EXPERIMENTAL_DICT_RESOLVED_SYMBOLS_MAX = MAX_DICT_ENTRIES * MAX_SEQ_LEN;

    typedef struct packed {
        logic valid;
        logic [3:0] used;
        symbol_t sym;
    } huff_decode_t;

    typedef struct packed {
        logic valid;
        logic [3:0] used;
        logic [EXPERIMENTAL_CODE_MAX_LEN - 1:0] bits;
    } huff_code_t;

    function automatic symbol_t experimental_literal_sym(input int value);
        experimental_literal_sym = symbol_t'(value & 9'h0ff);
    endfunction

    function automatic symbol_t experimental_code_sym(input int idx);
        experimental_code_sym = symbol_t'(9'h100 | (idx & 9'h0ff));
    endfunction

    function automatic logic experimental_sym_is_code(input symbol_t sym);
        experimental_sym_is_code = sym[8];
    endfunction

    function automatic logic experimental_sym_is_reuse(input symbol_t sym);
        int code_idx;
        begin
            code_idx = sym[7:0];
            experimental_sym_is_reuse =
                experimental_sym_is_code(sym)
                && (code_idx >= EXPERIMENTAL_REUSE_CODE_START)
                && (code_idx < (EXPERIMENTAL_REUSE_CODE_START + EXPERIMENTAL_REUSE_CODE_COUNT));
        end
    endfunction

    function automatic int experimental_reuse_distance(input symbol_t sym);
        experimental_reuse_distance =
            int'(sym[7:0]) - EXPERIMENTAL_REUSE_CODE_START + 1;
    endfunction

    function automatic symbol_t experimental_reuse_symbol(input int distance);
        experimental_reuse_symbol = experimental_code_sym(
            EXPERIMENTAL_REUSE_CODE_START + distance - 1
        );
    endfunction

    function automatic huff_decode_t decode_dict_window(input logic [11:0] window);
        huff_decode_t result;
        begin
            result = '0;
            casez (window)
                12'b0000????????: begin
                    result.valid = 1'b1;
                    result.used = 4'd4;
                    result.sym = symbol_t'(9'd0);
                end
                12'b00010???????: begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.sym = symbol_t'(9'd256);
                end
                12'b00011???????: begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.sym = symbol_t'(9'd257);
                end
                12'b00100???????: begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.sym = symbol_t'(9'd258);
                end
                12'b00101???????: begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.sym = symbol_t'(9'd259);
                end
                12'b00110???????: begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.sym = symbol_t'(9'd260);
                end
                12'b00111???????: begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.sym = symbol_t'(9'd261);
                end
                12'b010000??????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd262);
                end
                12'b010001??????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd263);
                end
                12'b010010??????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd264);
                end
                12'b010011??????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd265);
                end
                12'b010100??????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd266);
                end
                12'b010101??????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd267);
                end
                12'b010110??????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd320);
                end
                12'b0101110?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd268);
                end
                12'b0101111?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd269);
                end
                12'b0110000?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd270);
                end
                12'b0110001?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd271);
                end
                12'b0110010?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd272);
                end
                12'b0110011?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd273);
                end
                12'b0110100?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd274);
                end
                12'b0110101?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd319);
                end
                12'b0110110?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd321);
                end
                12'b0110111?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd322);
                end
                12'b01110000????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd275);
                end
                12'b01110001????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd276);
                end
                12'b01110010????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd277);
                end
                12'b01110011????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd278);
                end
                12'b01110100????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd279);
                end
                12'b01110101????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd280);
                end
                12'b01110110????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd323);
                end
                12'b01110111????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd324);
                end
                12'b01111000????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd325);
                end
                12'b01111001????: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd326);
                end
                12'b011110100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd1);
                end
                12'b011110101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd2);
                end
                12'b011110110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd3);
                end
                12'b011110111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd4);
                end
                12'b011111000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd5);
                end
                12'b011111001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd6);
                end
                12'b011111010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd7);
                end
                12'b011111011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd8);
                end
                12'b011111100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd9);
                end
                12'b011111101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd10);
                end
                12'b011111110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd11);
                end
                12'b011111111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd12);
                end
                12'b100000000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd13);
                end
                12'b100000001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd14);
                end
                12'b100000010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd15);
                end
                12'b100000011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd16);
                end
                12'b100000100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd17);
                end
                12'b100000101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd18);
                end
                12'b100000110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd19);
                end
                12'b100000111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd20);
                end
                12'b100001000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd21);
                end
                12'b100001001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd22);
                end
                12'b100001010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd23);
                end
                12'b100001011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd24);
                end
                12'b100001100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd25);
                end
                12'b100001101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd26);
                end
                12'b100001110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd27);
                end
                12'b100001111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd28);
                end
                12'b100010000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd29);
                end
                12'b100010001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd30);
                end
                12'b100010010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd31);
                end
                12'b100010011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd32);
                end
                12'b100010100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd33);
                end
                12'b100010101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd34);
                end
                12'b100010110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd35);
                end
                12'b100010111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd36);
                end
                12'b100011000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd37);
                end
                12'b100011001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd38);
                end
                12'b100011010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd39);
                end
                12'b100011011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd40);
                end
                12'b100011100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd41);
                end
                12'b100011101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd42);
                end
                12'b100011110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd43);
                end
                12'b100011111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd44);
                end
                12'b100100000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd45);
                end
                12'b100100001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd46);
                end
                12'b100100010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd47);
                end
                12'b100100011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd48);
                end
                12'b100100100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd49);
                end
                12'b100100101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd50);
                end
                12'b100100110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd51);
                end
                12'b100100111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd52);
                end
                12'b100101000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd53);
                end
                12'b100101001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd54);
                end
                12'b100101010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd55);
                end
                12'b100101011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd56);
                end
                12'b100101100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd57);
                end
                12'b100101101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd58);
                end
                12'b100101110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd59);
                end
                12'b100101111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd60);
                end
                12'b100110000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd61);
                end
                12'b100110001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd62);
                end
                12'b100110010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd63);
                end
                12'b100110011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd64);
                end
                12'b100110100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd65);
                end
                12'b100110101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd66);
                end
                12'b100110110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd67);
                end
                12'b100110111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd68);
                end
                12'b100111000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd69);
                end
                12'b100111001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd70);
                end
                12'b100111010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd71);
                end
                12'b100111011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd72);
                end
                12'b100111100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd73);
                end
                12'b100111101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd74);
                end
                12'b100111110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd75);
                end
                12'b100111111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd76);
                end
                12'b101000000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd77);
                end
                12'b101000001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd78);
                end
                12'b101000010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd79);
                end
                12'b101000011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd80);
                end
                12'b101000100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd81);
                end
                12'b101000101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd82);
                end
                12'b101000110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd83);
                end
                12'b101000111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd84);
                end
                12'b101001000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd85);
                end
                12'b101001001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd86);
                end
                12'b101001010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd87);
                end
                12'b101001011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd88);
                end
                12'b101001100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd89);
                end
                12'b101001101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd90);
                end
                12'b101001110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd91);
                end
                12'b101001111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd92);
                end
                12'b101010000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd93);
                end
                12'b101010001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd94);
                end
                12'b101010010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd95);
                end
                12'b101010011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd96);
                end
                12'b101010100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd97);
                end
                12'b101010101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd98);
                end
                12'b101010110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd99);
                end
                12'b101010111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd100);
                end
                12'b101011000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd101);
                end
                12'b101011001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd102);
                end
                12'b101011010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd103);
                end
                12'b101011011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd104);
                end
                12'b101011100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd105);
                end
                12'b101011101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd106);
                end
                12'b101011110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd107);
                end
                12'b101011111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd108);
                end
                12'b101100000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd109);
                end
                12'b101100001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd110);
                end
                12'b101100010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd111);
                end
                12'b101100011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd112);
                end
                12'b101100100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd113);
                end
                12'b101100101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd114);
                end
                12'b101100110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd115);
                end
                12'b101100111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd116);
                end
                12'b101101000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd117);
                end
                12'b101101001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd118);
                end
                12'b101101010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd119);
                end
                12'b101101011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd120);
                end
                12'b101101100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd121);
                end
                12'b101101101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd122);
                end
                12'b101101110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd123);
                end
                12'b101101111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd124);
                end
                12'b101110000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd125);
                end
                12'b101110001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd126);
                end
                12'b101110010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd127);
                end
                12'b101110011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd128);
                end
                12'b101110100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd129);
                end
                12'b101110101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd130);
                end
                12'b101110110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd131);
                end
                12'b101110111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd132);
                end
                12'b101111000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd133);
                end
                12'b101111001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd134);
                end
                12'b101111010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd135);
                end
                12'b101111011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd136);
                end
                12'b101111100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd137);
                end
                12'b101111101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd138);
                end
                12'b101111110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd139);
                end
                12'b101111111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd140);
                end
                12'b110000000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd141);
                end
                12'b110000001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd142);
                end
                12'b110000010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd143);
                end
                12'b110000011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd144);
                end
                12'b110000100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd145);
                end
                12'b110000101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd146);
                end
                12'b110000110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd147);
                end
                12'b110000111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd148);
                end
                12'b110001000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd149);
                end
                12'b110001001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd150);
                end
                12'b110001010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd151);
                end
                12'b110001011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd152);
                end
                12'b110001100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd153);
                end
                12'b110001101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd154);
                end
                12'b110001110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd155);
                end
                12'b110001111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd156);
                end
                12'b110010000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd157);
                end
                12'b110010001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd158);
                end
                12'b110010010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd159);
                end
                12'b110010011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd160);
                end
                12'b110010100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd161);
                end
                12'b110010101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd162);
                end
                12'b110010110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd163);
                end
                12'b110010111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd164);
                end
                12'b110011000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd165);
                end
                12'b110011001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd166);
                end
                12'b110011010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd167);
                end
                12'b110011011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd168);
                end
                12'b110011100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd169);
                end
                12'b110011101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd170);
                end
                12'b110011110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd171);
                end
                12'b110011111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd172);
                end
                12'b110100000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd173);
                end
                12'b110100001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd174);
                end
                12'b110100010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd175);
                end
                12'b110100011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd176);
                end
                12'b110100100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd177);
                end
                12'b110100101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd178);
                end
                12'b110100110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd179);
                end
                12'b110100111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd180);
                end
                12'b110101000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd181);
                end
                12'b110101001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd182);
                end
                12'b110101010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd183);
                end
                12'b110101011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd184);
                end
                12'b110101100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd185);
                end
                12'b110101101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd186);
                end
                12'b110101110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd187);
                end
                12'b110101111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd188);
                end
                12'b110110000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd189);
                end
                12'b110110001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd190);
                end
                12'b110110010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd191);
                end
                12'b110110011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd192);
                end
                12'b110110100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd193);
                end
                12'b110110101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd194);
                end
                12'b110110110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd195);
                end
                12'b110110111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd196);
                end
                12'b110111000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd197);
                end
                12'b110111001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd198);
                end
                12'b110111010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd199);
                end
                12'b110111011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd200);
                end
                12'b110111100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd201);
                end
                12'b110111101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd202);
                end
                12'b110111110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd203);
                end
                12'b110111111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd204);
                end
                12'b111000000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd205);
                end
                12'b111000001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd206);
                end
                12'b111000010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd207);
                end
                12'b111000011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd208);
                end
                12'b111000100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd209);
                end
                12'b111000101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd210);
                end
                12'b111000110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd211);
                end
                12'b111000111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd212);
                end
                12'b111001000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd213);
                end
                12'b111001001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd214);
                end
                12'b111001010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd215);
                end
                12'b111001011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd216);
                end
                12'b111001100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd217);
                end
                12'b111001101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd218);
                end
                12'b111001110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd219);
                end
                12'b111001111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd220);
                end
                12'b111010000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd221);
                end
                12'b111010001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd222);
                end
                12'b111010010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd223);
                end
                12'b111010011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd224);
                end
                12'b111010100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd225);
                end
                12'b111010101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd226);
                end
                12'b111010110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd227);
                end
                12'b111010111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd228);
                end
                12'b111011000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd229);
                end
                12'b111011001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd230);
                end
                12'b111011010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd231);
                end
                12'b111011011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd232);
                end
                12'b111011100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd233);
                end
                12'b111011101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd234);
                end
                12'b111011110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd235);
                end
                12'b111011111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd236);
                end
                12'b111100000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd237);
                end
                12'b111100001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd238);
                end
                12'b111100010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd239);
                end
                12'b111100011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd240);
                end
                12'b111100100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd241);
                end
                12'b111100101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd242);
                end
                12'b111100110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd243);
                end
                12'b111100111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd244);
                end
                12'b111101000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd245);
                end
                12'b111101001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd246);
                end
                12'b111101010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd247);
                end
                12'b111101011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd248);
                end
                12'b111101100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd249);
                end
                12'b111101101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd250);
                end
                12'b111101110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd251);
                end
                12'b111101111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd252);
                end
                12'b111110000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd253);
                end
                12'b111110001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd254);
                end
                12'b111110010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd255);
                end
                12'b111110011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd281);
                end
                12'b111110100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd282);
                end
                12'b111110101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd283);
                end
                12'b111110110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd284);
                end
                12'b111110111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd285);
                end
                12'b111111000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd286);
                end
                12'b111111001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd287);
                end
                12'b1111110100??: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd288);
                end
                12'b1111110101??: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd289);
                end
                12'b1111110110??: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd290);
                end
                12'b1111110111??: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd291);
                end
                12'b11111110000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.sym = symbol_t'(9'd292);
                end
                12'b11111110001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.sym = symbol_t'(9'd293);
                end
                12'b11111110010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.sym = symbol_t'(9'd294);
                end
                12'b11111110011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.sym = symbol_t'(9'd295);
                end
                12'b11111110100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.sym = symbol_t'(9'd296);
                end
                12'b111111101010: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd297);
                end
                12'b111111101011: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd298);
                end
                12'b111111101100: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd299);
                end
                12'b111111101101: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd300);
                end
                12'b111111101110: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd301);
                end
                12'b111111101111: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd302);
                end
                12'b111111110000: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd303);
                end
                12'b111111110001: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd304);
                end
                12'b111111110010: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd305);
                end
                12'b111111110011: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd306);
                end
                12'b111111110100: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd307);
                end
                12'b111111110101: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd308);
                end
                12'b111111110110: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd309);
                end
                12'b111111110111: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd310);
                end
                12'b111111111000: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd311);
                end
                12'b111111111001: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd312);
                end
                12'b111111111010: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd313);
                end
                12'b111111111011: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd314);
                end
                12'b111111111100: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd315);
                end
                12'b111111111101: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd316);
                end
                12'b111111111110: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd317);
                end
                12'b111111111111: begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.sym = symbol_t'(9'd318);
                end
                default: begin
                end
            endcase
            decode_dict_window = result;
        end
    endfunction

    function automatic huff_decode_t decode_chunk_window(input logic [9:0] window);
        huff_decode_t result;
        begin
            result = '0;
            casez (window)
                10'b00000?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.sym = symbol_t'(9'd320);
                end
                10'b00001?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.sym = symbol_t'(9'd321);
                end
                10'b00010?????: begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.sym = symbol_t'(9'd322);
                end
                10'b000110????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd0);
                end
                10'b000111????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd261);
                end
                10'b001000????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd323);
                end
                10'b001001????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd324);
                end
                10'b001010????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd325);
                end
                10'b001011????: begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.sym = symbol_t'(9'd326);
                end
                10'b0011000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd256);
                end
                10'b0011001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd257);
                end
                10'b0011010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd258);
                end
                10'b0011011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd259);
                end
                10'b0011100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd260);
                end
                10'b0011101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd262);
                end
                10'b0011110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd263);
                end
                10'b0011111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd264);
                end
                10'b0100000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd265);
                end
                10'b0100001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd266);
                end
                10'b0100010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd267);
                end
                10'b0100011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd268);
                end
                10'b0100100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd269);
                end
                10'b0100101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd270);
                end
                10'b0100110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd271);
                end
                10'b0100111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd272);
                end
                10'b0101000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd273);
                end
                10'b0101001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd274);
                end
                10'b0101010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd275);
                end
                10'b0101011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd276);
                end
                10'b0101100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd277);
                end
                10'b0101101???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd278);
                end
                10'b0101110???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd279);
                end
                10'b0101111???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd280);
                end
                10'b0110000???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd281);
                end
                10'b0110001???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd282);
                end
                10'b0110010???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd283);
                end
                10'b0110011???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd284);
                end
                10'b0110100???: begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.sym = symbol_t'(9'd319);
                end
                10'b01101010??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd285);
                end
                10'b01101011??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd286);
                end
                10'b01101100??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd287);
                end
                10'b01101101??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd288);
                end
                10'b01101110??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd289);
                end
                10'b01101111??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd290);
                end
                10'b01110000??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd291);
                end
                10'b01110001??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd292);
                end
                10'b01110010??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd293);
                end
                10'b01110011??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd294);
                end
                10'b01110100??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd295);
                end
                10'b01110101??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd296);
                end
                10'b01110110??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd297);
                end
                10'b01110111??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd298);
                end
                10'b01111000??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd299);
                end
                10'b01111001??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd300);
                end
                10'b01111010??: begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.sym = symbol_t'(9'd301);
                end
                10'b011110110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd1);
                end
                10'b011110111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd2);
                end
                10'b011111000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd3);
                end
                10'b011111001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd4);
                end
                10'b011111010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd5);
                end
                10'b011111011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd6);
                end
                10'b011111100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd7);
                end
                10'b011111101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd8);
                end
                10'b011111110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd9);
                end
                10'b011111111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd10);
                end
                10'b100000000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd11);
                end
                10'b100000001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd12);
                end
                10'b100000010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd13);
                end
                10'b100000011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd14);
                end
                10'b100000100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd15);
                end
                10'b100000101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd16);
                end
                10'b100000110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd17);
                end
                10'b100000111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd18);
                end
                10'b100001000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd19);
                end
                10'b100001001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd20);
                end
                10'b100001010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd21);
                end
                10'b100001011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd22);
                end
                10'b100001100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd23);
                end
                10'b100001101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd24);
                end
                10'b100001110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd25);
                end
                10'b100001111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd26);
                end
                10'b100010000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd27);
                end
                10'b100010001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd28);
                end
                10'b100010010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd29);
                end
                10'b100010011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd30);
                end
                10'b100010100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd31);
                end
                10'b100010101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd32);
                end
                10'b100010110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd33);
                end
                10'b100010111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd34);
                end
                10'b100011000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd35);
                end
                10'b100011001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd36);
                end
                10'b100011010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd37);
                end
                10'b100011011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd38);
                end
                10'b100011100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd39);
                end
                10'b100011101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd40);
                end
                10'b100011110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd41);
                end
                10'b100011111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd42);
                end
                10'b100100000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd43);
                end
                10'b100100001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd44);
                end
                10'b100100010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd45);
                end
                10'b100100011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd46);
                end
                10'b100100100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd47);
                end
                10'b100100101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd48);
                end
                10'b100100110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd49);
                end
                10'b100100111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd50);
                end
                10'b100101000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd51);
                end
                10'b100101001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd52);
                end
                10'b100101010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd53);
                end
                10'b100101011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd54);
                end
                10'b100101100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd55);
                end
                10'b100101101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd56);
                end
                10'b100101110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd57);
                end
                10'b100101111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd58);
                end
                10'b100110000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd59);
                end
                10'b100110001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd60);
                end
                10'b100110010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd61);
                end
                10'b100110011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd62);
                end
                10'b100110100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd63);
                end
                10'b100110101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd64);
                end
                10'b100110110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd65);
                end
                10'b100110111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd66);
                end
                10'b100111000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd67);
                end
                10'b100111001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd68);
                end
                10'b100111010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd69);
                end
                10'b100111011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd70);
                end
                10'b100111100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd71);
                end
                10'b100111101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd72);
                end
                10'b100111110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd73);
                end
                10'b100111111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd74);
                end
                10'b101000000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd75);
                end
                10'b101000001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd76);
                end
                10'b101000010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd77);
                end
                10'b101000011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd78);
                end
                10'b101000100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd79);
                end
                10'b101000101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd80);
                end
                10'b101000110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd81);
                end
                10'b101000111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd82);
                end
                10'b101001000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd83);
                end
                10'b101001001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd84);
                end
                10'b101001010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd85);
                end
                10'b101001011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd86);
                end
                10'b101001100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd87);
                end
                10'b101001101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd88);
                end
                10'b101001110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd89);
                end
                10'b101001111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd90);
                end
                10'b101010000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd91);
                end
                10'b101010001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd92);
                end
                10'b101010010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd93);
                end
                10'b101010011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd94);
                end
                10'b101010100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd95);
                end
                10'b101010101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd96);
                end
                10'b101010110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd97);
                end
                10'b101010111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd98);
                end
                10'b101011000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd99);
                end
                10'b101011001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd100);
                end
                10'b101011010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd101);
                end
                10'b101011011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd102);
                end
                10'b101011100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd103);
                end
                10'b101011101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd104);
                end
                10'b101011110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd105);
                end
                10'b101011111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd106);
                end
                10'b101100000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd107);
                end
                10'b101100001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd108);
                end
                10'b101100010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd109);
                end
                10'b101100011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd110);
                end
                10'b101100100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd111);
                end
                10'b101100101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd112);
                end
                10'b101100110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd113);
                end
                10'b101100111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd114);
                end
                10'b101101000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd115);
                end
                10'b101101001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd116);
                end
                10'b101101010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd117);
                end
                10'b101101011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd118);
                end
                10'b101101100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd119);
                end
                10'b101101101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd120);
                end
                10'b101101110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd121);
                end
                10'b101101111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd122);
                end
                10'b101110000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd123);
                end
                10'b101110001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd124);
                end
                10'b101110010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd125);
                end
                10'b101110011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd126);
                end
                10'b101110100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd127);
                end
                10'b101110101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd128);
                end
                10'b101110110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd129);
                end
                10'b101110111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd130);
                end
                10'b101111000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd131);
                end
                10'b101111001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd132);
                end
                10'b101111010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd133);
                end
                10'b101111011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd134);
                end
                10'b101111100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd135);
                end
                10'b101111101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd136);
                end
                10'b101111110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd137);
                end
                10'b101111111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd138);
                end
                10'b110000000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd139);
                end
                10'b110000001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd140);
                end
                10'b110000010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd141);
                end
                10'b110000011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd142);
                end
                10'b110000100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd143);
                end
                10'b110000101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd144);
                end
                10'b110000110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd145);
                end
                10'b110000111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd146);
                end
                10'b110001000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd147);
                end
                10'b110001001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd148);
                end
                10'b110001010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd149);
                end
                10'b110001011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd150);
                end
                10'b110001100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd151);
                end
                10'b110001101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd152);
                end
                10'b110001110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd153);
                end
                10'b110001111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd154);
                end
                10'b110010000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd155);
                end
                10'b110010001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd156);
                end
                10'b110010010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd157);
                end
                10'b110010011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd158);
                end
                10'b110010100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd159);
                end
                10'b110010101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd160);
                end
                10'b110010110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd161);
                end
                10'b110010111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd162);
                end
                10'b110011000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd163);
                end
                10'b110011001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd164);
                end
                10'b110011010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd165);
                end
                10'b110011011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd166);
                end
                10'b110011100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd167);
                end
                10'b110011101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd168);
                end
                10'b110011110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd169);
                end
                10'b110011111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd170);
                end
                10'b110100000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd171);
                end
                10'b110100001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd172);
                end
                10'b110100010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd173);
                end
                10'b110100011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd174);
                end
                10'b110100100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd175);
                end
                10'b110100101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd176);
                end
                10'b110100110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd177);
                end
                10'b110100111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd178);
                end
                10'b110101000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd179);
                end
                10'b110101001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd180);
                end
                10'b110101010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd181);
                end
                10'b110101011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd182);
                end
                10'b110101100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd183);
                end
                10'b110101101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd184);
                end
                10'b110101110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd185);
                end
                10'b110101111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd186);
                end
                10'b110110000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd187);
                end
                10'b110110001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd188);
                end
                10'b110110010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd189);
                end
                10'b110110011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd190);
                end
                10'b110110100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd191);
                end
                10'b110110101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd192);
                end
                10'b110110110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd193);
                end
                10'b110110111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd194);
                end
                10'b110111000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd195);
                end
                10'b110111001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd196);
                end
                10'b110111010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd197);
                end
                10'b110111011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd198);
                end
                10'b110111100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd199);
                end
                10'b110111101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd200);
                end
                10'b110111110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd201);
                end
                10'b110111111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd202);
                end
                10'b111000000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd203);
                end
                10'b111000001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd204);
                end
                10'b111000010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd205);
                end
                10'b111000011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd206);
                end
                10'b111000100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd207);
                end
                10'b111000101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd208);
                end
                10'b111000110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd209);
                end
                10'b111000111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd210);
                end
                10'b111001000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd211);
                end
                10'b111001001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd212);
                end
                10'b111001010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd213);
                end
                10'b111001011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd214);
                end
                10'b111001100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd215);
                end
                10'b111001101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd216);
                end
                10'b111001110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd217);
                end
                10'b111001111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd218);
                end
                10'b111010000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd219);
                end
                10'b111010001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd220);
                end
                10'b111010010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd221);
                end
                10'b111010011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd222);
                end
                10'b111010100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd223);
                end
                10'b111010101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd224);
                end
                10'b111010110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd225);
                end
                10'b111010111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd226);
                end
                10'b111011000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd227);
                end
                10'b111011001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd228);
                end
                10'b111011010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd229);
                end
                10'b111011011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd230);
                end
                10'b111011100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd231);
                end
                10'b111011101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd232);
                end
                10'b111011110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd233);
                end
                10'b111011111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd234);
                end
                10'b111100000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd235);
                end
                10'b111100001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd236);
                end
                10'b111100010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd237);
                end
                10'b111100011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd238);
                end
                10'b111100100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd239);
                end
                10'b111100101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd240);
                end
                10'b111100110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd241);
                end
                10'b111100111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd242);
                end
                10'b111101000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd243);
                end
                10'b111101001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd244);
                end
                10'b111101010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd245);
                end
                10'b111101011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd246);
                end
                10'b111101100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd247);
                end
                10'b111101101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd248);
                end
                10'b111101110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd249);
                end
                10'b111101111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd250);
                end
                10'b111110000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd251);
                end
                10'b111110001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd252);
                end
                10'b111110010?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd253);
                end
                10'b111110011?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd254);
                end
                10'b111110100?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd255);
                end
                10'b111110101?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd302);
                end
                10'b111110110?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd303);
                end
                10'b111110111?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd304);
                end
                10'b111111000?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd305);
                end
                10'b111111001?: begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.sym = symbol_t'(9'd306);
                end
                10'b1111110100: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd307);
                end
                10'b1111110101: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd308);
                end
                10'b1111110110: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd309);
                end
                10'b1111110111: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd310);
                end
                10'b1111111000: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd311);
                end
                10'b1111111001: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd312);
                end
                10'b1111111010: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd313);
                end
                10'b1111111011: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd314);
                end
                10'b1111111100: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd315);
                end
                10'b1111111101: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd316);
                end
                10'b1111111110: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd317);
                end
                10'b1111111111: begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.sym = symbol_t'(9'd318);
                end
                default: begin
                end
            endcase
            decode_chunk_window = result;
        end
    endfunction

    function automatic huff_code_t encode_dict_symbol(input symbol_t sym);
        huff_code_t result;
        begin
            result = '0;
            case (sym)
                symbol_t'(9'd0): begin
                    result.valid = 1'b1;
                    result.used = 4'd4;
                    result.bits = 12'b0000;
                end
                symbol_t'(9'd1): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011110100;
                end
                symbol_t'(9'd2): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011110101;
                end
                symbol_t'(9'd3): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011110110;
                end
                symbol_t'(9'd4): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011110111;
                end
                symbol_t'(9'd5): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111000;
                end
                symbol_t'(9'd6): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111001;
                end
                symbol_t'(9'd7): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111010;
                end
                symbol_t'(9'd8): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111011;
                end
                symbol_t'(9'd9): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111100;
                end
                symbol_t'(9'd10): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111101;
                end
                symbol_t'(9'd11): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111110;
                end
                symbol_t'(9'd12): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111111;
                end
                symbol_t'(9'd13): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000000;
                end
                symbol_t'(9'd14): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000001;
                end
                symbol_t'(9'd15): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000010;
                end
                symbol_t'(9'd16): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000011;
                end
                symbol_t'(9'd17): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000100;
                end
                symbol_t'(9'd18): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000101;
                end
                symbol_t'(9'd19): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000110;
                end
                symbol_t'(9'd20): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000111;
                end
                symbol_t'(9'd21): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001000;
                end
                symbol_t'(9'd22): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001001;
                end
                symbol_t'(9'd23): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001010;
                end
                symbol_t'(9'd24): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001011;
                end
                symbol_t'(9'd25): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001100;
                end
                symbol_t'(9'd26): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001101;
                end
                symbol_t'(9'd27): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001110;
                end
                symbol_t'(9'd28): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001111;
                end
                symbol_t'(9'd29): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010000;
                end
                symbol_t'(9'd30): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010001;
                end
                symbol_t'(9'd31): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010010;
                end
                symbol_t'(9'd32): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010011;
                end
                symbol_t'(9'd33): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010100;
                end
                symbol_t'(9'd34): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010101;
                end
                symbol_t'(9'd35): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010110;
                end
                symbol_t'(9'd36): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010111;
                end
                symbol_t'(9'd37): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011000;
                end
                symbol_t'(9'd38): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011001;
                end
                symbol_t'(9'd39): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011010;
                end
                symbol_t'(9'd40): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011011;
                end
                symbol_t'(9'd41): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011100;
                end
                symbol_t'(9'd42): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011101;
                end
                symbol_t'(9'd43): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011110;
                end
                symbol_t'(9'd44): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011111;
                end
                symbol_t'(9'd45): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100000;
                end
                symbol_t'(9'd46): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100001;
                end
                symbol_t'(9'd47): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100010;
                end
                symbol_t'(9'd48): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100011;
                end
                symbol_t'(9'd49): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100100;
                end
                symbol_t'(9'd50): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100101;
                end
                symbol_t'(9'd51): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100110;
                end
                symbol_t'(9'd52): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100111;
                end
                symbol_t'(9'd53): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101000;
                end
                symbol_t'(9'd54): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101001;
                end
                symbol_t'(9'd55): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101010;
                end
                symbol_t'(9'd56): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101011;
                end
                symbol_t'(9'd57): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101100;
                end
                symbol_t'(9'd58): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101101;
                end
                symbol_t'(9'd59): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101110;
                end
                symbol_t'(9'd60): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101111;
                end
                symbol_t'(9'd61): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110000;
                end
                symbol_t'(9'd62): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110001;
                end
                symbol_t'(9'd63): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110010;
                end
                symbol_t'(9'd64): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110011;
                end
                symbol_t'(9'd65): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110100;
                end
                symbol_t'(9'd66): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110101;
                end
                symbol_t'(9'd67): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110110;
                end
                symbol_t'(9'd68): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110111;
                end
                symbol_t'(9'd69): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111000;
                end
                symbol_t'(9'd70): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111001;
                end
                symbol_t'(9'd71): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111010;
                end
                symbol_t'(9'd72): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111011;
                end
                symbol_t'(9'd73): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111100;
                end
                symbol_t'(9'd74): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111101;
                end
                symbol_t'(9'd75): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111110;
                end
                symbol_t'(9'd76): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111111;
                end
                symbol_t'(9'd77): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000000;
                end
                symbol_t'(9'd78): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000001;
                end
                symbol_t'(9'd79): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000010;
                end
                symbol_t'(9'd80): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000011;
                end
                symbol_t'(9'd81): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000100;
                end
                symbol_t'(9'd82): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000101;
                end
                symbol_t'(9'd83): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000110;
                end
                symbol_t'(9'd84): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000111;
                end
                symbol_t'(9'd85): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001000;
                end
                symbol_t'(9'd86): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001001;
                end
                symbol_t'(9'd87): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001010;
                end
                symbol_t'(9'd88): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001011;
                end
                symbol_t'(9'd89): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001100;
                end
                symbol_t'(9'd90): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001101;
                end
                symbol_t'(9'd91): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001110;
                end
                symbol_t'(9'd92): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001111;
                end
                symbol_t'(9'd93): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010000;
                end
                symbol_t'(9'd94): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010001;
                end
                symbol_t'(9'd95): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010010;
                end
                symbol_t'(9'd96): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010011;
                end
                symbol_t'(9'd97): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010100;
                end
                symbol_t'(9'd98): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010101;
                end
                symbol_t'(9'd99): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010110;
                end
                symbol_t'(9'd100): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010111;
                end
                symbol_t'(9'd101): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011000;
                end
                symbol_t'(9'd102): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011001;
                end
                symbol_t'(9'd103): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011010;
                end
                symbol_t'(9'd104): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011011;
                end
                symbol_t'(9'd105): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011100;
                end
                symbol_t'(9'd106): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011101;
                end
                symbol_t'(9'd107): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011110;
                end
                symbol_t'(9'd108): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011111;
                end
                symbol_t'(9'd109): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100000;
                end
                symbol_t'(9'd110): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100001;
                end
                symbol_t'(9'd111): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100010;
                end
                symbol_t'(9'd112): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100011;
                end
                symbol_t'(9'd113): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100100;
                end
                symbol_t'(9'd114): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100101;
                end
                symbol_t'(9'd115): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100110;
                end
                symbol_t'(9'd116): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100111;
                end
                symbol_t'(9'd117): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101000;
                end
                symbol_t'(9'd118): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101001;
                end
                symbol_t'(9'd119): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101010;
                end
                symbol_t'(9'd120): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101011;
                end
                symbol_t'(9'd121): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101100;
                end
                symbol_t'(9'd122): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101101;
                end
                symbol_t'(9'd123): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101110;
                end
                symbol_t'(9'd124): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101111;
                end
                symbol_t'(9'd125): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110000;
                end
                symbol_t'(9'd126): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110001;
                end
                symbol_t'(9'd127): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110010;
                end
                symbol_t'(9'd128): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110011;
                end
                symbol_t'(9'd129): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110100;
                end
                symbol_t'(9'd130): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110101;
                end
                symbol_t'(9'd131): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110110;
                end
                symbol_t'(9'd132): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110111;
                end
                symbol_t'(9'd133): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111000;
                end
                symbol_t'(9'd134): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111001;
                end
                symbol_t'(9'd135): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111010;
                end
                symbol_t'(9'd136): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111011;
                end
                symbol_t'(9'd137): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111100;
                end
                symbol_t'(9'd138): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111101;
                end
                symbol_t'(9'd139): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111110;
                end
                symbol_t'(9'd140): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111111;
                end
                symbol_t'(9'd141): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000000;
                end
                symbol_t'(9'd142): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000001;
                end
                symbol_t'(9'd143): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000010;
                end
                symbol_t'(9'd144): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000011;
                end
                symbol_t'(9'd145): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000100;
                end
                symbol_t'(9'd146): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000101;
                end
                symbol_t'(9'd147): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000110;
                end
                symbol_t'(9'd148): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000111;
                end
                symbol_t'(9'd149): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001000;
                end
                symbol_t'(9'd150): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001001;
                end
                symbol_t'(9'd151): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001010;
                end
                symbol_t'(9'd152): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001011;
                end
                symbol_t'(9'd153): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001100;
                end
                symbol_t'(9'd154): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001101;
                end
                symbol_t'(9'd155): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001110;
                end
                symbol_t'(9'd156): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001111;
                end
                symbol_t'(9'd157): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010000;
                end
                symbol_t'(9'd158): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010001;
                end
                symbol_t'(9'd159): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010010;
                end
                symbol_t'(9'd160): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010011;
                end
                symbol_t'(9'd161): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010100;
                end
                symbol_t'(9'd162): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010101;
                end
                symbol_t'(9'd163): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010110;
                end
                symbol_t'(9'd164): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010111;
                end
                symbol_t'(9'd165): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011000;
                end
                symbol_t'(9'd166): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011001;
                end
                symbol_t'(9'd167): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011010;
                end
                symbol_t'(9'd168): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011011;
                end
                symbol_t'(9'd169): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011100;
                end
                symbol_t'(9'd170): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011101;
                end
                symbol_t'(9'd171): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011110;
                end
                symbol_t'(9'd172): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011111;
                end
                symbol_t'(9'd173): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100000;
                end
                symbol_t'(9'd174): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100001;
                end
                symbol_t'(9'd175): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100010;
                end
                symbol_t'(9'd176): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100011;
                end
                symbol_t'(9'd177): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100100;
                end
                symbol_t'(9'd178): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100101;
                end
                symbol_t'(9'd179): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100110;
                end
                symbol_t'(9'd180): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100111;
                end
                symbol_t'(9'd181): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101000;
                end
                symbol_t'(9'd182): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101001;
                end
                symbol_t'(9'd183): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101010;
                end
                symbol_t'(9'd184): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101011;
                end
                symbol_t'(9'd185): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101100;
                end
                symbol_t'(9'd186): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101101;
                end
                symbol_t'(9'd187): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101110;
                end
                symbol_t'(9'd188): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101111;
                end
                symbol_t'(9'd189): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110000;
                end
                symbol_t'(9'd190): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110001;
                end
                symbol_t'(9'd191): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110010;
                end
                symbol_t'(9'd192): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110011;
                end
                symbol_t'(9'd193): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110100;
                end
                symbol_t'(9'd194): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110101;
                end
                symbol_t'(9'd195): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110110;
                end
                symbol_t'(9'd196): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110111;
                end
                symbol_t'(9'd197): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111000;
                end
                symbol_t'(9'd198): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111001;
                end
                symbol_t'(9'd199): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111010;
                end
                symbol_t'(9'd200): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111011;
                end
                symbol_t'(9'd201): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111100;
                end
                symbol_t'(9'd202): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111101;
                end
                symbol_t'(9'd203): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111110;
                end
                symbol_t'(9'd204): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111111;
                end
                symbol_t'(9'd205): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000000;
                end
                symbol_t'(9'd206): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000001;
                end
                symbol_t'(9'd207): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000010;
                end
                symbol_t'(9'd208): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000011;
                end
                symbol_t'(9'd209): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000100;
                end
                symbol_t'(9'd210): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000101;
                end
                symbol_t'(9'd211): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000110;
                end
                symbol_t'(9'd212): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000111;
                end
                symbol_t'(9'd213): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001000;
                end
                symbol_t'(9'd214): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001001;
                end
                symbol_t'(9'd215): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001010;
                end
                symbol_t'(9'd216): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001011;
                end
                symbol_t'(9'd217): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001100;
                end
                symbol_t'(9'd218): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001101;
                end
                symbol_t'(9'd219): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001110;
                end
                symbol_t'(9'd220): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001111;
                end
                symbol_t'(9'd221): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010000;
                end
                symbol_t'(9'd222): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010001;
                end
                symbol_t'(9'd223): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010010;
                end
                symbol_t'(9'd224): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010011;
                end
                symbol_t'(9'd225): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010100;
                end
                symbol_t'(9'd226): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010101;
                end
                symbol_t'(9'd227): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010110;
                end
                symbol_t'(9'd228): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010111;
                end
                symbol_t'(9'd229): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011000;
                end
                symbol_t'(9'd230): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011001;
                end
                symbol_t'(9'd231): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011010;
                end
                symbol_t'(9'd232): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011011;
                end
                symbol_t'(9'd233): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011100;
                end
                symbol_t'(9'd234): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011101;
                end
                symbol_t'(9'd235): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011110;
                end
                symbol_t'(9'd236): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011111;
                end
                symbol_t'(9'd237): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100000;
                end
                symbol_t'(9'd238): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100001;
                end
                symbol_t'(9'd239): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100010;
                end
                symbol_t'(9'd240): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100011;
                end
                symbol_t'(9'd241): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100100;
                end
                symbol_t'(9'd242): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100101;
                end
                symbol_t'(9'd243): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100110;
                end
                symbol_t'(9'd244): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100111;
                end
                symbol_t'(9'd245): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101000;
                end
                symbol_t'(9'd246): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101001;
                end
                symbol_t'(9'd247): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101010;
                end
                symbol_t'(9'd248): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101011;
                end
                symbol_t'(9'd249): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101100;
                end
                symbol_t'(9'd250): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101101;
                end
                symbol_t'(9'd251): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101110;
                end
                symbol_t'(9'd252): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101111;
                end
                symbol_t'(9'd253): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110000;
                end
                symbol_t'(9'd254): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110001;
                end
                symbol_t'(9'd255): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110010;
                end
                symbol_t'(9'd256): begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.bits = 12'b00010;
                end
                symbol_t'(9'd257): begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.bits = 12'b00011;
                end
                symbol_t'(9'd258): begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.bits = 12'b00100;
                end
                symbol_t'(9'd259): begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.bits = 12'b00101;
                end
                symbol_t'(9'd260): begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.bits = 12'b00110;
                end
                symbol_t'(9'd261): begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.bits = 12'b00111;
                end
                symbol_t'(9'd262): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b010000;
                end
                symbol_t'(9'd263): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b010001;
                end
                symbol_t'(9'd264): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b010010;
                end
                symbol_t'(9'd265): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b010011;
                end
                symbol_t'(9'd266): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b010100;
                end
                symbol_t'(9'd267): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b010101;
                end
                symbol_t'(9'd268): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101110;
                end
                symbol_t'(9'd269): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101111;
                end
                symbol_t'(9'd270): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110000;
                end
                symbol_t'(9'd271): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110001;
                end
                symbol_t'(9'd272): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110010;
                end
                symbol_t'(9'd273): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110011;
                end
                symbol_t'(9'd274): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110100;
                end
                symbol_t'(9'd275): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110000;
                end
                symbol_t'(9'd276): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110001;
                end
                symbol_t'(9'd277): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110010;
                end
                symbol_t'(9'd278): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110011;
                end
                symbol_t'(9'd279): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110100;
                end
                symbol_t'(9'd280): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110101;
                end
                symbol_t'(9'd281): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110011;
                end
                symbol_t'(9'd282): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110100;
                end
                symbol_t'(9'd283): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110101;
                end
                symbol_t'(9'd284): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110110;
                end
                symbol_t'(9'd285): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110111;
                end
                symbol_t'(9'd286): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111111000;
                end
                symbol_t'(9'd287): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111111001;
                end
                symbol_t'(9'd288): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111110100;
                end
                symbol_t'(9'd289): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111110101;
                end
                symbol_t'(9'd290): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111110110;
                end
                symbol_t'(9'd291): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111110111;
                end
                symbol_t'(9'd292): begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.bits = 12'b11111110000;
                end
                symbol_t'(9'd293): begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.bits = 12'b11111110001;
                end
                symbol_t'(9'd294): begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.bits = 12'b11111110010;
                end
                symbol_t'(9'd295): begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.bits = 12'b11111110011;
                end
                symbol_t'(9'd296): begin
                    result.valid = 1'b1;
                    result.used = 4'd11;
                    result.bits = 12'b11111110100;
                end
                symbol_t'(9'd297): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111101010;
                end
                symbol_t'(9'd298): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111101011;
                end
                symbol_t'(9'd299): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111101100;
                end
                symbol_t'(9'd300): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111101101;
                end
                symbol_t'(9'd301): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111101110;
                end
                symbol_t'(9'd302): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111101111;
                end
                symbol_t'(9'd303): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111110000;
                end
                symbol_t'(9'd304): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111110001;
                end
                symbol_t'(9'd305): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111110010;
                end
                symbol_t'(9'd306): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111110011;
                end
                symbol_t'(9'd307): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111110100;
                end
                symbol_t'(9'd308): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111110101;
                end
                symbol_t'(9'd309): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111110110;
                end
                symbol_t'(9'd310): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111110111;
                end
                symbol_t'(9'd311): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111111000;
                end
                symbol_t'(9'd312): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111111001;
                end
                symbol_t'(9'd313): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111111010;
                end
                symbol_t'(9'd314): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111111011;
                end
                symbol_t'(9'd315): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111111100;
                end
                symbol_t'(9'd316): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111111101;
                end
                symbol_t'(9'd317): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111111110;
                end
                symbol_t'(9'd318): begin
                    result.valid = 1'b1;
                    result.used = 4'd12;
                    result.bits = 12'b111111111111;
                end
                symbol_t'(9'd319): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110101;
                end
                symbol_t'(9'd320): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b010110;
                end
                symbol_t'(9'd321): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110110;
                end
                symbol_t'(9'd322): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110111;
                end
                symbol_t'(9'd323): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110110;
                end
                symbol_t'(9'd324): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110111;
                end
                symbol_t'(9'd325): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01111000;
                end
                symbol_t'(9'd326): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01111001;
                end
                default: begin
                end
            endcase
            encode_dict_symbol = result;
        end
    endfunction

    function automatic huff_code_t encode_chunk_symbol(input symbol_t sym);
        huff_code_t result;
        begin
            result = '0;
            case (sym)
                symbol_t'(9'd0): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b000110;
                end
                symbol_t'(9'd1): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011110110;
                end
                symbol_t'(9'd2): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011110111;
                end
                symbol_t'(9'd3): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111000;
                end
                symbol_t'(9'd4): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111001;
                end
                symbol_t'(9'd5): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111010;
                end
                symbol_t'(9'd6): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111011;
                end
                symbol_t'(9'd7): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111100;
                end
                symbol_t'(9'd8): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111101;
                end
                symbol_t'(9'd9): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111110;
                end
                symbol_t'(9'd10): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b011111111;
                end
                symbol_t'(9'd11): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000000;
                end
                symbol_t'(9'd12): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000001;
                end
                symbol_t'(9'd13): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000010;
                end
                symbol_t'(9'd14): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000011;
                end
                symbol_t'(9'd15): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000100;
                end
                symbol_t'(9'd16): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000101;
                end
                symbol_t'(9'd17): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000110;
                end
                symbol_t'(9'd18): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100000111;
                end
                symbol_t'(9'd19): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001000;
                end
                symbol_t'(9'd20): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001001;
                end
                symbol_t'(9'd21): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001010;
                end
                symbol_t'(9'd22): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001011;
                end
                symbol_t'(9'd23): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001100;
                end
                symbol_t'(9'd24): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001101;
                end
                symbol_t'(9'd25): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001110;
                end
                symbol_t'(9'd26): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100001111;
                end
                symbol_t'(9'd27): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010000;
                end
                symbol_t'(9'd28): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010001;
                end
                symbol_t'(9'd29): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010010;
                end
                symbol_t'(9'd30): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010011;
                end
                symbol_t'(9'd31): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010100;
                end
                symbol_t'(9'd32): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010101;
                end
                symbol_t'(9'd33): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010110;
                end
                symbol_t'(9'd34): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100010111;
                end
                symbol_t'(9'd35): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011000;
                end
                symbol_t'(9'd36): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011001;
                end
                symbol_t'(9'd37): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011010;
                end
                symbol_t'(9'd38): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011011;
                end
                symbol_t'(9'd39): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011100;
                end
                symbol_t'(9'd40): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011101;
                end
                symbol_t'(9'd41): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011110;
                end
                symbol_t'(9'd42): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100011111;
                end
                symbol_t'(9'd43): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100000;
                end
                symbol_t'(9'd44): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100001;
                end
                symbol_t'(9'd45): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100010;
                end
                symbol_t'(9'd46): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100011;
                end
                symbol_t'(9'd47): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100100;
                end
                symbol_t'(9'd48): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100101;
                end
                symbol_t'(9'd49): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100110;
                end
                symbol_t'(9'd50): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100100111;
                end
                symbol_t'(9'd51): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101000;
                end
                symbol_t'(9'd52): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101001;
                end
                symbol_t'(9'd53): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101010;
                end
                symbol_t'(9'd54): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101011;
                end
                symbol_t'(9'd55): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101100;
                end
                symbol_t'(9'd56): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101101;
                end
                symbol_t'(9'd57): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101110;
                end
                symbol_t'(9'd58): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100101111;
                end
                symbol_t'(9'd59): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110000;
                end
                symbol_t'(9'd60): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110001;
                end
                symbol_t'(9'd61): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110010;
                end
                symbol_t'(9'd62): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110011;
                end
                symbol_t'(9'd63): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110100;
                end
                symbol_t'(9'd64): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110101;
                end
                symbol_t'(9'd65): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110110;
                end
                symbol_t'(9'd66): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100110111;
                end
                symbol_t'(9'd67): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111000;
                end
                symbol_t'(9'd68): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111001;
                end
                symbol_t'(9'd69): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111010;
                end
                symbol_t'(9'd70): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111011;
                end
                symbol_t'(9'd71): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111100;
                end
                symbol_t'(9'd72): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111101;
                end
                symbol_t'(9'd73): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111110;
                end
                symbol_t'(9'd74): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b100111111;
                end
                symbol_t'(9'd75): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000000;
                end
                symbol_t'(9'd76): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000001;
                end
                symbol_t'(9'd77): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000010;
                end
                symbol_t'(9'd78): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000011;
                end
                symbol_t'(9'd79): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000100;
                end
                symbol_t'(9'd80): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000101;
                end
                symbol_t'(9'd81): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000110;
                end
                symbol_t'(9'd82): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101000111;
                end
                symbol_t'(9'd83): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001000;
                end
                symbol_t'(9'd84): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001001;
                end
                symbol_t'(9'd85): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001010;
                end
                symbol_t'(9'd86): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001011;
                end
                symbol_t'(9'd87): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001100;
                end
                symbol_t'(9'd88): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001101;
                end
                symbol_t'(9'd89): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001110;
                end
                symbol_t'(9'd90): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101001111;
                end
                symbol_t'(9'd91): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010000;
                end
                symbol_t'(9'd92): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010001;
                end
                symbol_t'(9'd93): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010010;
                end
                symbol_t'(9'd94): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010011;
                end
                symbol_t'(9'd95): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010100;
                end
                symbol_t'(9'd96): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010101;
                end
                symbol_t'(9'd97): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010110;
                end
                symbol_t'(9'd98): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101010111;
                end
                symbol_t'(9'd99): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011000;
                end
                symbol_t'(9'd100): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011001;
                end
                symbol_t'(9'd101): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011010;
                end
                symbol_t'(9'd102): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011011;
                end
                symbol_t'(9'd103): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011100;
                end
                symbol_t'(9'd104): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011101;
                end
                symbol_t'(9'd105): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011110;
                end
                symbol_t'(9'd106): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101011111;
                end
                symbol_t'(9'd107): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100000;
                end
                symbol_t'(9'd108): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100001;
                end
                symbol_t'(9'd109): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100010;
                end
                symbol_t'(9'd110): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100011;
                end
                symbol_t'(9'd111): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100100;
                end
                symbol_t'(9'd112): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100101;
                end
                symbol_t'(9'd113): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100110;
                end
                symbol_t'(9'd114): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101100111;
                end
                symbol_t'(9'd115): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101000;
                end
                symbol_t'(9'd116): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101001;
                end
                symbol_t'(9'd117): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101010;
                end
                symbol_t'(9'd118): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101011;
                end
                symbol_t'(9'd119): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101100;
                end
                symbol_t'(9'd120): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101101;
                end
                symbol_t'(9'd121): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101110;
                end
                symbol_t'(9'd122): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101101111;
                end
                symbol_t'(9'd123): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110000;
                end
                symbol_t'(9'd124): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110001;
                end
                symbol_t'(9'd125): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110010;
                end
                symbol_t'(9'd126): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110011;
                end
                symbol_t'(9'd127): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110100;
                end
                symbol_t'(9'd128): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110101;
                end
                symbol_t'(9'd129): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110110;
                end
                symbol_t'(9'd130): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101110111;
                end
                symbol_t'(9'd131): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111000;
                end
                symbol_t'(9'd132): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111001;
                end
                symbol_t'(9'd133): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111010;
                end
                symbol_t'(9'd134): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111011;
                end
                symbol_t'(9'd135): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111100;
                end
                symbol_t'(9'd136): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111101;
                end
                symbol_t'(9'd137): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111110;
                end
                symbol_t'(9'd138): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b101111111;
                end
                symbol_t'(9'd139): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000000;
                end
                symbol_t'(9'd140): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000001;
                end
                symbol_t'(9'd141): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000010;
                end
                symbol_t'(9'd142): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000011;
                end
                symbol_t'(9'd143): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000100;
                end
                symbol_t'(9'd144): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000101;
                end
                symbol_t'(9'd145): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000110;
                end
                symbol_t'(9'd146): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110000111;
                end
                symbol_t'(9'd147): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001000;
                end
                symbol_t'(9'd148): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001001;
                end
                symbol_t'(9'd149): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001010;
                end
                symbol_t'(9'd150): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001011;
                end
                symbol_t'(9'd151): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001100;
                end
                symbol_t'(9'd152): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001101;
                end
                symbol_t'(9'd153): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001110;
                end
                symbol_t'(9'd154): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110001111;
                end
                symbol_t'(9'd155): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010000;
                end
                symbol_t'(9'd156): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010001;
                end
                symbol_t'(9'd157): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010010;
                end
                symbol_t'(9'd158): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010011;
                end
                symbol_t'(9'd159): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010100;
                end
                symbol_t'(9'd160): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010101;
                end
                symbol_t'(9'd161): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010110;
                end
                symbol_t'(9'd162): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110010111;
                end
                symbol_t'(9'd163): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011000;
                end
                symbol_t'(9'd164): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011001;
                end
                symbol_t'(9'd165): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011010;
                end
                symbol_t'(9'd166): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011011;
                end
                symbol_t'(9'd167): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011100;
                end
                symbol_t'(9'd168): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011101;
                end
                symbol_t'(9'd169): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011110;
                end
                symbol_t'(9'd170): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110011111;
                end
                symbol_t'(9'd171): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100000;
                end
                symbol_t'(9'd172): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100001;
                end
                symbol_t'(9'd173): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100010;
                end
                symbol_t'(9'd174): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100011;
                end
                symbol_t'(9'd175): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100100;
                end
                symbol_t'(9'd176): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100101;
                end
                symbol_t'(9'd177): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100110;
                end
                symbol_t'(9'd178): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110100111;
                end
                symbol_t'(9'd179): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101000;
                end
                symbol_t'(9'd180): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101001;
                end
                symbol_t'(9'd181): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101010;
                end
                symbol_t'(9'd182): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101011;
                end
                symbol_t'(9'd183): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101100;
                end
                symbol_t'(9'd184): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101101;
                end
                symbol_t'(9'd185): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101110;
                end
                symbol_t'(9'd186): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110101111;
                end
                symbol_t'(9'd187): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110000;
                end
                symbol_t'(9'd188): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110001;
                end
                symbol_t'(9'd189): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110010;
                end
                symbol_t'(9'd190): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110011;
                end
                symbol_t'(9'd191): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110100;
                end
                symbol_t'(9'd192): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110101;
                end
                symbol_t'(9'd193): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110110;
                end
                symbol_t'(9'd194): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110110111;
                end
                symbol_t'(9'd195): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111000;
                end
                symbol_t'(9'd196): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111001;
                end
                symbol_t'(9'd197): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111010;
                end
                symbol_t'(9'd198): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111011;
                end
                symbol_t'(9'd199): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111100;
                end
                symbol_t'(9'd200): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111101;
                end
                symbol_t'(9'd201): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111110;
                end
                symbol_t'(9'd202): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b110111111;
                end
                symbol_t'(9'd203): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000000;
                end
                symbol_t'(9'd204): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000001;
                end
                symbol_t'(9'd205): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000010;
                end
                symbol_t'(9'd206): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000011;
                end
                symbol_t'(9'd207): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000100;
                end
                symbol_t'(9'd208): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000101;
                end
                symbol_t'(9'd209): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000110;
                end
                symbol_t'(9'd210): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111000111;
                end
                symbol_t'(9'd211): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001000;
                end
                symbol_t'(9'd212): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001001;
                end
                symbol_t'(9'd213): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001010;
                end
                symbol_t'(9'd214): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001011;
                end
                symbol_t'(9'd215): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001100;
                end
                symbol_t'(9'd216): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001101;
                end
                symbol_t'(9'd217): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001110;
                end
                symbol_t'(9'd218): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111001111;
                end
                symbol_t'(9'd219): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010000;
                end
                symbol_t'(9'd220): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010001;
                end
                symbol_t'(9'd221): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010010;
                end
                symbol_t'(9'd222): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010011;
                end
                symbol_t'(9'd223): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010100;
                end
                symbol_t'(9'd224): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010101;
                end
                symbol_t'(9'd225): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010110;
                end
                symbol_t'(9'd226): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111010111;
                end
                symbol_t'(9'd227): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011000;
                end
                symbol_t'(9'd228): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011001;
                end
                symbol_t'(9'd229): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011010;
                end
                symbol_t'(9'd230): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011011;
                end
                symbol_t'(9'd231): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011100;
                end
                symbol_t'(9'd232): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011101;
                end
                symbol_t'(9'd233): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011110;
                end
                symbol_t'(9'd234): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111011111;
                end
                symbol_t'(9'd235): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100000;
                end
                symbol_t'(9'd236): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100001;
                end
                symbol_t'(9'd237): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100010;
                end
                symbol_t'(9'd238): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100011;
                end
                symbol_t'(9'd239): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100100;
                end
                symbol_t'(9'd240): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100101;
                end
                symbol_t'(9'd241): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100110;
                end
                symbol_t'(9'd242): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111100111;
                end
                symbol_t'(9'd243): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101000;
                end
                symbol_t'(9'd244): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101001;
                end
                symbol_t'(9'd245): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101010;
                end
                symbol_t'(9'd246): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101011;
                end
                symbol_t'(9'd247): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101100;
                end
                symbol_t'(9'd248): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101101;
                end
                symbol_t'(9'd249): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101110;
                end
                symbol_t'(9'd250): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111101111;
                end
                symbol_t'(9'd251): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110000;
                end
                symbol_t'(9'd252): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110001;
                end
                symbol_t'(9'd253): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110010;
                end
                symbol_t'(9'd254): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110011;
                end
                symbol_t'(9'd255): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110100;
                end
                symbol_t'(9'd256): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0011000;
                end
                symbol_t'(9'd257): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0011001;
                end
                symbol_t'(9'd258): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0011010;
                end
                symbol_t'(9'd259): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0011011;
                end
                symbol_t'(9'd260): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0011100;
                end
                symbol_t'(9'd261): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b000111;
                end
                symbol_t'(9'd262): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0011101;
                end
                symbol_t'(9'd263): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0011110;
                end
                symbol_t'(9'd264): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0011111;
                end
                symbol_t'(9'd265): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0100000;
                end
                symbol_t'(9'd266): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0100001;
                end
                symbol_t'(9'd267): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0100010;
                end
                symbol_t'(9'd268): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0100011;
                end
                symbol_t'(9'd269): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0100100;
                end
                symbol_t'(9'd270): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0100101;
                end
                symbol_t'(9'd271): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0100110;
                end
                symbol_t'(9'd272): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0100111;
                end
                symbol_t'(9'd273): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101000;
                end
                symbol_t'(9'd274): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101001;
                end
                symbol_t'(9'd275): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101010;
                end
                symbol_t'(9'd276): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101011;
                end
                symbol_t'(9'd277): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101100;
                end
                symbol_t'(9'd278): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101101;
                end
                symbol_t'(9'd279): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101110;
                end
                symbol_t'(9'd280): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0101111;
                end
                symbol_t'(9'd281): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110000;
                end
                symbol_t'(9'd282): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110001;
                end
                symbol_t'(9'd283): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110010;
                end
                symbol_t'(9'd284): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110011;
                end
                symbol_t'(9'd285): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01101010;
                end
                symbol_t'(9'd286): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01101011;
                end
                symbol_t'(9'd287): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01101100;
                end
                symbol_t'(9'd288): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01101101;
                end
                symbol_t'(9'd289): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01101110;
                end
                symbol_t'(9'd290): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01101111;
                end
                symbol_t'(9'd291): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110000;
                end
                symbol_t'(9'd292): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110001;
                end
                symbol_t'(9'd293): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110010;
                end
                symbol_t'(9'd294): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110011;
                end
                symbol_t'(9'd295): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110100;
                end
                symbol_t'(9'd296): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110101;
                end
                symbol_t'(9'd297): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110110;
                end
                symbol_t'(9'd298): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01110111;
                end
                symbol_t'(9'd299): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01111000;
                end
                symbol_t'(9'd300): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01111001;
                end
                symbol_t'(9'd301): begin
                    result.valid = 1'b1;
                    result.used = 4'd8;
                    result.bits = 12'b01111010;
                end
                symbol_t'(9'd302): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110101;
                end
                symbol_t'(9'd303): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110110;
                end
                symbol_t'(9'd304): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111110111;
                end
                symbol_t'(9'd305): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111111000;
                end
                symbol_t'(9'd306): begin
                    result.valid = 1'b1;
                    result.used = 4'd9;
                    result.bits = 12'b111111001;
                end
                symbol_t'(9'd307): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111110100;
                end
                symbol_t'(9'd308): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111110101;
                end
                symbol_t'(9'd309): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111110110;
                end
                symbol_t'(9'd310): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111110111;
                end
                symbol_t'(9'd311): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111111000;
                end
                symbol_t'(9'd312): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111111001;
                end
                symbol_t'(9'd313): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111111010;
                end
                symbol_t'(9'd314): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111111011;
                end
                symbol_t'(9'd315): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111111100;
                end
                symbol_t'(9'd316): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111111101;
                end
                symbol_t'(9'd317): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111111110;
                end
                symbol_t'(9'd318): begin
                    result.valid = 1'b1;
                    result.used = 4'd10;
                    result.bits = 12'b1111111111;
                end
                symbol_t'(9'd319): begin
                    result.valid = 1'b1;
                    result.used = 4'd7;
                    result.bits = 12'b0110100;
                end
                symbol_t'(9'd320): begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.bits = 12'b00000;
                end
                symbol_t'(9'd321): begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.bits = 12'b00001;
                end
                symbol_t'(9'd322): begin
                    result.valid = 1'b1;
                    result.used = 4'd5;
                    result.bits = 12'b00010;
                end
                symbol_t'(9'd323): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b001000;
                end
                symbol_t'(9'd324): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b001001;
                end
                symbol_t'(9'd325): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b001010;
                end
                symbol_t'(9'd326): begin
                    result.valid = 1'b1;
                    result.used = 4'd6;
                    result.bits = 12'b001011;
                end
                default: begin
                end
            endcase
            encode_chunk_symbol = result;
        end
    endfunction

    function automatic int experimental_dict_code_length(input symbol_t sym);
        huff_code_t code;
        begin
            code = encode_dict_symbol(sym);
            experimental_dict_code_length = int'(code.used);
        end
    endfunction

    function automatic int experimental_chunk_code_length(input symbol_t sym);
        huff_code_t code;
        begin
            code = encode_chunk_symbol(sym);
            experimental_chunk_code_length = int'(code.used);
        end
    endfunction

endpackage
