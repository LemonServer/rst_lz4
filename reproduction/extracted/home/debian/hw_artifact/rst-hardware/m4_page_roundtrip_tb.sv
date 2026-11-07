`timescale 1ps / 1ps
`default_nettype none

module tb_M4PageRoundTripTop;
    import rst_pkg::*;

    localparam int CLK_HALF = 5;
`ifdef M4_PAGE_COMP_TIMEOUT_CYCLES
    localparam int COMP_TIMEOUT_CYCLES = `M4_PAGE_COMP_TIMEOUT_CYCLES;
`else
    localparam int COMP_TIMEOUT_CYCLES = 100000;
`endif
`ifdef M4_PAGE_DECOMP_TIMEOUT_CYCLES
    localparam int DECOMP_TIMEOUT_CYCLES = `M4_PAGE_DECOMP_TIMEOUT_CYCLES;
`else
    localparam int DECOMP_TIMEOUT_CYCLES = 100000;
`endif
    localparam int RAW_PAGE_BITS = PAGE_WIDTH * 8;

    logic clk;
    logic rst;
    logic compress_start;
    logic decompress_start;
    symbol_t page_in [PAGE_WIDTH];
    vsym_t compressed_out [PAGE_WIDTH];
    seq_t dict_seqs [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens [MAX_DICT_ENTRIES];
    dict_count_t dict_count;
    dict_packed_t dict_packed;
    dict_bit_count_t dict_packed_bits;
    logic compress_done;
    symbol_t decompressed_out [PAGE_WIDTH];
    logic decompress_done;

    symbol_t stimulus_page [PAGE_WIDTH];

    PageCompressorTop compressor_dut (
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

    PageDecompressorTop decompressor_dut (
        .clk(clk),
        .rst(rst),
        .start(decompress_start),
        .compressed_in(compressed_out),
        .dict_packed(dict_packed),
        .decompressed_out(decompressed_out),
        .done(decompress_done)
    );

    always #(CLK_HALF) clk = ~clk;

    function automatic symbol_t literal_sym(input int value);
        begin
            literal_sym = symbol_t'(value & 8'h0ff);
        end
    endfunction

    task automatic clear_inputs;
        begin
            compress_start = 1'b0;
            decompress_start = 1'b0;
            for (int i = 0; i < PAGE_WIDTH; i++) begin
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
            for (int i = 0; i < PAGE_WIDTH; i++) begin
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
                $fatal(1, "%s timed out waiting for page compressor done", case_name);
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
                $fatal(1, "%s timed out waiting for page decompressor done", case_name);
            end
        end
    endtask

    function automatic int count_compressed_symbols;
        int count;
        begin
            count = 0;
            for (int i = 0; i < PAGE_WIDTH; i++) begin
                if (compressed_out[i].valid) begin
                    count++;
                end
            end
            return count;
        end
    endfunction

    function automatic int count_chunk_compressed_symbols(input int chunk_idx);
        int count;
        int base_idx;
        begin
            count = 0;
            base_idx = chunk_idx * CHUNK_WIDTH;
            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                if (compressed_out[base_idx + lane].valid) begin
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

    task automatic log_page_summary(
        input string case_name,
        input int comp_cycles,
        input int decomp_cycles
    );
        int comp_symbols;
        int dict_bits;
        int encoded_bits;
        int dict_entries;
        real ratio;
        real comp_bytes_per_cycle;
        real decomp_bytes_per_cycle;
        begin
            comp_symbols = count_compressed_symbols();
            dict_bits = dict_packed_bits;
            encoded_bits = comp_symbols * 9 + dict_bits;
            dict_entries = dict_count;
            ratio = RAW_PAGE_BITS * 1.0 / encoded_bits;
            comp_bytes_per_cycle = PAGE_WIDTH * 1.0 / comp_cycles;
            decomp_bytes_per_cycle = PAGE_WIDTH * 1.0 / decomp_cycles;

            $display("[%s] comp_cycles=%0d decomp_cycles=%0d dict_count=%0d comp_syms=%0d dict_bits=%0d raw_bits=%0d total_bits=%0d ratio=%0.4f comp_Bpc=%0.4f decomp_Bpc=%0.4f",
                case_name, comp_cycles, decomp_cycles, dict_entries, comp_symbols, dict_bits,
                RAW_PAGE_BITS, encoded_bits, ratio, comp_bytes_per_cycle, decomp_bytes_per_cycle);
            for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                $display("  chunk[%0d] comp_syms=%0d",
                    chunk, count_chunk_compressed_symbols(chunk));
            end
        end
    endtask

    task automatic run_roundtrip_case(
        input string case_name,
        input int min_total_dict_entries,
        input bit expect_substitution,
        input bit expect_ratio_gt_one
    );
        int comp_cycles;
        int decomp_cycles;
        int comp_symbols;
        int dict_bits;
        int encoded_bits;
        int dict_entries;
        begin
            load_page_into_dut();

            pulse_compress_start();
            wait_compress_done(case_name, comp_cycles);

            comp_symbols = count_compressed_symbols();
            dict_bits = dict_packed_bits;
            encoded_bits = comp_symbols * 9 + dict_bits;
            dict_entries = dict_count;

            if (dict_entries < min_total_dict_entries) begin
                $fatal(1, "%s dict entry count too small got=%0d expected_at_least=%0d",
                    case_name, dict_entries, min_total_dict_entries);
            end

            if (expect_substitution && (comp_symbols >= PAGE_WIDTH)) begin
                $fatal(1, "%s did not reduce compressed symbol count got=%0d raw=%0d",
                    case_name, comp_symbols, PAGE_WIDTH);
            end

            if (expect_ratio_gt_one && (encoded_bits >= RAW_PAGE_BITS)) begin
                $fatal(1, "%s did not reduce total encoded bits got=%0d raw=%0d",
                    case_name, encoded_bits, RAW_PAGE_BITS);
            end

            pulse_decompress_start();
            wait_decompress_done(case_name, decomp_cycles);

            for (int i = 0; i < PAGE_WIDTH; i++) begin
                if (decompressed_out[i] !== stimulus_page[i]) begin
                    $fatal(1, "%s decompressed_out[%0d] mismatch got=%0h expected=%0h",
                        case_name, i, decompressed_out[i], stimulus_page[i]);
                end
            end

            log_page_summary(case_name, comp_cycles, decomp_cycles);
        end
    endtask

    task automatic fill_identical_unique_chunk(input int chunk_idx);
        int base_idx;
        begin
            base_idx = chunk_idx * CHUNK_WIDTH;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                stimulus_page[base_idx + i] = literal_sym(i);
            end
        end
    endtask

    task automatic fill_seeded_unique_chunk(input int chunk_idx, input int seed);
        int base_idx;
        begin
            base_idx = chunk_idx * CHUNK_WIDTH;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                stimulus_page[base_idx + i] = literal_sym(seed + i * 29);
            end
        end
    endtask

    task automatic fill_pair_chunk(input int chunk_idx, input int seed);
        int base_idx;
        symbol_t a_sym;
        symbol_t b_sym;
        begin
            base_idx = chunk_idx * CHUNK_WIDTH;
            a_sym = literal_sym(8'h021 + seed * 7);
            b_sym = literal_sym(8'h02b + seed * 11);
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                case (i % 3)
                    0: stimulus_page[base_idx + i] = a_sym;
                    1: stimulus_page[base_idx + i] = b_sym;
                    default: stimulus_page[base_idx + i] = literal_sym(8'h080 + seed * 13 + (i / 3));
                endcase
            end
        end
    endtask

    task automatic fill_sparse_len5_chunk(input int chunk_idx, input int seed);
        int base_idx;
        symbol_t seq_a [5];
        begin
            base_idx = chunk_idx * CHUNK_WIDTH;
            seq_a[0] = literal_sym(8'h01a + seed * 3);
            seq_a[1] = literal_sym(8'h02b + seed * 5);
            seq_a[2] = literal_sym(8'h03c + seed * 7);
            seq_a[3] = literal_sym(8'h04d + seed * 9);
            seq_a[4] = literal_sym(8'h05e + seed * 11);

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                stimulus_page[base_idx + i] = literal_sym(seed * 17 + i * 29);
            end

            for (int rep = 0; rep < 4; rep++) begin
                int rep_base;
                if (CHUNK_WIDTH >= 192) begin
                    rep_base = 24 + rep * 56;
                end else begin
                    rep_base = rep * 8;
                end
                for (int j = 0; j < 5; j++) begin
                    if ((rep_base + j) < CHUNK_WIDTH) begin
                        stimulus_page[base_idx + rep_base + j] = seq_a[j];
                    end
                end
            end
        end
    endtask

    task automatic fill_sparse_len4_chunk(input int chunk_idx, input int seed);
        int base_idx;
        symbol_t seq_b [4];
        begin
            base_idx = chunk_idx * CHUNK_WIDTH;
            seq_b[0] = literal_sym(8'h061 + seed * 3);
            seq_b[1] = literal_sym(8'h072 + seed * 5);
            seq_b[2] = literal_sym(8'h083 + seed * 7);
            seq_b[3] = literal_sym(8'h094 + seed * 9);

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                stimulus_page[base_idx + i] = literal_sym(seed * 19 + i * 29);
            end

            for (int rep = 0; rep < 4; rep++) begin
                int rep_base;
                if (CHUNK_WIDTH >= 192) begin
                    rep_base = 40 + rep * 48;
                end else begin
                    rep_base = 2 + rep * 7;
                end
                for (int j = 0; j < 4; j++) begin
                    if ((rep_base + j) < CHUNK_WIDTH) begin
                        stimulus_page[base_idx + rep_base + j] = seq_b[j];
                    end
                end
            end
        end
    endtask

    task automatic fill_sparse_multi_iter_chunk(input int chunk_idx, input int seed);
        int base_idx;
        symbol_t seq_a [5];
        symbol_t seq_b [4];
        begin
            base_idx = chunk_idx * CHUNK_WIDTH;
            seq_a[0] = literal_sym(8'h01a + seed * 3);
            seq_a[1] = literal_sym(8'h02b + seed * 5);
            seq_a[2] = literal_sym(8'h03c + seed * 7);
            seq_a[3] = literal_sym(8'h04d + seed * 9);
            seq_a[4] = literal_sym(8'h05e + seed * 11);

            seq_b[0] = literal_sym(8'h061 + seed * 13);
            seq_b[1] = literal_sym(8'h072 + seed * 15);
            seq_b[2] = literal_sym(8'h083 + seed * 17);
            seq_b[3] = literal_sym(8'h094 + seed * 19);

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                stimulus_page[base_idx + i] = literal_sym(seed * 23 + i * 29);
            end

            for (int rep = 0; rep < ((CHUNK_WIDTH >= 256) ? 4 : 3); rep++) begin
                int rep_base;
                if (CHUNK_WIDTH >= 256) begin
                    rep_base = 16 + rep * 64;
                end else begin
                    rep_base = rep * 10;
                end
                for (int j = 0; j < 5; j++) begin
                    if ((rep_base + j) < CHUNK_WIDTH) begin
                        stimulus_page[base_idx + rep_base + j] = seq_a[j];
                    end
                end
            end

            for (int rep = 0; rep < ((CHUNK_WIDTH >= 256) ? 4 : 3); rep++) begin
                int rep_base;
                if (CHUNK_WIDTH >= 256) begin
                    rep_base = 48 + rep * 64;
                end else begin
                    rep_base = 5 + rep * 10;
                end
                for (int j = 0; j < 4; j++) begin
                    if ((rep_base + j) < CHUNK_WIDTH) begin
                        stimulus_page[base_idx + rep_base + j] = seq_b[j];
                    end
                end
            end
        end
    endtask

    task automatic build_ordered_unique_page;
        begin
            for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                fill_seeded_unique_chunk(chunk, chunk * 17);
            end
        end
    endtask

    task automatic build_pair_page;
        begin
            for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                fill_pair_chunk(chunk, 1);
            end
        end
    endtask

    task automatic build_mixed_chunk_page;
        begin
            for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                case (chunk % 4)
                    0: fill_pair_chunk(chunk, chunk + 1);
                    1: fill_sparse_len5_chunk(chunk, chunk + 1);
                    2: fill_sparse_len4_chunk(chunk, chunk + 1);
                    default: fill_sparse_multi_iter_chunk(chunk, chunk + 1);
                endcase
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        clear_inputs();

        reset_dut();
        build_ordered_unique_page();
        run_roundtrip_case("ordered_unique_page_passthrough", 0, 1'b0, 1'b0);

        reset_dut();
        build_pair_page();
        run_roundtrip_case("pair_page_roundtrip", 1, 1'b1, 1'b1);

        reset_dut();
        build_mixed_chunk_page();
        run_roundtrip_case("mixed_chunk_page_roundtrip", 2, 1'b1, 1'b0);

        $display("tb_M4PageRoundTripTop passed");
        $finish;
    end
endmodule
