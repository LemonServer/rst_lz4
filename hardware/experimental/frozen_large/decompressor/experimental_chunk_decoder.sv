`timescale 1ps / 1ps
`default_nettype none

module ExperimentalChunkDecoder
    import rst_pkg::*;
    import experimental_huffman_pkg::*;
(
    input  logic [EXPERIMENTAL_CHUNK_BITS_MAX-1:0] chunk_bits,
    input  logic [EXPERIMENTAL_CHUNK_BIT_COUNT_W-1:0] chunk_bit_count,
    output vsym_t compressed_out [CHUNK_WIDTH],
    output logic [$clog2(CHUNK_WIDTH + 1)-1:0] token_count,
    output logic parse_ok
);
    symbol_t resolved_history [0:EXPERIMENTAL_CHUNK_MAX_DECODE_TOKENS-1];

    function automatic logic [EXPERIMENTAL_CHUNK_MAX_CODE_LEN-1:0] chunk_window_at(
        input logic [EXPERIMENTAL_CHUNK_BITS_MAX-1:0] bits,
        input int pos,
        input int valid_bits
    );
        integer bit_idx;
        logic [EXPERIMENTAL_CHUNK_MAX_CODE_LEN-1:0] window;
        begin
            window = '0;
            for (bit_idx = 0; bit_idx < EXPERIMENTAL_CHUNK_MAX_CODE_LEN; bit_idx = bit_idx + 1) begin
                if ((pos + bit_idx) < valid_bits) begin
                    window[EXPERIMENTAL_CHUNK_MAX_CODE_LEN - 1 - bit_idx] =
                        bits[EXPERIMENTAL_CHUNK_BITS_MAX - 1 - (pos + bit_idx)];
                end
            end
            chunk_window_at = window;
        end
    endfunction

    always_comb begin
        int bit_pos_i;
        int history_count_i;
        int token_count_i;
        huff_decode_t decode_i;
        symbol_t resolved_sym_i;

        parse_ok = 1'b1;
        token_count = '0;
        bit_pos_i = 0;
        history_count_i = 0;
        token_count_i = 0;
        decode_i = '0;
        resolved_sym_i = '0;

        for (int idx = 0; idx < CHUNK_WIDTH; idx++) begin
            compressed_out[idx] = '0;
        end
        for (int idx = 0; idx < EXPERIMENTAL_CHUNK_MAX_DECODE_TOKENS; idx++) begin
            resolved_history[idx] = '0;
        end

        for (int step = 0; step < EXPERIMENTAL_CHUNK_MAX_DECODE_TOKENS; step++) begin
            if (parse_ok && (bit_pos_i < int'(chunk_bit_count))) begin
                decode_i = decode_chunk_window(chunk_window_at(
                    chunk_bits,
                    bit_pos_i,
                    int'(chunk_bit_count)
                ));
                if (!decode_i.valid || ((bit_pos_i + int'(decode_i.used)) > int'(chunk_bit_count))) begin
                    parse_ok = 1'b0;
                end else begin
                    bit_pos_i += int'(decode_i.used);
                    resolved_sym_i = decode_i.sym;

                    if (experimental_sym_is_reuse(decode_i.sym)) begin
                        int distance_i;

                        distance_i = experimental_reuse_distance(decode_i.sym);
                        if (history_count_i >= distance_i) begin
                            resolved_sym_i = resolved_history[history_count_i - distance_i];
                        end else begin
                            parse_ok = 1'b0;
                        end
                    end

                    if (parse_ok) begin
                        if (history_count_i < EXPERIMENTAL_CHUNK_MAX_DECODE_TOKENS) begin
                            resolved_history[history_count_i] = resolved_sym_i;
                            history_count_i++;
                        end else begin
                            parse_ok = 1'b0;
                        end

                        if (token_count_i < CHUNK_WIDTH) begin
                            compressed_out[token_count_i].sym = resolved_sym_i;
                            compressed_out[token_count_i].valid = 1'b1;
                            token_count_i++;
                        end else begin
                            parse_ok = 1'b0;
                        end
                    end
                end
            end
        end

        if (parse_ok && (bit_pos_i != int'(chunk_bit_count))) begin
            parse_ok = 1'b0;
        end

        token_count = token_count_i[$clog2(CHUNK_WIDTH + 1)-1:0];
    end
endmodule
