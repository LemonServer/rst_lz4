`timescale 1ps / 1ps
`default_nettype none

module tb_M6DictSerialization;
    import rst_pkg::*;

    seq_t dict_seqs [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens [MAX_DICT_ENTRIES];
    dict_count_t dict_count;
    dict_packed_t dict_packed;
    dict_bit_count_t dict_packed_bits;

    seq_t unpacked_seqs [MAX_DICT_ENTRIES];
    logic [2:0] unpacked_lens [MAX_DICT_ENTRIES];
    dict_count_t unpacked_count;
    dict_bit_count_t unpacked_bits;

    DictSerializer serializer (
        .dict_count(dict_count),
        .dict_seqs(dict_seqs),
        .dict_lens(dict_lens),
        .dict_packed(dict_packed),
        .dict_packed_bits(dict_packed_bits)
    );

    DictDeserializer deserializer (
        .dict_packed(dict_packed),
        .dict_seqs(unpacked_seqs),
        .dict_lens(unpacked_lens),
        .dict_count(unpacked_count),
        .dict_packed_bits(unpacked_bits)
    );

    function automatic symbol_t literal_sym(input int value);
        begin
            literal_sym = symbol_t'(value & 9'h0ff);
        end
    endfunction

    function automatic symbol_t code_sym(input int idx);
        begin
            code_sym = symbol_t'(9'h100 + idx);
        end
    endfunction

    task automatic clear_dict;
        begin
            dict_count = '0;
            for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                dict_seqs[idx] = '0;
                dict_lens[idx] = '0;
            end
        end
    endtask

    task automatic expect_roundtrip(input string case_name);
        begin
            if (unpacked_count !== dict_count) begin
                $fatal(1, "%s count mismatch got=%0d expected=%0d",
                    case_name, unpacked_count, dict_count);
            end

            if (unpacked_bits !== dict_packed_bits) begin
                $fatal(1, "%s packed bit count mismatch got=%0d expected=%0d",
                    case_name, unpacked_bits, dict_packed_bits);
            end

            for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                if (unpacked_lens[idx] !== dict_lens[idx]) begin
                    $fatal(1, "%s len[%0d] mismatch got=%0d expected=%0d",
                        case_name, idx, unpacked_lens[idx], dict_lens[idx]);
                end

                if (unpacked_seqs[idx] !== dict_seqs[idx]) begin
                    $fatal(1, "%s seq[%0d] mismatch got=%h expected=%h",
                        case_name, idx, unpacked_seqs[idx], dict_seqs[idx]);
                end
            end
        end
    endtask

    task automatic run_empty_case;
        begin
            clear_dict();
            #1;

            if (dict_packed_bits != DICT_COUNT_BITS) begin
                $fatal(1, "empty dict packed bits mismatch got=%0d expected=%0d",
                    dict_packed_bits, DICT_COUNT_BITS);
            end

            if (dict_packed[DICT_STORAGE_BITS-1 -: DICT_COUNT_BITS] !== '0) begin
                $fatal(1, "empty dict header mismatch got=%b expected=0",
                    dict_packed[DICT_STORAGE_BITS-1 -: DICT_COUNT_BITS]);
            end

            expect_roundtrip("empty");
        end
    endtask

    task automatic run_multi_length_nested_case;
        localparam int EXPECTED_BITS = DICT_COUNT_BITS + 4 * DICT_LEN_BITS + (2 + 3 + 4 + 5) * 9;
        begin
            clear_dict();

            dict_count = 6'd4;

            dict_lens[0] = 3'd2;
            dict_seqs[0][0] = literal_sym("A");
            dict_seqs[0][1] = code_sym(1);

            dict_lens[1] = 3'd3;
            dict_seqs[1][0] = code_sym(0);
            dict_seqs[1][1] = literal_sym("B");
            dict_seqs[1][2] = literal_sym("C");

            dict_lens[2] = 3'd4;
            dict_seqs[2][0] = literal_sym("D");
            dict_seqs[2][1] = code_sym(1);
            dict_seqs[2][2] = literal_sym("E");
            dict_seqs[2][3] = code_sym(0);

            dict_lens[3] = 3'd5;
            dict_seqs[3][0] = code_sym(2);
            dict_seqs[3][1] = literal_sym("F");
            dict_seqs[3][2] = code_sym(1);
            dict_seqs[3][3] = literal_sym("G");
            dict_seqs[3][4] = literal_sym("H");

            #1;

            if (dict_packed_bits != EXPECTED_BITS) begin
                $fatal(1, "multi_length_nested packed bits mismatch got=%0d expected=%0d",
                    dict_packed_bits, EXPECTED_BITS);
            end

            if (dict_packed[DICT_STORAGE_BITS-1 -: 14] !== 14'b00010000011011) begin
                $fatal(1, "multi_length_nested header mismatch got=%b expected=00010000011011",
                    dict_packed[DICT_STORAGE_BITS-1 -: 14]);
            end

            if (dict_packed[DICT_STORAGE_BITS-15 -: 18] !== {literal_sym("A"), code_sym(1)}) begin
                $fatal(1, "multi_length_nested first entry payload mismatch got=%h expected=%h",
                    dict_packed[DICT_STORAGE_BITS-15 -: 18], {literal_sym("A"), code_sym(1)});
            end

            if (dict_packed[DICT_STORAGE_BITS-33 -: 27] !==
                {code_sym(0), literal_sym("B"), literal_sym("C")}) begin
                $fatal(1, "multi_length_nested second entry payload mismatch got=%h expected=%h",
                    dict_packed[DICT_STORAGE_BITS-33 -: 27],
                    {code_sym(0), literal_sym("B"), literal_sym("C")});
            end

            expect_roundtrip("multi_length_nested");

            $display("multi_length_nested packed_bits=%0d packed_prefix=%h",
                dict_packed_bits, dict_packed[DICT_STORAGE_BITS-1 -: 64]);
        end
    endtask

    initial begin
        run_empty_case();
        run_multi_length_nested_case();
        $display("tb_M6DictSerialization passed");
        $finish;
    end
endmodule
