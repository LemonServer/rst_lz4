`timescale 1ps / 1ps
`default_nettype none

module DictSerializer
    import rst_pkg::*;
(
    input  dict_count_t dict_count,
    input  seq_t dict_seqs [MAX_DICT_ENTRIES],
    input  logic [2:0] dict_lens [MAX_DICT_ENTRIES],
    output dict_packed_t dict_packed,
    output dict_bit_count_t dict_packed_bits
);
    localparam int MAX_SERIALIZED_SYMBOLS = MAX_DICT_ENTRIES * MAX_SEQ_LEN;
    localparam int MAX_PACKED_SYMBOLS = DICT_STORAGE_BITS / 9;

    symbol_t payload_symbols [MAX_SERIALIZED_SYMBOLS];
    dict_packed_t payload_packed;

    always_comb begin
        int payload_shift_bits;
        int running_symbol_offset;
        int entry_offset;
        logic [DICT_LEN_BITS-1:0] encoded_len;

        dict_packed = '0;
        dict_packed_bits = '0;
        payload_packed = '0;
        payload_shift_bits = DICT_COUNT_BITS + int'(dict_count) * DICT_LEN_BITS;
        running_symbol_offset = 0;
        entry_offset = 0;
        encoded_len = '0;

        for (int sym_idx = 0; sym_idx < MAX_SERIALIZED_SYMBOLS; sym_idx++) begin
            payload_symbols[sym_idx] = '0;
        end

        dict_packed[DICT_STORAGE_BITS - 1 -: DICT_COUNT_BITS] = dict_count;

        for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
            if (idx < dict_count) begin
                encoded_len = dict_len_encode(dict_lens[idx]);
                dict_packed[
                    DICT_STORAGE_BITS - 1 - (DICT_COUNT_BITS + idx * DICT_LEN_BITS) -: DICT_LEN_BITS
                ] = encoded_len;

                entry_offset = running_symbol_offset;
                for (int sym_idx = 0; sym_idx < MAX_SEQ_LEN; sym_idx++) begin
                    if ((sym_idx < dict_lens[idx]) &&
                        ((entry_offset + sym_idx) < MAX_SERIALIZED_SYMBOLS)) begin
                        payload_symbols[entry_offset + sym_idx] = dict_seqs[idx][sym_idx];
                    end
                end
                running_symbol_offset = entry_offset + dict_lens[idx];
            end
        end

        for (int sym_idx = 0; sym_idx < MAX_PACKED_SYMBOLS; sym_idx++) begin
            if (sym_idx < MAX_SERIALIZED_SYMBOLS) begin
                payload_packed[DICT_STORAGE_BITS - 1 - sym_idx * 9 -: 9] = payload_symbols[sym_idx];
            end
        end

        dict_packed |= payload_packed >> payload_shift_bits;
        dict_packed_bits = dict_bit_count_t'(payload_shift_bits + running_symbol_offset * 9);
    end
endmodule

module DictDeserializer
    import rst_pkg::*;
(
    input  dict_packed_t dict_packed,
    output seq_t dict_seqs [MAX_DICT_ENTRIES],
    output logic [2:0] dict_lens [MAX_DICT_ENTRIES],
    output dict_count_t dict_count,
    output dict_bit_count_t dict_packed_bits
);
    localparam int MAX_PACKED_SYMBOLS = DICT_STORAGE_BITS / 9;

    symbol_t payload_symbols [MAX_PACKED_SYMBOLS];
    dict_packed_t payload_aligned;

    always_comb begin
        int payload_shift_bits;
        int running_symbol_offset;
        int entry_offset;
        dict_count_t count_tmp;
        logic [DICT_LEN_BITS-1:0] encoded_len;
        logic [2:0] decoded_len;

        payload_shift_bits = DICT_COUNT_BITS;
        running_symbol_offset = 0;
        entry_offset = 0;
        count_tmp = '0;
        encoded_len = '0;
        decoded_len = '0;
        dict_count = '0;
        dict_packed_bits = '0;
        payload_aligned = '0;

        for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
            dict_seqs[idx] = '0;
            dict_lens[idx] = '0;
        end

        for (int sym_idx = 0; sym_idx < MAX_PACKED_SYMBOLS; sym_idx++) begin
            payload_symbols[sym_idx] = '0;
        end

        count_tmp = dict_count_t'(dict_packed[DICT_STORAGE_BITS-1 -: DICT_COUNT_BITS]);
        dict_count = count_tmp;
        payload_shift_bits = DICT_COUNT_BITS + int'(count_tmp) * DICT_LEN_BITS;
        payload_aligned = dict_packed << payload_shift_bits;

        for (int sym_idx = 0; sym_idx < MAX_PACKED_SYMBOLS; sym_idx++) begin
            payload_symbols[sym_idx] =
                payload_aligned[DICT_STORAGE_BITS - 1 - sym_idx * 9 -: 9];
        end

        for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
            entry_offset = running_symbol_offset;
            encoded_len = '0;
            decoded_len = '0;

            if (idx < count_tmp) begin
                encoded_len =
                    dict_packed[DICT_STORAGE_BITS - 1 - (DICT_COUNT_BITS + idx * DICT_LEN_BITS) -: DICT_LEN_BITS];
                decoded_len = dict_len_decode(encoded_len);
                dict_lens[idx] = decoded_len;

                for (int sym_idx = 0; sym_idx < MAX_SEQ_LEN; sym_idx++) begin
                    if ((sym_idx < decoded_len) &&
                        ((entry_offset + sym_idx) < MAX_PACKED_SYMBOLS)) begin
                        dict_seqs[idx][sym_idx] = payload_symbols[entry_offset + sym_idx];
                    end
                end

                running_symbol_offset = entry_offset + decoded_len;
            end
        end

        dict_packed_bits = dict_bit_count_t'(payload_shift_bits + running_symbol_offset * 9);
    end
endmodule
