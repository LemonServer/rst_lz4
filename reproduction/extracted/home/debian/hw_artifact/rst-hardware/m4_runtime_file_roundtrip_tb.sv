`timescale 1ps / 1ps
`default_nettype none

module tb_M4RuntimeFileRoundTripTop;
    import rst_pkg::*;

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
    byte unsigned raw_page_bytes [0:PAGE_WIDTH-1];
    string input_file_arg;
    string vcd_file_arg;
    integer input_fd;
    int max_pages_arg;
    int expected_pages_arg;

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

    function automatic int pad_byte(input int page_idx, input int lane_idx);
        begin
            pad_byte = (page_idx * 73 + lane_idx * 29) & 8'h0ff;
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

    task automatic load_runtime_page(input int page_idx, input int valid_bytes);
        begin
            for (int lane = 0; lane < PAGE_WIDTH; lane++) begin
                if (lane < valid_bytes) begin
                    stimulus_page[lane] = symbol_t'(raw_page_bytes[lane]);
                end else begin
                    stimulus_page[lane] = symbol_t'(pad_byte(page_idx, lane));
                end
                page_in[lane] = stimulus_page[lane];
            end
        end
    endtask

    task run_file_harness;
        integer input_fd_local;
        int bytes_read_local;
        int pages_processed_local;
        int comp_cycles_local;
        int decomp_cycles_local;
        int comp_symbols_local;
        int dict_bits_local;
        int encoded_bits_local;
        int page_raw_bits_local;
        real page_ratio_local;
        real comp_bytes_per_cycle_local;
        real decomp_bytes_per_cycle_local;
        begin
            if (!$value$plusargs("INPUT_FILE=%s", input_file_arg)) begin
                $fatal(1, "missing +INPUT_FILE=/abs/path/to/file plusarg");
            end

            if (!$value$plusargs("MAX_PAGES=%d", max_pages_arg)) begin
                max_pages_arg = 0;
            end

            if (!$value$plusargs("EXPECT_PAGES=%d", expected_pages_arg)) begin
                expected_pages_arg = 0;
            end

            input_fd_local = $fopen(input_file_arg, "rb");
            if (input_fd_local == 0) begin
                $fatal(1, "failed to open input file %s", input_file_arg);
            end

            $display("[runtime file harness] input_file=%s max_pages=%0d expect_pages=%0d",
                input_file_arg, max_pages_arg, expected_pages_arg);

            pages_processed_local = 0;

            while ((max_pages_arg == 0) || (pages_processed_local < max_pages_arg)) begin
                reset_dut();

                for (int lane = 0; lane < PAGE_WIDTH; lane++) begin
                    raw_page_bytes[lane] = 8'h00;
                end

                bytes_read_local = $fread(raw_page_bytes, input_fd_local);
                if (bytes_read_local <= 0) begin
                    break;
                end

                load_runtime_page(pages_processed_local, bytes_read_local);

                pulse_compress_start();
                wait_compress_done(pages_processed_local, comp_cycles_local);

                comp_symbols_local = count_compressed_symbols();
                dict_bits_local = dict_packed_bits;
                encoded_bits_local = comp_symbols_local * 9 + dict_bits_local;
                page_raw_bits_local = bytes_read_local * RAW_BITS_PER_BYTE;
                page_ratio_local =
                    (encoded_bits_local > 0) ? (page_raw_bits_local * 1.0 / encoded_bits_local) : 0.0;
                comp_bytes_per_cycle_local = bytes_read_local * 1.0 / comp_cycles_local;

                pulse_decompress_start();
                wait_decompress_done(pages_processed_local, decomp_cycles_local);
                decomp_bytes_per_cycle_local = bytes_read_local * 1.0 / decomp_cycles_local;

                for (int i = 0; i < PAGE_WIDTH; i++) begin
                    if (decompressed_out[i] !== stimulus_page[i]) begin
                        $fatal(1, "page %0d decompressed_out[%0d] mismatch got=%0h expected=%0h",
                            pages_processed_local, i, decompressed_out[i], stimulus_page[i]);
                    end
                end

                pages_processed_local++;

                if (expected_pages_arg > 0) begin
                    $display("[page %0d/%0d] valid_bytes=%0d comp_syms=%0d dict_count=%0d dict_bits=%0d raw_bits=%0d encoded_bits=%0d ratio=%0.4f comp_cycles=%0d decomp_cycles=%0d comp_Bpc=%0.4f decomp_Bpc=%0.4f",
                        pages_processed_local, expected_pages_arg, bytes_read_local, comp_symbols_local,
                        dict_count, dict_bits_local, page_raw_bits_local, encoded_bits_local,
                        page_ratio_local, comp_cycles_local, decomp_cycles_local,
                        comp_bytes_per_cycle_local, decomp_bytes_per_cycle_local);
                end else begin
                    $display("[page %0d] valid_bytes=%0d comp_syms=%0d dict_count=%0d dict_bits=%0d raw_bits=%0d encoded_bits=%0d ratio=%0.4f comp_cycles=%0d decomp_cycles=%0d comp_Bpc=%0.4f decomp_Bpc=%0.4f",
                        pages_processed_local, bytes_read_local, comp_symbols_local, dict_count, dict_bits_local,
                        page_raw_bits_local, encoded_bits_local, page_ratio_local,
                        comp_cycles_local, decomp_cycles_local,
                        comp_bytes_per_cycle_local, decomp_bytes_per_cycle_local);
                end
            end

            $fclose(input_fd_local);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        clear_inputs();

        if ($value$plusargs("VCD_FILE=%s", vcd_file_arg)) begin
            $display("[vcd] dumping to %s", vcd_file_arg);
            $dumpfile(vcd_file_arg);
            $dumpvars(0, tb_M4RuntimeFileRoundTripTop);
        end

        run_file_harness();
        $display("tb_M4RuntimeFileRoundTripTop passed");
        $finish;
    end
endmodule
