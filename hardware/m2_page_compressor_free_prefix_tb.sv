`timescale 1ps / 1ps
`default_nettype none

module tb_M2PageCompressorFreePrefix;
    import rst_pkg::*;

    localparam int CLK_HALF = 5;
    localparam int TIMEOUT_CYCLES = 20000;
    localparam int INITIAL_DICT_SPACE_BITS = MEMORY_BLOCKS * 64 * 8 - 6;

    logic clk;
    logic rst;
    logic start;
    symbol_t page_in [PAGE_WIDTH];
    vsym_t compressed_out [PAGE_WIDTH];
    seq_t dict_seqs [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens [MAX_DICT_ENTRIES];
    dict_count_t dict_count;
    dict_packed_t dict_packed;
    dict_bit_count_t dict_packed_bits;
    logic done;

    symbol_t stimulus_page [PAGE_WIDTH];

    PageCompressorTop dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .page_in(page_in),
        .compressed_out(compressed_out),
        .dict_seqs(dict_seqs),
        .dict_lens(dict_lens),
        .dict_count(dict_count),
        .dict_packed(dict_packed),
        .dict_packed_bits(dict_packed_bits),
        .done(done)
    );

    always #(CLK_HALF) clk = ~clk;

    function automatic symbol_t literal_sym(input int value);
        begin
            literal_sym = symbol_t'(value & 9'h0ff);
        end
    endfunction

    function automatic symbol_t code_sym(input int idx);
        begin
            code_sym = dict_code_symbol(dict_count_t'(idx));
        end
    endfunction

    function automatic int count_compressed_symbols;
        int count;
        begin
            count = 0;
            for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
                if (compressed_out[idx].valid) begin
                    count++;
                end
            end
            return count;
        end
    endfunction

    task automatic load_page;
        begin
            for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
                page_in[idx] = stimulus_page[idx];
            end
        end
    endtask

    task automatic reset_dut;
        begin
            rst = 1'b1;
            start = 1'b0;
            for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
                page_in[idx] = '0;
            end
            repeat (4) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic pulse_start;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic wait_done(input string case_name);
        int cycles;
        begin
            cycles = 0;
            while (!done && cycles < TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycles++;
            end
            if (!done) begin
                $fatal(1, "%s timed out waiting for compressor done", case_name);
            end
        end
    endtask

    task automatic expect_free_seed_prefix(input string case_name);
        begin
            if (dict_count < 2) begin
                $fatal(1, "%s expected at least two seeded substitutions, got dict_count=%0d", case_name, dict_count);
            end
            if ((dict_lens[0] != 3'd2) ||
                (dict_seqs[0][0] != literal_sym(0)) ||
                (dict_seqs[0][1] != literal_sym(0))) begin
                $fatal(1, "%s dict[0] mismatch len=%0d seq=%h", case_name, dict_lens[0], dict_seqs[0]);
            end
            if ((dict_lens[1] != 3'd2) ||
                (dict_seqs[1][0] != code_sym(0)) ||
                (dict_seqs[1][1] != code_sym(0))) begin
                $fatal(1, "%s dict[1] mismatch len=%0d seq=%h", case_name, dict_lens[1], dict_seqs[1]);
            end
        end
    endtask

    task automatic build_unique_page;
        begin
            for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
                stimulus_page[idx] = literal_sym(idx);
            end
        end
    endtask

    task automatic build_zero_page;
        begin
            for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
                stimulus_page[idx] = literal_sym(0);
            end
        end
    endtask

    task automatic run_unique_case;
        begin
            build_unique_page();
            reset_dut();
            load_page();
            pulse_start();
            wait_done("unique_no_matches");
            expect_free_seed_prefix("unique_no_matches");

            if (dict_count !== dict_count_t'(2)) begin
                $fatal(1, "unique_no_matches expected dict_count=2 got=%0d", dict_count);
            end
            if (dut.dict_space_bits_r !== INITIAL_DICT_SPACE_BITS) begin
                $fatal(1, "unique_no_matches free seeds consumed space got=%0d expected=%0d",
                    dut.dict_space_bits_r, INITIAL_DICT_SPACE_BITS);
            end
            if (count_compressed_symbols() != PAGE_WIDTH) begin
                $fatal(1, "unique_no_matches changed symbol count got=%0d expected=%0d",
                    count_compressed_symbols(), PAGE_WIDTH);
            end

            for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
                if (!compressed_out[idx].valid || (compressed_out[idx].sym != stimulus_page[idx])) begin
                    $fatal(1, "unique_no_matches compressed_out[%0d] mismatch got={%0d,%0b} expected=%0d",
                        idx, compressed_out[idx].sym, compressed_out[idx].valid, stimulus_page[idx]);
                end
            end
        end
    endtask

    task automatic run_zero_case;
        begin
            build_zero_page();
            reset_dut();
            load_page();
            pulse_start();
            wait_done("all_zero_nested");
            expect_free_seed_prefix("all_zero_nested");

            if (dict_count !== dict_count_t'(4)) begin
                $fatal(1, "all_zero_nested expected dict_count=4 got=%0d", dict_count);
            end

            if ((dict_lens[2] != 3'd3) ||
                (dict_seqs[2][0] != code_sym(1)) ||
                (dict_seqs[2][1] != code_sym(1)) ||
                (dict_seqs[2][2] != code_sym(1))) begin
                $fatal(1, "all_zero_nested dict[2] mismatch len=%0d seq=%h",
                    dict_lens[2], dict_seqs[2]);
            end

            if ((dict_lens[3] != 3'd4) ||
                (dict_seqs[3][0] != code_sym(2)) ||
                (dict_seqs[3][1] != code_sym(2)) ||
                (dict_seqs[3][2] != code_sym(1)) ||
                (dict_seqs[3][3] != code_sym(1))) begin
                $fatal(1, "all_zero_nested dict[3] mismatch len=%0d seq=%h",
                    dict_lens[3], dict_seqs[3]);
            end

            if (dut.dict_space_bits_r !== (INITIAL_DICT_SPACE_BITS - 8'd39)) begin
                $fatal(1, "all_zero_nested unexpected dict space got=%0d expected=%0d",
                    dut.dict_space_bits_r,
                    INITIAL_DICT_SPACE_BITS - 8'd39);
            end
            if (count_compressed_symbols() != 2) begin
                $fatal(1, "all_zero_nested expected 2 compressed symbols got=%0d", count_compressed_symbols());
            end
            for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
                if (compressed_out[idx].valid && (compressed_out[idx].sym != code_sym(3))) begin
                    $fatal(1, "all_zero_nested expected valid compressed_out[%0d]=code3 got=%0d",
                        idx, compressed_out[idx].sym);
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;

        run_unique_case();
        run_zero_case();

        $display("PASS tb_M2PageCompressorFreePrefix");
        $finish;
    end
endmodule
