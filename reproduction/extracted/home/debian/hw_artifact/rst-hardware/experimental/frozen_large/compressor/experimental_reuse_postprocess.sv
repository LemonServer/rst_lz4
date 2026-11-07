`timescale 1ps / 1ps
`default_nettype none

module ExperimentalReusePostprocess
    import rst_pkg::*;
    import experimental_huffman_pkg::*;
(
    input  dict_count_t dict_count,
    input  seq_t dict_seqs [MAX_DICT_ENTRIES],
    input  logic [2:0] dict_lens [MAX_DICT_ENTRIES],
    input  vsym_t compressed_syms [PAGE_WIDTH],
    output dict_count_t stored_dict_count,
    output symbol_t dict_payload_tokens [MAX_DICT_ENTRIES * MAX_SEQ_LEN],
    output logic dict_payload_token_valid [MAX_DICT_ENTRIES * MAX_SEQ_LEN],
    output int unsigned dict_payload_token_count,
    output int unsigned dict_bits,
    output logic [EXPERIMENTAL_DICT_BITS_MAX-1:0] dict_bitstream,
    output vsym_t compressed_tokens [PAGE_WIDTH],
    output int unsigned compressed_symbol_count,
    output int unsigned chunk_bits [PAGE_CHUNKS],
    output logic [EXPERIMENTAL_CHUNK_BITS_MAX-1:0] compressed_chunk_bitstreams [PAGE_CHUNKS],
    output int unsigned total_chunk_bits,
    output int unsigned total_bits
);

    task automatic push_history(
        inout symbol_t history [EXPERIMENTAL_REUSE_CODE_COUNT],
        inout int unsigned history_len,
        input symbol_t sym
    );
        begin
            if (history_len < EXPERIMENTAL_REUSE_CODE_COUNT) begin
                history[history_len] = sym;
                history_len = history_len + 1;
            end else begin
                for (int idx = 0; idx < EXPERIMENTAL_REUSE_CODE_COUNT - 1; idx++) begin
                    history[idx] = history[idx + 1];
                end
                history[EXPERIMENTAL_REUSE_CODE_COUNT - 1] = sym;
            end
        end
    endtask

    function automatic symbol_t best_reuse_token(
        input symbol_t sym,
        input bit is_dict_stream,
        input symbol_t history [EXPERIMENTAL_REUSE_CODE_COUNT],
        input int unsigned history_len
    );
        symbol_t best_token;
        symbol_t candidate;
        int unsigned best_len;
        int unsigned candidate_len;
        begin
            best_token = sym;
            best_len = is_dict_stream ?
                experimental_dict_code_length(sym) :
                experimental_chunk_code_length(sym);

            for (int distance = 1; distance <= EXPERIMENTAL_REUSE_CODE_COUNT; distance++) begin
                if ((history_len >= distance) && (history[history_len - distance] == sym)) begin
                    candidate = experimental_reuse_symbol(distance);
                    candidate_len = is_dict_stream ?
                        experimental_dict_code_length(candidate) :
                        experimental_chunk_code_length(candidate);
                    if (candidate_len < best_len) begin
                        best_token = candidate;
                        best_len = candidate_len;
                    end
                end
            end

            best_reuse_token = best_token;
        end
    endfunction

    task automatic append_dict_bits(
        inout logic [EXPERIMENTAL_DICT_BITS_MAX-1:0] stream,
        inout int unsigned bit_pos,
        input logic [EXPERIMENTAL_CODE_MAX_LEN-1:0] bits,
        input int unsigned used
    );
        begin
            for (int bit_idx = 0; bit_idx < used; bit_idx++) begin
                if ((bit_pos + bit_idx) < EXPERIMENTAL_DICT_BITS_MAX) begin
                    stream[EXPERIMENTAL_DICT_BITS_MAX - 1 - (bit_pos + bit_idx)] =
                        bits[used - 1 - bit_idx];
                end
            end
            bit_pos = bit_pos + used;
        end
    endtask

    task automatic append_chunk_bits(
        inout logic [EXPERIMENTAL_CHUNK_BITS_MAX-1:0] stream,
        inout int unsigned bit_pos,
        input logic [EXPERIMENTAL_CODE_MAX_LEN-1:0] bits,
        input int unsigned used
    );
        begin
            for (int bit_idx = 0; bit_idx < used; bit_idx++) begin
                if ((bit_pos + bit_idx) < EXPERIMENTAL_CHUNK_BITS_MAX) begin
                    stream[EXPERIMENTAL_CHUNK_BITS_MAX - 1 - (bit_pos + bit_idx)] =
                        bits[used - 1 - bit_idx];
                end
            end
            bit_pos = bit_pos + used;
        end
    endtask

    always_comb begin
        int unsigned input_dict_count;
        int unsigned explicit_dict_count;
        int unsigned page_idx;
        symbol_t dict_history [EXPERIMENTAL_REUSE_CODE_COUNT];
        symbol_t chunk_history [EXPERIMENTAL_REUSE_CODE_COUNT];
        int unsigned dict_history_len;
        int unsigned chunk_history_len;
        symbol_t token;
        huff_code_t encoded_token;
        logic [EXPERIMENTAL_CODE_MAX_LEN-1:0] raw_bits;

        input_dict_count = int'(dict_count);
        explicit_dict_count = (input_dict_count > EXPERIMENTAL_FREE_DICT_ENTRIES) ?
            (input_dict_count - EXPERIMENTAL_FREE_DICT_ENTRIES) :
            0;
        stored_dict_count = dict_count_t'(explicit_dict_count);
        dict_payload_token_count = 0;
        dict_bits = 0;
        dict_bitstream = '0;
        compressed_symbol_count = 0;
        total_chunk_bits = 0;
        total_bits = 0;

        for (int idx = 0; idx < MAX_DICT_ENTRIES * MAX_SEQ_LEN; idx++) begin
            dict_payload_tokens[idx] = '0;
            dict_payload_token_valid[idx] = 1'b0;
        end

        for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
            compressed_tokens[idx] = '0;
        end

        for (int idx = 0; idx < PAGE_CHUNKS; idx++) begin
            chunk_bits[idx] = 0;
            compressed_chunk_bitstreams[idx] = '0;
        end

        for (int idx = 0; idx < EXPERIMENTAL_REUSE_CODE_COUNT; idx++) begin
            dict_history[idx] = '0;
            chunk_history[idx] = '0;
        end

        raw_bits = '0;
        raw_bits[DICT_COUNT_BITS-1:0] = dict_count_t'(explicit_dict_count);
        append_dict_bits(dict_bitstream, dict_bits, raw_bits, DICT_COUNT_BITS);

        for (int dict_idx = EXPERIMENTAL_FREE_DICT_ENTRIES; dict_idx < MAX_DICT_ENTRIES; dict_idx++) begin
            if (dict_idx < input_dict_count) begin
                raw_bits = '0;
                raw_bits[DICT_LEN_BITS-1:0] = dict_len_encode(dict_lens[dict_idx]);
                append_dict_bits(dict_bitstream, dict_bits, raw_bits, DICT_LEN_BITS);
            end
        end

        dict_history_len = 0;
        push_history(dict_history, dict_history_len, experimental_literal_sym(0));
        push_history(dict_history, dict_history_len, experimental_literal_sym(0));
        push_history(dict_history, dict_history_len, experimental_code_sym(0));
        push_history(dict_history, dict_history_len, experimental_code_sym(0));

        for (int dict_idx = EXPERIMENTAL_FREE_DICT_ENTRIES; dict_idx < MAX_DICT_ENTRIES; dict_idx++) begin
            if (dict_idx < input_dict_count) begin
                for (int sym_idx = 0; sym_idx < MAX_SEQ_LEN; sym_idx++) begin
                    if (sym_idx < dict_lens[dict_idx]) begin
                        token = best_reuse_token(
                            dict_seqs[dict_idx][sym_idx],
                            1'b1,
                            dict_history,
                            dict_history_len
                        );
                        dict_payload_tokens[dict_payload_token_count] = token;
                        dict_payload_token_valid[dict_payload_token_count] = 1'b1;
                        dict_payload_token_count = dict_payload_token_count + 1;
                        encoded_token = encode_dict_symbol(token);
                        append_dict_bits(
                            dict_bitstream,
                            dict_bits,
                            encoded_token.bits,
                            int'(encoded_token.used)
                        );
                        push_history(dict_history, dict_history_len, dict_seqs[dict_idx][sym_idx]);
                    end
                end
            end
        end

        for (int chunk_idx = 0; chunk_idx < PAGE_CHUNKS; chunk_idx++) begin
            for (int idx = 0; idx < EXPERIMENTAL_REUSE_CODE_COUNT; idx++) begin
                chunk_history[idx] = '0;
            end
            chunk_history_len = 0;

            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                page_idx = chunk_idx * CHUNK_WIDTH + lane;
                if (compressed_syms[page_idx].valid) begin
                    token = best_reuse_token(
                        compressed_syms[page_idx].sym,
                        1'b0,
                        chunk_history,
                        chunk_history_len
                    );
                    compressed_tokens[page_idx].valid = 1'b1;
                    compressed_tokens[page_idx].sym = token;
                    compressed_symbol_count = compressed_symbol_count + 1;
                    encoded_token = encode_chunk_symbol(token);
                    append_chunk_bits(
                        compressed_chunk_bitstreams[chunk_idx],
                        chunk_bits[chunk_idx],
                        encoded_token.bits,
                        int'(encoded_token.used)
                    );
                    push_history(chunk_history, chunk_history_len, compressed_syms[page_idx].sym);
                end
            end

            total_chunk_bits = total_chunk_bits + chunk_bits[chunk_idx];
        end

        total_bits = dict_bits + total_chunk_bits;
    end
endmodule
