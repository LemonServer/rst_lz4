`timescale 1ps / 1ps
`default_nettype none

module ExperimentalDictDecoder
    import rst_pkg::*;
    import experimental_huffman_pkg::*;
(
    input  logic [EXPERIMENTAL_DICT_BITS_MAX-1:0] dict_bits,
    input  dict_bit_count_t dict_bit_count,
    output seq_t dict_seqs [MAX_DICT_ENTRIES],
    output logic [2:0] dict_lens [MAX_DICT_ENTRIES],
    output dict_count_t dict_count,
    output logic parse_ok
);
    symbol_t resolved_history [0:EXPERIMENTAL_DICT_RESOLVED_SYMBOLS_MAX-1];

    function automatic logic [EXPERIMENTAL_DICT_MAX_CODE_LEN-1:0] dict_window_at(
        input logic [EXPERIMENTAL_DICT_BITS_MAX-1:0] bits,
        input int pos,
        input int valid_bits
    );
        integer bit_idx;
        logic [EXPERIMENTAL_DICT_MAX_CODE_LEN-1:0] window;
        begin
            window = '0;
            for (bit_idx = 0; bit_idx < EXPERIMENTAL_DICT_MAX_CODE_LEN; bit_idx = bit_idx + 1) begin
                if ((pos + bit_idx) < valid_bits) begin
                    window[EXPERIMENTAL_DICT_MAX_CODE_LEN - 1 - bit_idx] =
                        bits[EXPERIMENTAL_DICT_BITS_MAX - 1 - (pos + bit_idx)];
                end
            end
            dict_window_at = window;
        end
    endfunction

    always_comb begin
        int added_entries_i;
        int total_entries_i;
        int expected_symbol_count_i;
        int bit_pos_i;
        int history_count_i;
        int sym_cursor_i;
        huff_decode_t decode_i;
        symbol_t resolved_sym_i;

        parse_ok = 1'b1;
        dict_count = dict_count_t'(EXPERIMENTAL_FREE_DICT_ENTRIES);
        added_entries_i = 0;
        total_entries_i = EXPERIMENTAL_FREE_DICT_ENTRIES;
        expected_symbol_count_i = EXPERIMENTAL_FREE_DICT_ENTRIES * MIN_SEQ_LEN;
        bit_pos_i = 0;
        history_count_i = 0;
        sym_cursor_i = 0;
        decode_i = '0;
        resolved_sym_i = '0;

        for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
            dict_seqs[idx] = '0;
            dict_lens[idx] = '0;
        end
        for (int idx = 0; idx < EXPERIMENTAL_DICT_RESOLVED_SYMBOLS_MAX; idx++) begin
            resolved_history[idx] = '0;
        end

        dict_lens[0] = 3'd2;
        dict_seqs[0][0] = experimental_literal_sym(0);
        dict_seqs[0][1] = experimental_literal_sym(0);
        dict_lens[1] = 3'd2;
        dict_seqs[1][0] = experimental_code_sym(0);
        dict_seqs[1][1] = experimental_code_sym(0);

        resolved_history[0] = experimental_literal_sym(0);
        resolved_history[1] = experimental_literal_sym(0);
        resolved_history[2] = experimental_code_sym(0);
        resolved_history[3] = experimental_code_sym(0);
        history_count_i = EXPERIMENTAL_FREE_DICT_ENTRIES * MIN_SEQ_LEN;

        if (int'(dict_bit_count) < DICT_COUNT_BITS) begin
            parse_ok = 1'b0;
        end else begin
            added_entries_i = int'(dict_bits[EXPERIMENTAL_DICT_BITS_MAX-1 -: DICT_COUNT_BITS]);
            if (added_entries_i > (MAX_DICT_ENTRIES - EXPERIMENTAL_FREE_DICT_ENTRIES)) begin
                parse_ok = 1'b0;
            end

            total_entries_i = added_entries_i + EXPERIMENTAL_FREE_DICT_ENTRIES;
            dict_count = dict_count_t'(total_entries_i);
            bit_pos_i = DICT_COUNT_BITS;

            for (int idx = 0; idx < (MAX_DICT_ENTRIES - EXPERIMENTAL_FREE_DICT_ENTRIES); idx++) begin
                if (idx < added_entries_i) begin
                    if ((bit_pos_i + DICT_LEN_BITS) > int'(dict_bit_count)) begin
                        parse_ok = 1'b0;
                    end else begin
                        dict_lens[idx + EXPERIMENTAL_FREE_DICT_ENTRIES] = dict_len_decode(
                            dict_bits[EXPERIMENTAL_DICT_BITS_MAX - 1 - bit_pos_i -: DICT_LEN_BITS]
                        );
                        expected_symbol_count_i += dict_lens[idx + EXPERIMENTAL_FREE_DICT_ENTRIES];
                        bit_pos_i += DICT_LEN_BITS;
                    end
                end
            end

            for (int step = 0; step < EXPERIMENTAL_DICT_MAX_DECODE_TOKENS; step++) begin
                if (parse_ok && (bit_pos_i < int'(dict_bit_count))) begin
                    decode_i = decode_dict_window(dict_window_at(
                        dict_bits,
                        bit_pos_i,
                        int'(dict_bit_count)
                    ));
                    if (!decode_i.valid || ((bit_pos_i + int'(decode_i.used)) > int'(dict_bit_count))) begin
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
                            if (history_count_i < EXPERIMENTAL_DICT_RESOLVED_SYMBOLS_MAX) begin
                                resolved_history[history_count_i] = resolved_sym_i;
                                history_count_i++;
                            end else begin
                                parse_ok = 1'b0;
                            end
                        end
                    end
                end
            end

            if (parse_ok && (history_count_i < expected_symbol_count_i)) begin
                parse_ok = 1'b0;
            end

            sym_cursor_i = 0;
            for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                if (idx < total_entries_i) begin
                    if ((sym_cursor_i + dict_lens[idx]) > history_count_i) begin
                        parse_ok = 1'b0;
                    end else begin
                        for (int sym_idx = 0; sym_idx < MAX_SEQ_LEN; sym_idx++) begin
                            if (sym_idx < dict_lens[idx]) begin
                                dict_seqs[idx][sym_idx] = resolved_history[sym_cursor_i + sym_idx];
                            end
                        end
                        sym_cursor_i += dict_lens[idx];
                    end
                end
            end
        end
    end
endmodule
