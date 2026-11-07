`timescale 1ps / 1ps
`default_nettype none

module tb_ExperimentalDecompressorTop;
    import rst_pkg::*;

    localparam int CLK_HALF = 5;
    localparam int TIMEOUT_CYCLES = 100000;
    localparam int SYMBOL_BITS = 9;
    localparam int TOKEN_PACK_BITS = CHUNK_WIDTH * SYMBOL_BITS;
    localparam int EXPECTED_PACK_BITS = CHUNK_WIDTH * SYMBOL_BITS;
    localparam int DICT_LENS_PACK_BITS = MAX_DICT_ENTRIES * 3;
    localparam int DICT_SEQ_PACK_BITS = MAX_DICT_ENTRIES * MAX_SEQ_LEN * SYMBOL_BITS;
    localparam int LOGICAL_BLOCKS_PER_CHUNK = CHUNK_WIDTH / 64;

    localparam logic [2:0] STATE_IDLE = 3'd0;
    localparam logic [2:0] STATE_COMPACT_TOKENS = 3'd1;
    localparam logic [2:0] STATE_PREP_SEGMENTS = 3'd2;
    localparam logic [2:0] STATE_LAUNCH = 3'd3;
    localparam logic [2:0] STATE_WAIT_DONE = 3'd4;
    localparam logic [2:0] STATE_DONE_STATE = 3'd5;

    logic clk;
    logic rst;
    logic start;
    vsym_t compressed_in [CHUNK_WIDTH];
    seq_t dict_seqs [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens [MAX_DICT_ENTRIES];
    dict_count_t dict_count;
    symbol_t decompressed_out [CHUNK_WIDTH];
    logic done;

    symbol_t expected_out [CHUNK_WIDTH];

    ExperimentalDecompressorTop dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .compressed_in(compressed_in),
        .dict_seqs(dict_seqs),
        .dict_lens(dict_lens),
        .dict_count(dict_count),
        .decompressed_out(decompressed_out),
        .done(done)
    );

    always #(CLK_HALF) clk = ~clk;

    function automatic symbol_t unpack_symbol(
        input logic [TOKEN_PACK_BITS-1:0] packed_bits,
        input int idx
    );
        unpack_symbol = packed_bits[idx * SYMBOL_BITS +: SYMBOL_BITS];
    endfunction

    function automatic logic [2:0] unpack_len(
        input logic [DICT_LENS_PACK_BITS-1:0] packed_bits,
        input int idx
    );
        unpack_len = packed_bits[idx * 3 +: 3];
    endfunction

    function automatic symbol_t unpack_seq_symbol(
        input logic [DICT_SEQ_PACK_BITS-1:0] packed_bits,
        input int dict_idx,
        input int sym_idx
    );
        int flat_idx;
        begin
            flat_idx = dict_idx * MAX_SEQ_LEN + sym_idx;
            unpack_seq_symbol = packed_bits[flat_idx * SYMBOL_BITS +: SYMBOL_BITS];
        end
    endfunction

    task automatic clear_inputs;
        begin
            start = 1'b0;
            dict_count = '0;
            for (int idx = 0; idx < CHUNK_WIDTH; idx++) begin
                compressed_in[idx] = '0;
                expected_out[idx] = '0;
            end
            for (int dict_idx = 0; dict_idx < MAX_DICT_ENTRIES; dict_idx++) begin
                dict_lens[dict_idx] = '0;
                dict_seqs[dict_idx] = '0;
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

    task automatic pulse_start;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic load_case(
        input integer fd,
        output string case_label,
        output int expected_count
    );
        logic [TOKEN_PACK_BITS-1:0] token_pack;
        logic [EXPECTED_PACK_BITS-1:0] expected_pack;
        logic [DICT_LENS_PACK_BITS-1:0] lens_pack;
        logic [DICT_SEQ_PACK_BITS-1:0] seq_pack;
        int rc;
        int token_count_i;
        int dict_count_i;
        begin
            token_pack = '0;
            expected_pack = '0;
            lens_pack = '0;
            seq_pack = '0;

            rc = $fscanf(fd, "%s\n", case_label);
            if (rc != 1) begin
                $fatal(1, "failed to read case label");
            end

            rc = $fscanf(fd, "%d\n", token_count_i);
            if (rc != 1) begin
                $fatal(1, "failed to read token count for %s", case_label);
            end
            rc = $fscanf(fd, "%h\n", token_pack);
            if (rc != 1) begin
                $fatal(1, "failed to read token pack for %s", case_label);
            end

            rc = $fscanf(fd, "%d\n", expected_count);
            if (rc != 1) begin
                $fatal(1, "failed to read expected count for %s", case_label);
            end
            rc = $fscanf(fd, "%h\n", expected_pack);
            if (rc != 1) begin
                $fatal(1, "failed to read expected pack for %s", case_label);
            end

            rc = $fscanf(fd, "%d\n", dict_count_i);
            if (rc != 1) begin
                $fatal(1, "failed to read dict_count for %s", case_label);
            end
            rc = $fscanf(fd, "%h\n", lens_pack);
            if (rc != 1) begin
                $fatal(1, "failed to read dict lens pack for %s", case_label);
            end
            rc = $fscanf(fd, "%h\n", seq_pack);
            if (rc != 1) begin
                $fatal(1, "failed to read dict sequence pack for %s", case_label);
            end

            dict_count = dict_count_t'(dict_count_i);
            for (int idx = 0; idx < CHUNK_WIDTH; idx++) begin
                compressed_in[idx].sym = unpack_symbol(token_pack, idx);
                compressed_in[idx].valid = (idx < token_count_i);
                expected_out[idx] = unpack_symbol(expected_pack, idx);
            end
            for (int dict_idx = 0; dict_idx < MAX_DICT_ENTRIES; dict_idx++) begin
                dict_lens[dict_idx] = unpack_len(lens_pack, dict_idx);
                for (int sym_idx = 0; sym_idx < MAX_SEQ_LEN; sym_idx++) begin
                    dict_seqs[dict_idx][sym_idx] = unpack_seq_symbol(seq_pack, dict_idx, sym_idx);
                end
            end
        end
    endtask

    task automatic wait_done_and_measure(
        input int case_idx,
        input string case_label,
        input int expected_count,
        input integer result_fd
    );
        int cycles;
        int state_idle;
        int state_compact;
        int state_prep;
        int state_launch;
        int state_wait;
        int state_done;
        int seg_done_cycle [DECOMP_LIFOS];
        int block_ready_cycle [LOGICAL_BLOCKS_PER_CHUNK];
        int output_timestamp [DECOMP_LIFOS][CHUNK_WIDTH];
        int prev_out_count [DECOMP_LIFOS];
        begin
            cycles = 0;
            state_idle = 0;
            state_compact = 0;
            state_prep = 0;
            state_launch = 0;
            state_wait = 0;
            state_done = 0;
            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                seg_done_cycle[seg] = -1;
            end
            for (int block_idx = 0; block_idx < LOGICAL_BLOCKS_PER_CHUNK; block_idx++) begin
                block_ready_cycle[block_idx] = -1;
            end
            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                prev_out_count[seg] = 0;
                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                    output_timestamp[seg][lane] = -1;
                end
            end

            while (!done && cycles < TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycles++;

                case (dut.state_r)
                    STATE_IDLE: state_idle = state_idle + 1;
                    STATE_COMPACT_TOKENS: state_compact = state_compact + 1;
                    STATE_PREP_SEGMENTS: state_prep = state_prep + 1;
                    STATE_LAUNCH: state_launch = state_launch + 1;
                    STATE_WAIT_DONE: state_wait = state_wait + 1;
                    STATE_DONE_STATE: state_done = state_done + 1;
                    default: begin
                    end
                endcase

                for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                    int current_out_count;

                    current_out_count = dut.segmented_out_counts[seg];
                    for (int lane = prev_out_count[seg]; lane < current_out_count; lane++) begin
                        output_timestamp[seg][lane] = cycles;
                    end
                    prev_out_count[seg] = current_out_count;

                    if (dut.segmented_done[seg] && (seg_done_cycle[seg] < 0)) begin
                        seg_done_cycle[seg] = cycles;
                    end
                end
            end

            if (!done) begin
                $fatal(1, "%s timed out waiting for decompressor done", case_label);
            end

            if (dut.total_out_count_dbg != expected_count) begin
                $fatal(1, "%s output count mismatch got=%0d expected=%0d",
                    case_label, dut.total_out_count_dbg, expected_count);
            end

            for (int idx = 0; idx < expected_count; idx++) begin
                if (decompressed_out[idx] !== expected_out[idx]) begin
                    $fatal(1, "%s output mismatch idx=%0d got=%0h expected=%0h",
                        case_label, idx, decompressed_out[idx], expected_out[idx]);
                end
            end

            begin
                int threshold;
                int prev_total;
                int total_available;
                int max_prev_done;
                int next_block_idx;

                threshold = 64;
                prev_total = 0;
                total_available = 0;
                max_prev_done = 0;
                next_block_idx = 0;

                for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                    total_available += dut.segmented_out_counts[seg];
                    while ((threshold <= expected_count) && (threshold <= total_available)) begin
                        int offset_in_seg;
                        int ready_cycle;

                        offset_in_seg = threshold - prev_total;
                        ready_cycle = output_timestamp[seg][offset_in_seg - 1];
                        if (ready_cycle < max_prev_done) begin
                            ready_cycle = max_prev_done;
                        end
                        block_ready_cycle[next_block_idx] = ready_cycle;
                        next_block_idx++;
                        threshold += 64;
                    end
                    prev_total = total_available;
                    if (seg_done_cycle[seg] > max_prev_done) begin
                        max_prev_done = seg_done_cycle[seg];
                    end
                end

                if (next_block_idx != LOGICAL_BLOCKS_PER_CHUNK) begin
                    $fatal(1, "%s block readiness accounting incomplete ready=%0d/%0d",
                        case_label, next_block_idx, LOGICAL_BLOCKS_PER_CHUNK);
                end
            end

            $fwrite(result_fd,
                "%0d %s %0d %0d %0d %0d %0d %0d %0d %0d",
                case_idx,
                case_label,
                cycles,
                state_idle,
                state_compact,
                state_prep,
                state_launch,
                state_wait,
                state_done,
                dut.total_out_count_dbg
            );
            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                $fwrite(result_fd, " %0d", seg_done_cycle[seg]);
            end
            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                $fwrite(result_fd, " %0d", dut.segmented_out_counts[seg]);
            end
            for (int block_idx = 0; block_idx < LOGICAL_BLOCKS_PER_CHUNK; block_idx++) begin
                $fwrite(result_fd, " %0d", block_ready_cycle[block_idx]);
            end
            $fwrite(result_fd, "\n");
        end
    endtask

    initial begin
        string stim_path;
        string result_path;
        string case_label;
        integer stim_fd;
        integer result_fd;
        int rc;
        int case_count;
        int expected_count;

        clk = 1'b0;

        if (!$value$plusargs("STIM_FILE=%s", stim_path)) begin
            $fatal(1, "missing +STIM_FILE=... plusarg");
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "missing +RESULT_FILE=... plusarg");
        end

        stim_fd = $fopen(stim_path, "r");
        if (stim_fd == 0) begin
            $fatal(1, "failed to open stimulus file %s", stim_path);
        end

        result_fd = $fopen(result_path, "w");
        if (result_fd == 0) begin
            $fatal(1, "failed to open result file %s", result_path);
        end

        rc = $fscanf(stim_fd, "%d\n", case_count);
        if (rc != 1) begin
            $fatal(1, "failed to read case count from %s", stim_path);
        end

        for (int case_idx = 0; case_idx < case_count; case_idx++) begin
            reset_dut();
            load_case(stim_fd, case_label, expected_count);
            pulse_start();
            wait_done_and_measure(case_idx, case_label, expected_count, result_fd);
        end

        $fclose(result_fd);
        $fclose(stim_fd);
        $display("[experimental-direct] PASS cases=%0d", case_count);
        $finish;
    end
endmodule
