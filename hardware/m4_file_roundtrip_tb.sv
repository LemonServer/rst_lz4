`timescale 1ps / 1ps
`default_nettype none

module tb_M4FileRoundTripTop;
    import rst_pkg::*;

`ifndef M4_FILE_INPUT_INCLUDE
`define M4_FILE_INPUT_INCLUDE "m4_generated_file_pages.svh"
`endif

    localparam int CLK_HALF = 5;
    localparam int COMP_TIMEOUT_CYCLES = 100000;
    localparam int DECOMP_TIMEOUT_CYCLES = 100000;
    localparam int RAW_BITS_PER_BYTE = 8;

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

`include `M4_FILE_INPUT_INCLUDE

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

    task automatic wait_compress_done(input int page_idx, output int cycles);
        begin
            cycles = 0;
            while (!compress_done && cycles < COMP_TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycles++;
            end
            if (!compress_done) begin
                $fatal(1, "page %0d timed out waiting for page compressor done", page_idx);
            end
        end
    endtask

    task automatic wait_decompress_done(input int page_idx, output int cycles);
        begin
            cycles = 0;
            while (!decompress_done && cycles < DECOMP_TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycles++;
            end
            if (!decompress_done) begin
                $fatal(1, "page %0d timed out waiting for page decompressor done", page_idx);
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

    task automatic run_file_harness;
        int valid_bytes;
        int comp_cycles;
        int decomp_cycles;
        int comp_symbols;
        int dict_bits;
        int encoded_bits;
        int total_comp_cycles;
        int total_decomp_cycles;
        int total_cycles;
        int total_encoded_bits;
        int total_raw_bits;
        int page_raw_bits;
        real page_ratio;
        real comp_bytes_per_cycle;
        real decomp_bytes_per_cycle;
        real total_ratio;
        real total_comp_bytes_per_cycle;
        real total_decomp_bytes_per_cycle;
        begin
            if (FILE_NUM_PAGES <= 0) begin
                $fatal(1, "FILE_NUM_PAGES must be > 0");
            end

            total_comp_cycles = 0;
            total_decomp_cycles = 0;
            total_encoded_bits = 0;
            total_raw_bits = FILE_INPUT_BYTES * RAW_BITS_PER_BYTE;

            for (int page_idx = 0; page_idx < FILE_NUM_PAGES; page_idx++) begin
                reset_dut();
                load_generated_page(page_idx, stimulus_page, valid_bytes);

                for (int i = 0; i < PAGE_WIDTH; i++) begin
                    page_in[i] = stimulus_page[i];
                end

                pulse_compress_start();
                wait_compress_done(page_idx, comp_cycles);

                comp_symbols = count_compressed_symbols();
                dict_bits = dict_packed_bits;
                encoded_bits = comp_symbols * 9 + dict_bits;
                page_raw_bits = valid_bytes * RAW_BITS_PER_BYTE;
                page_ratio = page_raw_bits * 1.0 / encoded_bits;
                comp_bytes_per_cycle = valid_bytes * 1.0 / comp_cycles;

                pulse_decompress_start();
                wait_decompress_done(page_idx, decomp_cycles);
                decomp_bytes_per_cycle = valid_bytes * 1.0 / decomp_cycles;

                for (int i = 0; i < PAGE_WIDTH; i++) begin
                    if (decompressed_out[i] !== stimulus_page[i]) begin
                        $fatal(1, "page %0d decompressed_out[%0d] mismatch got=%0h expected=%0h",
                            page_idx, i, decompressed_out[i], stimulus_page[i]);
                    end
                end

                total_comp_cycles += comp_cycles;
                total_decomp_cycles += decomp_cycles;
                total_encoded_bits += encoded_bits;

                $display("[page %0d/%0d] valid_bytes=%0d comp_syms=%0d dict_count=%0d dict_bits=%0d raw_bits=%0d encoded_bits=%0d ratio=%0.4f comp_cycles=%0d decomp_cycles=%0d comp_Bpc=%0.4f decomp_Bpc=%0.4f",
                    page_idx + 1, FILE_NUM_PAGES, valid_bytes, comp_symbols, dict_count, dict_bits,
                    page_raw_bits, encoded_bits, page_ratio,
                    comp_cycles, decomp_cycles, comp_bytes_per_cycle, decomp_bytes_per_cycle);
            end

            total_cycles = total_comp_cycles + total_decomp_cycles;
            total_ratio = total_raw_bits * 1.0 / total_encoded_bits;
            total_comp_bytes_per_cycle = FILE_INPUT_BYTES * 1.0 / total_comp_cycles;
            total_decomp_bytes_per_cycle = FILE_INPUT_BYTES * 1.0 / total_decomp_cycles;

            $display("[file summary] input_bytes=%0d padded_bytes=%0d pages=%0d raw_bits=%0d encoded_bits=%0d ratio=%0.4f comp_cycles=%0d decomp_cycles=%0d total_cycles=%0d comp_Bpc=%0.4f decomp_Bpc=%0.4f",
                FILE_INPUT_BYTES, FILE_PADDED_BYTES, FILE_NUM_PAGES, total_raw_bits,
                total_encoded_bits, total_ratio, total_comp_cycles, total_decomp_cycles,
                total_cycles, total_comp_bytes_per_cycle, total_decomp_bytes_per_cycle);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        clear_inputs();
        run_file_harness();
        $display("tb_M4FileRoundTripTop passed");
        $finish;
    end
endmodule
