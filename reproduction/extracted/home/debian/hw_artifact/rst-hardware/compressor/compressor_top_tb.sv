`timescale 1ps / 1ps
`default_nettype none

module tb_CompressorTop;
    import rst_pkg::*;

    localparam int CLK_HALF = 5;
    localparam int MAX_CANDIDATES = CHUNK_WIDTH * (MAX_SEQ_LEN - MIN_SEQ_LEN + 1);
    localparam int TIMEOUT_CYCLES = 5000;

    logic clk;
    logic rst;
    logic start;
    symbol_t page_in [CHUNK_WIDTH];
    vsym_t compressed_out [CHUNK_WIDTH];
    seq_t dict_seqs [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens [MAX_DICT_ENTRIES];
    dict_count_t dict_count;
    dict_packed_t dict_packed;
    dict_bit_count_t dict_packed_bits;
    logic done;

    symbol_t stimulus_page [CHUNK_WIDTH];
    symbol_t expected_page_sym [CHUNK_WIDTH];
    logic expected_page_valid [CHUNK_WIDTH];
    seq_t expected_dict_seqs [MAX_DICT_ENTRIES];
    logic [2:0] expected_dict_lens [MAX_DICT_ENTRIES];
    int expected_dict_count;

`include "compressor/compressor_top_golden_vectors.svh"

    CompressorTop dut (
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

    task automatic reset_dut;
        begin
            rst = 1'b1;
            start = 1'b0;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
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
                    default: stimulus_page[i] = 9'h080 + symbol_t'(i / 3);
                endcase
            end
        end
    endtask

    task automatic build_sparse_single_iter_page;
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
                base = 24 + rep * 56;
                for (int j = 0; j < 5; j++) begin
                    stimulus_page[base + j] = seq_a[j];
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

            for (int rep = 0; rep < 4; rep++) begin
                int base;
                base = 16 + rep * 64;
                for (int j = 0; j < 5; j++) begin
                    stimulus_page[base + j] = seq_a[j];
                end
            end

            for (int rep = 0; rep < 4; rep++) begin
                int base;
                base = 48 + rep * 64;
                for (int j = 0; j < 4; j++) begin
                    stimulus_page[base + j] = seq_b[j];
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
                base = 40 + rep * 48;
                for (int j = 0; j < 4; j++) begin
                    stimulus_page[base + j] = seq_b[j];
                end
            end
        end
    endtask

    task automatic compute_expected;
        symbol_t working_page [CHUNK_WIDTH];
        symbol_t next_page [CHUNK_WIDTH];
        seq_t cand_seq [MAX_CANDIDATES];
        logic [2:0] cand_len [MAX_CANDIDATES];
        int cand_count [MAX_CANDIDATES];
        int working_len;
        int dict_space;
        int cand_used;
        int best_idx;
        int best_cost;
        int next_len;
        int match_idx;
        int best_num;
        int best_den;
        int cand_num;
        int cand_den;
        int seq_len_i;
        bit made_replacement;
        symbol_t repl_symbol;
        seq_t this_seq;

        begin
            working_len = CHUNK_WIDTH;
            dict_space = MEMORY_BLOCKS * 64 * 8 - 6;
            expected_dict_count = 0;

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                working_page[i] = stimulus_page[i];
                expected_page_sym[i] = '0;
                expected_page_valid[i] = 1'b0;
            end

            for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                expected_dict_seqs[idx] = '0;
                expected_dict_lens[idx] = '0;
            end

            while (expected_dict_count < MAX_DICT_ENTRIES) begin
                cand_used = 0;
                best_idx = -1;
                best_cost = 0;
                best_num = 0;
                best_den = 1;

                for (int idx = 0; idx < MAX_CANDIDATES; idx++) begin
                    cand_seq[idx] = '0;
                    cand_len[idx] = '0;
                    cand_count[idx] = 0;
                end

                for (seq_len_i = MIN_SEQ_LEN; seq_len_i <= MAX_SEQ_LEN; seq_len_i++) begin
                    for (int pos = 0; pos + seq_len_i <= working_len; pos++) begin
                        this_seq = '0;
                        for (int j = 0; j < seq_len_i; j++) begin
                            this_seq[j] = working_page[pos + j];
                        end

                        match_idx = -1;
                        for (int idx = 0; idx < cand_used; idx++) begin
                            if ((cand_len[idx] == seq_len_i[2:0]) && (cand_seq[idx] == this_seq)) begin
                                match_idx = idx;
                            end
                        end

                        if (match_idx == -1) begin
                            cand_seq[cand_used] = this_seq;
                            cand_len[cand_used] = seq_len_i[2:0];
                            cand_count[cand_used] = 1;
                            cand_used++;
                        end else begin
                            cand_count[match_idx]++;
                        end
                    end
                end

                for (int idx = 0; idx < cand_used; idx++) begin
                    cand_num = utility_numerator(cand_len[idx], cand_count[idx][COUNT_BITS-1:0]);
                    cand_den = utility_denominator(cand_len[idx]);
                    if ((cand_num > 0) && (dict_space >= dict_entry_cost_bits(cand_len[idx]))) begin
                        if ((best_idx == -1) || ((cand_num * best_den) > (best_num * cand_den))) begin
                            best_idx = idx;
                            best_cost = dict_entry_cost_bits(cand_len[idx]);
                            best_num = cand_num;
                            best_den = cand_den;
                        end
                    end
                end

                if (best_idx == -1) begin
                    break;
                end

                repl_symbol = symbol_t'(9'h100 + expected_dict_count);
                next_len = 0;
                made_replacement = 1'b0;
                seq_len_i = cand_len[best_idx];

                for (int i = 0; i < CHUNK_WIDTH; i++) begin
                    next_page[i] = '0;
                end

                for (int pos = 0; pos < working_len; ) begin
                    bit hit;
                    hit = 1'b1;
                    if (pos + seq_len_i > working_len) begin
                        hit = 1'b0;
                    end else begin
                        for (int j = 0; j < seq_len_i; j++) begin
                            if (working_page[pos + j] != cand_seq[best_idx][j]) begin
                                hit = 1'b0;
                            end
                        end
                    end

                    if (hit) begin
                        next_page[next_len] = repl_symbol;
                        next_len++;
                        pos += seq_len_i;
                        made_replacement = 1'b1;
                    end else begin
                        next_page[next_len] = working_page[pos];
                        next_len++;
                        pos++;
                    end
                end

                if (!made_replacement) begin
                    break;
                end

                expected_dict_seqs[expected_dict_count] = cand_seq[best_idx];
                expected_dict_lens[expected_dict_count] = cand_len[best_idx];
                expected_dict_count++;
                dict_space -= best_cost;
                working_len = next_len;

                for (int i = 0; i < CHUNK_WIDTH; i++) begin
                    working_page[i] = next_page[i];
                end
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (i < working_len) begin
                    expected_page_sym[i] = working_page[i];
                    expected_page_valid[i] = 1'b1;
                end else begin
                    expected_page_sym[i] = '0;
                    expected_page_valid[i] = 1'b0;
                end
            end
        end
    endtask

    function automatic string state_name(input logic [3:0] state_bits);
        begin
            case (state_bits)
                4'd0: state_name = "IDLE";
                4'd1: state_name = "INIT_COUNT";
                4'd2: state_name = "WAIT_DRAIN";
                4'd3: state_name = "WAIT_TOP_SETTLE";
                4'd4: state_name = "SELECT_TOP";
                4'd5: state_name = "WAIT_TOP_RESULT";
                4'd6: state_name = "WAIT_TOP_SCORE";
                4'd7: state_name = "CHECK_UTILITY";
                4'd8: state_name = "START_SUBSTITUTE";
                4'd9: state_name = "WAIT_SUBSTITUTE";
                4'd10: state_name = "GEN_UPDATES";
                4'd11: state_name = "DONE_STATE";
                default: state_name = "UNKNOWN";
            endcase
        end
    endfunction

    task automatic log_top_state(input string case_name, input int cycles);
        int actual_match_count;
        int sub_site_count;
        int valid_syms;
        bit hit;
        begin
            actual_match_count = 0;
            valid_syms = 0;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (dut.page_reg[i].valid) begin
                    valid_syms++;
                end
            end

            for (int pos = 0; pos < CHUNK_WIDTH; pos++) begin
                hit = 1'b1;
                if (!dut.top_result.valid || (dut.top_result.seq_len < MIN_SEQ_LEN) ||
                    (dut.top_result.seq_len > MAX_SEQ_LEN)) begin
                    hit = 1'b0;
                end else if (pos + dut.top_result.seq_len > CHUNK_WIDTH) begin
                    hit = 1'b0;
                end else begin
                    for (int j = 0; j < dut.top_result.seq_len; j++) begin
                        if (!dut.page_reg[pos + j].valid ||
                            (dut.page_reg[pos + j].sym !== dut.top_result.seq[j])) begin
                            hit = 1'b0;
                        end
                    end
                end

                if (hit) begin
                    actual_match_count++;
                    pos += dut.top_result.seq_len - 1;
                end
            end

            sub_site_count = 0;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (dut.sub_sites[i]) begin
                    sub_site_count++;
                end
            end

            $display("[%s] cyc=%0d state=%s dict=%0d page_valid=%0d init_done=%0b update_done=%0b all_empty=%0b",
                case_name, cycles, state_name(dut.state), dut.dict_count, valid_syms,
                dut.init_done, dut.update_done, dut.all_pipes_empty);
            $display("  top: valid=%0b len=%0d count=%0d actual_matches=%0d sub_sites=%0d util_num=%0d can_sub=%0b",
                dut.top_valid, dut.top_result.seq_len, dut.top_result.count, actual_match_count,
                sub_site_count, dut.selected_utility_num, dut.can_substitute);
            for (int idx = 0; idx < 4; idx++) begin
                $display("  cand_len%0d: valid=%0b count=%0d",
                    idx + 2,
                    dut.hash_table.candidates[idx].valid,
                    dut.hash_table.candidates[idx].count);
            end
        end
    endtask

    task automatic check_outputs(input string case_name, input bit verbose);
        int cycles;
        logic [3:0] last_state;
        begin
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                page_in[i] = stimulus_page[i];
            end

            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            cycles = 0;
            last_state = dut.state;
            while (!done && (cycles < TIMEOUT_CYCLES)) begin
                @(posedge clk);
                if (verbose && (dut.state != last_state)) begin
                    log_top_state(case_name, cycles);
                end
                last_state = dut.state;
                cycles++;
            end

            if (!done) begin
                if (verbose) begin
                    log_top_state(case_name, cycles);
                end
                $display("%s timeout debug: state=%0d dict_count=%0d init_done=%0b update_done=%0b all_empty=%0b",
                    case_name, dut.state, dut.dict_count, dut.init_done, dut.update_done, dut.all_pipes_empty);
                $display("  pipe_empty seq2=%0b seq3=%0b seq4=%0b seq5=%0b",
                    dut.pipe_empty_seq2, dut.pipe_empty_seq3, dut.pipe_empty_seq4, dut.pipe_empty_seq5);
                $display("  pipe_busy  seq2=%0b seq3=%0b seq4=%0b seq5=%0b",
                    dut.pipe_busy_seq2, dut.pipe_busy_seq3, dut.pipe_busy_seq4, dut.pipe_busy_seq5);
                $display("  update_o_valid=%0b sub_sites=%0h post_sub_sites=%0h",
                    dut.update_o_valid, dut.update_pre_sites, dut.update_post_sites);
                $display("  pending_pre=%0h pending_post=%0h pre_pos0=%0d post_pos0=%0d",
                    dut.update_gen.pending_pre_sites,
                    dut.update_gen.pending_post_sites,
                    dut.update_gen.pre_site_pos0,
                    dut.update_gen.post_site_pos0);
                for (int bank = 0; bank < BANKS_SEQ2; bank++) begin
                    if (dut.pipe_seq2.fifo_busy[bank]) begin
                        $display("  seq2 bank%0d fifo_busy=1", bank);
                    end
                end
                for (int bank = 0; bank < BANKS_SEQ3; bank++) begin
                    if (dut.pipe_seq3.fifo_busy[bank]) begin
                        $display("  seq3 bank%0d fifo_busy=1", bank);
                    end
                end
                for (int bank = 0; bank < BANKS_SEQ4; bank++) begin
                    if (dut.pipe_seq4.fifo_busy[bank]) begin
                        $display("  seq4 bank%0d fifo_busy=1", bank);
                    end
                end
                for (int bank = 0; bank < BANKS_SEQ5; bank++) begin
                    if (dut.pipe_seq5.fifo_busy[bank]) begin
                        $display("  seq5 bank%0d fifo_busy=1", bank);
                    end
                end
                $fatal(1, "%s timed out after %0d cycles", case_name, TIMEOUT_CYCLES);
            end

            if (dict_count !== expected_dict_count[5:0]) begin
                $fatal(1, "%s dict_count mismatch got=%0d expected=%0d", case_name, dict_count, expected_dict_count);
            end

            for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                if (dict_lens[idx] !== expected_dict_lens[idx]) begin
                    $fatal(1, "%s dict_lens[%0d] mismatch got=%0d expected=%0d",
                        case_name, idx, dict_lens[idx], expected_dict_lens[idx]);
                end
                if (dict_seqs[idx] !== expected_dict_seqs[idx]) begin
                    $fatal(1, "%s dict_seqs[%0d] mismatch", case_name, idx);
                end
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (compressed_out[i].valid !== expected_page_valid[i]) begin
                    $fatal(1, "%s compressed_out[%0d].valid mismatch got=%0b expected=%0b",
                        case_name, i, compressed_out[i].valid, expected_page_valid[i]);
                end
                if (compressed_out[i].sym !== expected_page_sym[i]) begin
                    $fatal(1, "%s compressed_out[%0d].sym mismatch got=%0h expected=%0h",
                        case_name, i, compressed_out[i].sym, expected_page_sym[i]);
                end
            end

            $display("%s clean: dict_count=%0d cycles=%0d", case_name, expected_dict_count, cycles);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        start = 1'b0;
        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            page_in[i] = '0;
            stimulus_page[i] = '0;
        end

        reset_dut();
        load_golden_unique_page_no_compress();
        check_outputs("unique_page_no_compress", 1'b0);

        reset_dut();
        load_golden_sparse_page_single_iter();
        check_outputs("sparse_page_single_iter", 1'b1);

        reset_dut();
        load_golden_sparse_len4_single_iter();
        check_outputs("sparse_len4_single_iter", 1'b1);

        $display("tb_CompressorTop passed");
        $finish;
    end
endmodule
