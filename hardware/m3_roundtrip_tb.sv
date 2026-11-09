`timescale 1ps / 1ps
`default_nettype none

module tb_RoundTripTop;
    import rst_pkg::*;

    localparam int CLK_HALF = 5;
`ifdef M3_COMP_TIMEOUT_CYCLES
    localparam int COMP_TIMEOUT_CYCLES = `M3_COMP_TIMEOUT_CYCLES;
`else
    localparam int COMP_TIMEOUT_CYCLES = 5000;
`endif
`ifdef M3_DECOMP_TIMEOUT_CYCLES
    localparam int DECOMP_TIMEOUT_CYCLES = `M3_DECOMP_TIMEOUT_CYCLES;
`else
    localparam int DECOMP_TIMEOUT_CYCLES = 5000;
`endif
    localparam int RAW_PAGE_BYTES = CHUNK_WIDTH;
    localparam int RAW_PAGE_BITS = RAW_PAGE_BYTES * 8;
    localparam int LITERAL_PAGE_BITS = CHUNK_WIDTH * 9;
    localparam int EMPTY_DICT_PAGE_BITS = LITERAL_PAGE_BITS + DICT_COUNT_BITS;

    logic clk;
    logic rst;
    logic compress_start;
    logic decompress_start;
    symbol_t page_in [CHUNK_WIDTH];
    vsym_t compressed_out [CHUNK_WIDTH];
    seq_t dict_seqs [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens [MAX_DICT_ENTRIES];
    dict_count_t dict_count;
    dict_packed_t dict_packed;
    dict_bit_count_t dict_packed_bits;
    logic compress_done;
    symbol_t decompressed_out [CHUNK_WIDTH];
    logic decompress_done;

    symbol_t stimulus_page [CHUNK_WIDTH];

    CompressorTop compressor_dut (
        .clk(clk),
        .rst(rst),
        .start(compress_start),
        .page_in(page_in),
        .compressed_out(compressed_out),
        .dict_seqs(dict_seqs),
        .dict_lens(dict_lens),
        .dict_count(dict_count),
        .dict_packed(dict_packed),
        .dict_packed_bits(dict_packed_bits),
        .done(compress_done)
    );

    DecompressorTop decompressor_dut (
        .clk(clk),
        .rst(rst),
        .start(decompress_start),
        .compressed_in(compressed_out),
        .dict_packed(dict_packed),
        .decompressed_out(decompressed_out),
        .done(decompress_done)
    );

    always #(CLK_HALF) clk = ~clk;

    task automatic clear_inputs;
        begin
            compress_start = 1'b0;
            decompress_start = 1'b0;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                page_in[i] = '0;
                stimulus_page[i] = '0;
            end
        end
    endtask

    task automatic reset_dut;
        begin
            clear_inputs();
            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic load_page_into_dut;
        begin
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                page_in[i] = stimulus_page[i];
            end
        end
    endtask

    task automatic pulse_compress_start;
        begin
            @(negedge clk);
            compress_start = 1'b1;
            @(negedge clk);
            compress_start = 1'b0;
        end
    endtask

    task automatic pulse_decompress_start;
        begin
            @(negedge clk);
            decompress_start = 1'b1;
            @(negedge clk);
            decompress_start = 1'b0;
        end
    endtask

    task automatic wait_compress_done(input string case_name, output int cycles);
        begin
            cycles = 0;
            while (!compress_done && cycles < COMP_TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycles++;
            end
            if (!compress_done) begin
                $fatal(1, "%s timed out waiting for compressor done", case_name);
            end
        end
    endtask

    task automatic wait_decompress_done(input string case_name, output int cycles);
        begin
            cycles = 0;
            while (!decompress_done && cycles < DECOMP_TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycles++;
            end
            if (!decompress_done) begin
                $fatal(1, "%s timed out waiting for decompressor done", case_name);
            end
        end
    endtask

    function automatic int count_compressed_symbols;
        int count;
        begin
            count = 0;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (compressed_out[i].valid) begin
                    count++;
                end
            end
            return count;
        end
    endfunction

    function automatic int dictionary_bits_used;
        int bits;
        begin
            bits = 0;
            for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                if (idx < dict_count) begin
                    bits += dict_entry_cost_bits(dict_lens[idx]);
                end
            end
            return bits;
        end
    endfunction

    task automatic log_roundtrip_summary(
        input string case_name,
        input int comp_cycles,
        input int decomp_cycles
    );
        int comp_symbols;
        int dict_bits;
        int total_bits;
        real ratio;
        real comp_bytes_per_cycle;
        real decomp_bytes_per_cycle;
        begin
            comp_symbols = count_compressed_symbols();
            dict_bits = dict_packed_bits;
            total_bits = comp_symbols * 9 + dict_bits;
            ratio = RAW_PAGE_BITS * 1.0 / total_bits;
            comp_bytes_per_cycle = RAW_PAGE_BYTES * 1.0 / comp_cycles;
            decomp_bytes_per_cycle = RAW_PAGE_BYTES * 1.0 / decomp_cycles;

            $display("[%s] comp_cycles=%0d decomp_cycles=%0d dict_count=%0d comp_syms=%0d dict_bits=%0d raw_bits=%0d total_bits=%0d ratio=%0.4f comp_Bpc=%0.4f decomp_Bpc=%0.4f",
                case_name, comp_cycles, decomp_cycles, dict_count, comp_symbols, dict_bits,
                RAW_PAGE_BITS, total_bits, ratio, comp_bytes_per_cycle, decomp_bytes_per_cycle);
            for (int idx = 0; idx < dict_count; idx++) begin
                $display("  dict[%0d] len=%0d seq=%h", idx, dict_lens[idx], dict_seqs[idx]);
            end
        end
    endtask

    task automatic run_roundtrip_case(
        input string case_name,
        input int min_dict_entries,
        input bit expect_substitution,
        input bit expect_ratio_gt_one
    );
        int comp_cycles;
        int decomp_cycles;
        int comp_symbols;
        int dict_bits;
        int total_bits;
        begin
            load_page_into_dut();

            pulse_compress_start();
            wait_compress_done(case_name, comp_cycles);

            comp_symbols = count_compressed_symbols();
            dict_bits = dict_packed_bits;
            total_bits = comp_symbols * 9 + dict_bits;

            if (dict_count < min_dict_entries) begin
                $fatal(1, "%s dict_count too small got=%0d expected_at_least=%0d",
                    case_name, dict_count, min_dict_entries);
            end

            if (expect_substitution) begin
                if (comp_symbols >= CHUNK_WIDTH) begin
                    $fatal(1, "%s did not reduce the compressed symbol count got=%0d raw=%0d",
                        case_name, comp_symbols, CHUNK_WIDTH);
                end
            end else begin
                if (dict_count != 0) begin
                    $fatal(1, "%s unexpectedly created dictionary entries got=%0d",
                        case_name, dict_count);
                end
                if (comp_symbols != CHUNK_WIDTH) begin
                    $fatal(1, "%s compressed symbol count mismatch got=%0d expected=%0d",
                        case_name, comp_symbols, CHUNK_WIDTH);
                end
                if (total_bits != EMPTY_DICT_PAGE_BITS) begin
                    $fatal(1, "%s encoded bit count mismatch got=%0d expected=%0d",
                        case_name, total_bits, EMPTY_DICT_PAGE_BITS);
                end
            end

            if (expect_ratio_gt_one) begin
                if (total_bits >= RAW_PAGE_BITS) begin
                    $fatal(1, "%s did not reduce total encoded bits got=%0d raw=%0d",
                        case_name, total_bits, RAW_PAGE_BITS);
                end
            end

            pulse_decompress_start();
            wait_decompress_done(case_name, decomp_cycles);

            if (decompressor_dut.total_out_count_dbg != CHUNK_WIDTH) begin
                $fatal(1, "%s decompressor output count mismatch got=%0d expected=%0d",
                    case_name, decompressor_dut.total_out_count_dbg, CHUNK_WIDTH);
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (decompressed_out[i] !== stimulus_page[i]) begin
                    $fatal(1, "%s decompressed_out[%0d] mismatch got=%0h expected=%0h",
                        case_name, i, decompressed_out[i], stimulus_page[i]);
                end
            end

            log_roundtrip_summary(case_name, comp_cycles, decomp_cycles);
        end
    endtask

    task automatic build_unique_page;
        begin
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                stimulus_page[i] = symbol_t'(i[8:0]);
            end
        end
    endtask

    task automatic build_pair_page;
        begin
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                case (i % 3)
                    0: stimulus_page[i] = 9'h021;
                    1: stimulus_page[i] = 9'h02b;
                    default: stimulus_page[i] = symbol_t'(9'h080 + (i / 3));
                endcase
            end
        end
    endtask

    task automatic build_sparse_len5_single_iter_page;
        symbol_t seq_a [5];
        begin
            seq_a[0] = 9'h01a;
            seq_a[1] = 9'h02b;
            seq_a[2] = 9'h03c;
            seq_a[3] = 9'h04d;
            seq_a[4] = 9'h05e;

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                stimulus_page[i] = symbol_t'(i[8:0]);
            end

            for (int rep = 0; rep < 4; rep++) begin
                int base;
                if (CHUNK_WIDTH >= 192) begin
                    base = 24 + rep * 56;
                end else begin
                    base = rep * 8;
                end
                for (int j = 0; j < 5; j++) begin
                    if ((base + j) < CHUNK_WIDTH) begin
                        stimulus_page[base + j] = seq_a[j];
                    end
                end
            end
        end
    endtask

    task automatic build_sparse_len4_single_iter_page;
        symbol_t seq_b [4];
        begin
            seq_b[0] = 9'h061;
            seq_b[1] = 9'h072;
            seq_b[2] = 9'h083;
            seq_b[3] = 9'h094;

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                stimulus_page[i] = symbol_t'(i[8:0]);
            end

            for (int rep = 0; rep < 4; rep++) begin
                int base;
                if (CHUNK_WIDTH >= 192) begin
                    base = 40 + rep * 48;
                end else begin
                    base = 2 + rep * 7;
                end
                for (int j = 0; j < 4; j++) begin
                    if ((base + j) < CHUNK_WIDTH) begin
                        stimulus_page[base + j] = seq_b[j];
                    end
                end
            end
        end
    endtask

    task automatic build_sparse_multi_iter_page;
        symbol_t seq_a [5];
        symbol_t seq_b [4];
        begin
            seq_a[0] = 9'h01a;
            seq_a[1] = 9'h02b;
            seq_a[2] = 9'h03c;
            seq_a[3] = 9'h04d;
            seq_a[4] = 9'h05e;

            seq_b[0] = 9'h061;
            seq_b[1] = 9'h072;
            seq_b[2] = 9'h083;
            seq_b[3] = 9'h094;

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                stimulus_page[i] = symbol_t'(i[8:0]);
            end

            for (int rep = 0; rep < ((CHUNK_WIDTH >= 256) ? 4 : 3); rep++) begin
                int base;
                if (CHUNK_WIDTH >= 256) begin
                    base = 16 + rep * 64;
                end else begin
                    base = rep * 10;
                end
                for (int j = 0; j < 5; j++) begin
                    if ((base + j) < CHUNK_WIDTH) begin
                        stimulus_page[base + j] = seq_a[j];
                    end
                end
            end

            for (int rep = 0; rep < ((CHUNK_WIDTH >= 256) ? 4 : 3); rep++) begin
                int base;
                if (CHUNK_WIDTH >= 256) begin
                    base = 48 + rep * 64;
                end else begin
                    base = 5 + rep * 10;
                end
                for (int j = 0; j < 4; j++) begin
                    if ((base + j) < CHUNK_WIDTH) begin
                        stimulus_page[base + j] = seq_b[j];
                    end
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        clear_inputs();

        reset_dut();
        build_unique_page();
        run_roundtrip_case("unique_page_passthrough", 0, 1'b0, 1'b0);

        reset_dut();
        build_pair_page();
        run_roundtrip_case("pair_len2_roundtrip", 1, 1'b1, 1'b1);

        reset_dut();
        build_sparse_len5_single_iter_page();
        run_roundtrip_case("sparse_len5_roundtrip", 1, 1'b1, 1'b0);

        reset_dut();
        build_sparse_len4_single_iter_page();
        run_roundtrip_case("sparse_len4_roundtrip", 1, 1'b1, 1'b0);

        reset_dut();
        build_sparse_multi_iter_page();
        run_roundtrip_case("sparse_multi_iter_roundtrip", 2, 1'b1, 1'b0);

        $display("tb_RoundTripTop passed");
        $finish;
    end
endmodule
