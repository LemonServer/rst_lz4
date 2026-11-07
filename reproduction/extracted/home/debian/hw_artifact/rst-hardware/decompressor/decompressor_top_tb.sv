`timescale 1ps / 1ps
`default_nettype none

module tb_DecompressorTop;
    import rst_pkg::*;

    localparam int CLK_HALF = 5;
    localparam int TIMEOUT_CYCLES = 32;

    logic clk;
    logic rst;
    logic start;
    vsym_t compressed_in [CHUNK_WIDTH];
    seq_t dict_seqs [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens [MAX_DICT_ENTRIES];
    dict_count_t dict_count;
    dict_packed_t dict_packed;
    dict_bit_count_t dict_packed_bits;
    symbol_t decompressed_out [CHUNK_WIDTH];
    logic done;
    symbol_t expected [0:CHUNK_WIDTH-1];

    DictSerializer dict_serializer (
        .dict_count(dict_count),
        .dict_seqs(dict_seqs),
        .dict_lens(dict_lens),
        .dict_packed(dict_packed),
        .dict_packed_bits(dict_packed_bits)
    );

    DecompressorTop dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .compressed_in(compressed_in),
        .dict_packed(dict_packed),
        .decompressed_out(decompressed_out),
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
            code_sym = symbol_t'(9'h100 + idx);
        end
    endfunction

    task automatic clear_stimulus;
        begin
            start = 1'b0;
            dict_count = '0;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                compressed_in[i] = '0;
                expected[i] = '0;
            end
            for (int i = 0; i < MAX_DICT_ENTRIES; i++) begin
                dict_seqs[i] = '0;
                dict_lens[i] = '0;
            end
        end
    endtask

    task automatic reset_dut;
        begin
            clear_stimulus();
            rst = 1'b1;
            repeat (3) @(posedge clk);
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

    task automatic wait_done(input string case_name, output int cycles);
        begin
            cycles = 0;
            while (!done && cycles < TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycles++;
            end
            if (!done) begin
                $fatal(1, "%s timed out waiting for done", case_name);
            end
            $display("%s completed in %0d cycles", case_name, cycles);
        end
    endtask

    task automatic expect_output(input string case_name, input int expected_count);
        begin
            if (dut.total_out_count_dbg != expected_count) begin
                $fatal(1, "%s output count mismatch got=%0d expected=%0d",
                    case_name, dut.total_out_count_dbg, expected_count);
            end
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                symbol_t want;
                want = (i < expected_count) ? expected[i] : '0;
                if (decompressed_out[i] !== want) begin
                    $fatal(1, "%s decompressed_out[%0d] mismatch got=%0h expected=%0h",
                        case_name, i, decompressed_out[i], want);
                end
            end
        end
    endtask

    task automatic run_spatial_segmentation_case;
        int cycles;
        begin
            reset_dut();

            dict_count = 4;
            dict_lens[0] = 3'd2;
            dict_seqs[0][0] = literal_sym("A");
            dict_seqs[0][1] = literal_sym("B");
            dict_lens[1] = 3'd2;
            dict_seqs[1][0] = literal_sym("C");
            dict_seqs[1][1] = literal_sym("D");
            dict_lens[2] = 3'd2;
            dict_seqs[2][0] = literal_sym("P");
            dict_seqs[2][1] = literal_sym("Q");
            dict_lens[3] = 3'd2;
            dict_seqs[3][0] = literal_sym("S");
            dict_seqs[3][1] = literal_sym("T");

            compressed_in[0] = '{sym: code_sym(0), valid: 1'b1};
            compressed_in[1] = '{sym: literal_sym("m"), valid: 1'b1};
            compressed_in[2] = '{sym: code_sym(1), valid: 1'b1};
            compressed_in[3] = '{sym: literal_sym("n"), valid: 1'b1};
            compressed_in[4] = '{sym: literal_sym("o"), valid: 1'b1};
            compressed_in[5] = '{sym: code_sym(2), valid: 1'b1};
            compressed_in[6] = '{sym: literal_sym("r"), valid: 1'b1};
            compressed_in[7] = '{sym: code_sym(3), valid: 1'b1};
            compressed_in[8] = '{sym: literal_sym("u"), valid: 1'b1};
            compressed_in[9] = '{sym: literal_sym("v"), valid: 1'b1};

            expected[0] = literal_sym("A");
            expected[1] = literal_sym("B");
            expected[2] = literal_sym("m");
            expected[3] = literal_sym("C");
            expected[4] = literal_sym("D");
            expected[5] = literal_sym("n");
            expected[6] = literal_sym("o");
            expected[7] = literal_sym("P");
            expected[8] = literal_sym("Q");
            expected[9] = literal_sym("r");
            expected[10] = literal_sym("S");
            expected[11] = literal_sym("T");
            expected[12] = literal_sym("u");
            expected[13] = literal_sym("v");

            #1;
            if (dut.valid_count_dbg != 10) begin
                $fatal(1, "spatial_segmentation valid_count mismatch got=%0d expected=10",
                    dut.valid_count_dbg);
            end
            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                int expected_seg_len;

                expected_seg_len = (10 / DECOMP_LIFOS) + ((seg < (10 % DECOMP_LIFOS)) ? 1 : 0);
                if (dut.segment_comp_counts_dbg[seg] != expected_seg_len) begin
                    $fatal(1, "spatial_segmentation segment_comp_counts_dbg[%0d] mismatch got=%0d expected=%0d",
                        seg, dut.segment_comp_counts_dbg[seg], expected_seg_len);
                end
            end

            pulse_start();
            wait_done("spatial_segmentation", cycles);

            if (DECOMP_LIFOS == 8) begin
                int expected_counts [0:7];

                expected_counts[0] = 3;
                expected_counts[1] = 3;
                expected_counts[2] = 1;
                expected_counts[3] = 2;
                expected_counts[4] = 1;
                expected_counts[5] = 2;
                expected_counts[6] = 1;
                expected_counts[7] = 1;

                for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                    if (dut.segmented_out_counts[seg] != expected_counts[seg]) begin
                        $fatal(1, "spatial_segmentation output count[%0d] mismatch got=%0d expected=%0d",
                            seg, dut.segmented_out_counts[seg], expected_counts[seg]);
                    end
                end
            end else begin
                int total_seg_outs;

                total_seg_outs = 0;
                for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                    total_seg_outs += dut.segmented_out_counts[seg];
                end
                if (total_seg_outs != 14) begin
                    $fatal(1, "spatial_segmentation total segmented outputs mismatch got=%0d expected=14",
                        total_seg_outs);
                end
            end

            expect_output("spatial_segmentation", 14);
            $display("spatial_segmentation completed in %0d cycles", cycles);
        end
    endtask

    task automatic run_nested_segment_case;
        int cycles;
        begin
            reset_dut();

            dict_count = 4;
            dict_lens[0] = 3'd2;
            dict_seqs[0][0] = literal_sym("A");
            dict_seqs[0][1] = code_sym(1);
            dict_lens[1] = 3'd2;
            dict_seqs[1][0] = literal_sym("B");
            dict_seqs[1][1] = literal_sym("C");
            dict_lens[2] = 3'd2;
            dict_seqs[2][0] = literal_sym("D");
            dict_seqs[2][1] = code_sym(3);
            dict_lens[3] = 3'd2;
            dict_seqs[3][0] = literal_sym("E");
            dict_seqs[3][1] = literal_sym("F");

            compressed_in[0] = '{sym: code_sym(0), valid: 1'b1};
            compressed_in[1] = '{sym: literal_sym("x"), valid: 1'b1};
            compressed_in[2] = '{sym: code_sym(2), valid: 1'b1};
            compressed_in[3] = '{sym: literal_sym("y"), valid: 1'b1};
            compressed_in[4] = '{sym: code_sym(1), valid: 1'b1};
            compressed_in[5] = '{sym: literal_sym("z"), valid: 1'b1};
            compressed_in[6] = '{sym: code_sym(3), valid: 1'b1};
            compressed_in[7] = '{sym: literal_sym("p"), valid: 1'b1};
            compressed_in[8] = '{sym: literal_sym("q"), valid: 1'b1};

            expected[0] = literal_sym("A");
            expected[1] = literal_sym("B");
            expected[2] = literal_sym("C");
            expected[3] = literal_sym("x");
            expected[4] = literal_sym("D");
            expected[5] = literal_sym("E");
            expected[6] = literal_sym("F");
            expected[7] = literal_sym("y");
            expected[8] = literal_sym("B");
            expected[9] = literal_sym("C");
            expected[10] = literal_sym("z");
            expected[11] = literal_sym("E");
            expected[12] = literal_sym("F");
            expected[13] = literal_sym("p");
            expected[14] = literal_sym("q");

            pulse_start();

            if (DECOMP_LIFOS == 8) begin
                @(posedge clk);
                if (dut.gen_lifos[0].lifo_expander.sp_r != 2) begin
                    $fatal(1, "nested_segment load mismatch sp=%0d expected=2",
                        dut.gen_lifos[0].lifo_expander.sp_r);
                end

                @(posedge clk);
                if (dut.gen_lifos[0].lifo_expander.out_count_r != 0) begin
                    $fatal(1, "nested_segment should stall outputs on code/literal boundary");
                end
                if (dut.gen_lifos[0].lifo_expander.sp_r != 3) begin
                    $fatal(1, "nested_segment stack depth mismatch got=%0d expected=3",
                        dut.gen_lifos[0].lifo_expander.sp_r);
                end
                if (dut.gen_lifos[0].lifo_expander.stack_mem_r[2] !== literal_sym("A") ||
                    dut.gen_lifos[0].lifo_expander.stack_mem_r[1] !== code_sym(1) ||
                    dut.gen_lifos[0].lifo_expander.stack_mem_r[0] !== literal_sym("x")) begin
                    $fatal(1, "nested_segment stack contents mismatch after restricted cycle");
                end
            end

            wait_done("nested_segment", cycles);

            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                int expected_seg_len;

                expected_seg_len = (9 / DECOMP_LIFOS) + ((seg < (9 % DECOMP_LIFOS)) ? 1 : 0);
                if (dut.segment_comp_counts_dbg[seg] != expected_seg_len) begin
                    $fatal(1, "nested_segment segment_comp_counts_dbg[%0d] mismatch got=%0d expected=%0d",
                        seg, dut.segment_comp_counts_dbg[seg], expected_seg_len);
                end
            end

            if (DECOMP_LIFOS == 8) begin
                int expected_counts [0:7];

                expected_counts[0] = 4;
                expected_counts[1] = 3;
                expected_counts[2] = 1;
                expected_counts[3] = 2;
                expected_counts[4] = 1;
                expected_counts[5] = 2;
                expected_counts[6] = 1;
                expected_counts[7] = 1;

                for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                    if (dut.segmented_out_counts[seg] != expected_counts[seg]) begin
                        $fatal(1, "nested_segment output count[%0d] mismatch got=%0d expected=%0d",
                            seg, dut.segmented_out_counts[seg], expected_counts[seg]);
                    end
                end
            end else begin
                int total_seg_outs;

                total_seg_outs = 0;
                for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                    total_seg_outs += dut.segmented_out_counts[seg];
                end
                if (total_seg_outs != 15) begin
                    $fatal(1, "nested_segment total segmented outputs mismatch got=%0d expected=15",
                        total_seg_outs);
                end
            end

            expect_output("nested_segment", 15);
            $display("nested_segment completed in %0d cycles", cycles);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        clear_stimulus();

        run_spatial_segmentation_case();
        run_nested_segment_case();

        $display("tb_DecompressorTop passed");
        $finish;
    end
endmodule
