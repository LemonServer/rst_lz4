`timescale 1ps / 1ps
`default_nettype none

module tb_SeqUpdateGen;
    import rst_pkg::*;

    logic clk;
    logic rst;
    logic start;
    logic i_busy;
    vsym_t pre_sub [CHUNK_WIDTH];
    vsym_t post_sub [CHUNK_WIDTH];
    logic [CHUNK_WIDTH-1:0] pre_sub_sites;
    logic [CHUNK_WIDTH-1:0] post_sub_sites;
    logic [2:0] sel_seq_len;
    logic o_valid;
    seq_update_t o_updates_len2 [PIPE_WIDTH_SEQ2];
    seq_update_t o_updates_len3 [PIPE_WIDTH_SEQ3];
    seq_update_t o_updates_len4 [PIPE_WIDTH_SEQ4];
    seq_update_t o_updates_len5 [PIPE_WIDTH_SEQ5];
    logic done;

    SeqUpdateGen dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .i_busy(i_busy),
        .pre_sub(pre_sub),
        .post_sub(post_sub),
        .pre_sub_sites(pre_sub_sites),
        .post_sub_sites(post_sub_sites),
        .sel_seq_len(sel_seq_len),
        .o_valid(o_valid),
        .o_updates_len2(o_updates_len2),
        .o_updates_len3(o_updates_len3),
        .o_updates_len4(o_updates_len4),
        .o_updates_len5(o_updates_len5),
        .done(done)
    );

    function automatic seq_t make_seq2(input int s0, input int s1);
        seq_t seq;
        begin
            seq = '0;
            seq[0] = symbol_t'(s0);
            seq[1] = symbol_t'(s1);
            return seq;
        end
    endfunction

    function automatic seq_t make_seq3(input int s0, input int s1, input int s2);
        seq_t seq;
        begin
            seq = '0;
            seq[0] = symbol_t'(s0);
            seq[1] = symbol_t'(s1);
            seq[2] = symbol_t'(s2);
            return seq;
        end
    endfunction

    function automatic seq_t make_seq4(input int s0, input int s1, input int s2, input int s3);
        seq_t seq;
        begin
            seq = '0;
            seq[0] = symbol_t'(s0);
            seq[1] = symbol_t'(s1);
            seq[2] = symbol_t'(s2);
            seq[3] = symbol_t'(s3);
            return seq;
        end
    endfunction

    function automatic seq_t make_seq5(
        input int s0,
        input int s1,
        input int s2,
        input int s3,
        input int s4
    );
        seq_t seq;
        begin
            seq = '0;
            seq[0] = symbol_t'(s0);
            seq[1] = symbol_t'(s1);
            seq[2] = symbol_t'(s2);
            seq[3] = symbol_t'(s3);
            seq[4] = symbol_t'(s4);
            return seq;
        end
    endfunction

    task automatic clear_arrays;
        begin
            pre_sub_sites = '0;
            post_sub_sites = '0;
            sel_seq_len = '0;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                pre_sub[i] = '0;
                post_sub[i] = '0;
            end
        end
    endtask

    task automatic set_pre(
        input int idx,
        input int sym,
        input logic valid
    );
        begin
            pre_sub[idx].sym = symbol_t'(sym);
            pre_sub[idx].valid = valid;
        end
    endtask

    task automatic set_post(
        input int idx,
        input int sym,
        input logic valid
    );
        begin
            post_sub[idx].sym = symbol_t'(sym);
            post_sub[idx].valid = valid;
        end
    endtask

    task automatic expect_update(
        input string label,
        input seq_update_t actual,
        input logic expected_valid,
        input logic expected_inc,
        input seq_t expected_seq
    );
        begin
            if (actual.valid !== expected_valid) begin
                $fatal(1, "%s valid mismatch: got %0b expected %0b",
                    label, actual.valid, expected_valid);
            end
            if (expected_valid) begin
                if ((actual.inc !== expected_inc) || (actual.seq !== expected_seq)) begin
                    $fatal(1, "%s mismatch: got inc=%0b seq=%p expected inc=%0b seq=%p",
                        label, actual.inc, actual.seq, expected_inc, expected_seq);
                end
            end
        end
    endtask

    task automatic expect_invalid_suffix;
        begin
            for (int i = PIPE_WIDTH_SEQ2 / 2; i < PIPE_WIDTH_SEQ2; i++) begin
                expect_update($sformatf("len2-suffix[%0d]", i), o_updates_len2[i], 1'b0, 1'b0, '0);
            end
            for (int i = PIPE_WIDTH_SEQ3 / 2; i < PIPE_WIDTH_SEQ3; i++) begin
                expect_update($sformatf("len3-suffix[%0d]", i), o_updates_len3[i], 1'b0, 1'b0, '0);
            end
            for (int i = PIPE_WIDTH_SEQ4 / 2; i < PIPE_WIDTH_SEQ4; i++) begin
                expect_update($sformatf("len4-suffix[%0d]", i), o_updates_len4[i], 1'b0, 1'b0, '0);
            end
            for (int i = PIPE_WIDTH_SEQ5 / 2; i < PIPE_WIDTH_SEQ5; i++) begin
                expect_update($sformatf("len5-suffix[%0d]", i), o_updates_len5[i], 1'b0, 1'b0, '0);
            end
        end
    endtask

    task automatic check_middle_seq3_vectors;
        localparam int REPL = 9'h1A5;
        begin
            expect_update("mid-l2-0", o_updates_len2[0], 1'b1, 1'b1, make_seq2(3, REPL));
            expect_update("mid-l2-1", o_updates_len2[1], 1'b1, 1'b1, make_seq2(REPL, 7));
            expect_update("mid-l2-2", o_updates_len2[2], 1'b1, 1'b0, make_seq2(3, 4));
            expect_update("mid-l2-3", o_updates_len2[3], 1'b1, 1'b0, make_seq2(4, 5));
            expect_update("mid-l2-4", o_updates_len2[4], 1'b1, 1'b0, make_seq2(5, 6));
            expect_update("mid-l2-5", o_updates_len2[5], 1'b1, 1'b0, make_seq2(6, 7));
            expect_update("mid-l2-6", o_updates_len2[6], 1'b0, 1'b0, '0);
            expect_update("mid-l2-7", o_updates_len2[7], 1'b0, 1'b0, '0);

            expect_update("mid-l3-0", o_updates_len3[0], 1'b1, 1'b1, make_seq3(2, 3, REPL));
            expect_update("mid-l3-1", o_updates_len3[1], 1'b1, 1'b1, make_seq3(3, REPL, 7));
            expect_update("mid-l3-2", o_updates_len3[2], 1'b1, 1'b1, make_seq3(REPL, 7, 8));
            expect_update("mid-l3-3", o_updates_len3[3], 1'b1, 1'b0, make_seq3(2, 3, 4));
            expect_update("mid-l3-4", o_updates_len3[4], 1'b1, 1'b0, make_seq3(3, 4, 5));
            expect_update("mid-l3-5", o_updates_len3[5], 1'b1, 1'b0, make_seq3(4, 5, 6));
            expect_update("mid-l3-6", o_updates_len3[6], 1'b1, 1'b0, make_seq3(5, 6, 7));
            expect_update("mid-l3-7", o_updates_len3[7], 1'b1, 1'b0, make_seq3(6, 7, 8));
            expect_update("mid-l3-8", o_updates_len3[8], 1'b0, 1'b0, '0);
            expect_update("mid-l3-9", o_updates_len3[9], 1'b0, 1'b0, '0);

            expect_update("mid-l4-0", o_updates_len4[0], 1'b1, 1'b1, make_seq4(1, 2, 3, REPL));
            expect_update("mid-l4-1", o_updates_len4[1], 1'b1, 1'b1, make_seq4(2, 3, REPL, 7));
            expect_update("mid-l4-2", o_updates_len4[2], 1'b1, 1'b1, make_seq4(3, REPL, 7, 8));
            expect_update("mid-l4-3", o_updates_len4[3], 1'b1, 1'b1, make_seq4(REPL, 7, 8, 9));
            expect_update("mid-l4-4", o_updates_len4[4], 1'b1, 1'b0, make_seq4(1, 2, 3, 4));
            expect_update("mid-l4-5", o_updates_len4[5], 1'b1, 1'b0, make_seq4(2, 3, 4, 5));
            expect_update("mid-l4-6", o_updates_len4[6], 1'b1, 1'b0, make_seq4(3, 4, 5, 6));
            expect_update("mid-l4-7", o_updates_len4[7], 1'b1, 1'b0, make_seq4(4, 5, 6, 7));
            expect_update("mid-l4-8", o_updates_len4[8], 1'b1, 1'b0, make_seq4(5, 6, 7, 8));
            expect_update("mid-l4-9", o_updates_len4[9], 1'b1, 1'b0, make_seq4(6, 7, 8, 9));
            expect_update("mid-l4-10", o_updates_len4[10], 1'b0, 1'b0, '0);
            expect_update("mid-l4-11", o_updates_len4[11], 1'b0, 1'b0, '0);

            expect_update("mid-l5-0", o_updates_len5[0], 1'b1, 1'b1, make_seq5(0, 1, 2, 3, REPL));
            expect_update("mid-l5-1", o_updates_len5[1], 1'b1, 1'b1, make_seq5(1, 2, 3, REPL, 7));
            expect_update("mid-l5-2", o_updates_len5[2], 1'b1, 1'b1, make_seq5(2, 3, REPL, 7, 8));
            expect_update("mid-l5-3", o_updates_len5[3], 1'b1, 1'b1, make_seq5(3, REPL, 7, 8, 9));
            expect_update("mid-l5-4", o_updates_len5[4], 1'b1, 1'b1, make_seq5(REPL, 7, 8, 9, 10));
            expect_update("mid-l5-5", o_updates_len5[5], 1'b1, 1'b0, make_seq5(0, 1, 2, 3, 4));
            expect_update("mid-l5-6", o_updates_len5[6], 1'b1, 1'b0, make_seq5(1, 2, 3, 4, 5));
            expect_update("mid-l5-7", o_updates_len5[7], 1'b1, 1'b0, make_seq5(2, 3, 4, 5, 6));
            expect_update("mid-l5-8", o_updates_len5[8], 1'b1, 1'b0, make_seq5(3, 4, 5, 6, 7));
            expect_update("mid-l5-9", o_updates_len5[9], 1'b1, 1'b0, make_seq5(4, 5, 6, 7, 8));
            expect_update("mid-l5-10", o_updates_len5[10], 1'b1, 1'b0, make_seq5(5, 6, 7, 8, 9));
            expect_update("mid-l5-11", o_updates_len5[11], 1'b1, 1'b0, make_seq5(6, 7, 8, 9, 10));
            expect_update("mid-l5-12", o_updates_len5[12], 1'b0, 1'b0, '0);
            expect_update("mid-l5-13", o_updates_len5[13], 1'b0, 1'b0, '0);
        end
    endtask

    task automatic check_start_seq5_vectors;
        localparam int REPL = 9'h1B4;
        begin
            expect_update("start-l2-0", o_updates_len2[0], 1'b0, 1'b0, '0);
            expect_update("start-l2-1", o_updates_len2[1], 1'b1, 1'b1, make_seq2(REPL, 5));
            expect_update("start-l2-2", o_updates_len2[2], 1'b0, 1'b0, '0);
            expect_update("start-l2-3", o_updates_len2[3], 1'b1, 1'b0, make_seq2(0, 1));
            expect_update("start-l2-4", o_updates_len2[4], 1'b1, 1'b0, make_seq2(1, 2));
            expect_update("start-l2-5", o_updates_len2[5], 1'b1, 1'b0, make_seq2(2, 3));
            expect_update("start-l2-6", o_updates_len2[6], 1'b1, 1'b0, make_seq2(3, 4));
            expect_update("start-l2-7", o_updates_len2[7], 1'b1, 1'b0, make_seq2(4, 5));

            expect_update("start-l3-0", o_updates_len3[0], 1'b0, 1'b0, '0);
            expect_update("start-l3-1", o_updates_len3[1], 1'b0, 1'b0, '0);
            expect_update("start-l3-2", o_updates_len3[2], 1'b1, 1'b1, make_seq3(REPL, 5, 6));
            expect_update("start-l3-3", o_updates_len3[3], 1'b0, 1'b0, '0);
            expect_update("start-l3-4", o_updates_len3[4], 1'b0, 1'b0, '0);
            expect_update("start-l3-5", o_updates_len3[5], 1'b1, 1'b0, make_seq3(0, 1, 2));
            expect_update("start-l3-6", o_updates_len3[6], 1'b1, 1'b0, make_seq3(1, 2, 3));
            expect_update("start-l3-7", o_updates_len3[7], 1'b1, 1'b0, make_seq3(2, 3, 4));
            expect_update("start-l3-8", o_updates_len3[8], 1'b1, 1'b0, make_seq3(3, 4, 5));
            expect_update("start-l3-9", o_updates_len3[9], 1'b1, 1'b0, make_seq3(4, 5, 6));

            expect_update("start-l4-0", o_updates_len4[0], 1'b0, 1'b0, '0);
            expect_update("start-l4-1", o_updates_len4[1], 1'b0, 1'b0, '0);
            expect_update("start-l4-2", o_updates_len4[2], 1'b0, 1'b0, '0);
            expect_update("start-l4-3", o_updates_len4[3], 1'b1, 1'b1, make_seq4(REPL, 5, 6, 7));
            expect_update("start-l4-4", o_updates_len4[4], 1'b0, 1'b0, '0);
            expect_update("start-l4-5", o_updates_len4[5], 1'b0, 1'b0, '0);
            expect_update("start-l4-6", o_updates_len4[6], 1'b0, 1'b0, '0);
            expect_update("start-l4-7", o_updates_len4[7], 1'b1, 1'b0, make_seq4(0, 1, 2, 3));
            expect_update("start-l4-8", o_updates_len4[8], 1'b1, 1'b0, make_seq4(1, 2, 3, 4));
            expect_update("start-l4-9", o_updates_len4[9], 1'b1, 1'b0, make_seq4(2, 3, 4, 5));
            expect_update("start-l4-10", o_updates_len4[10], 1'b1, 1'b0, make_seq4(3, 4, 5, 6));
            expect_update("start-l4-11", o_updates_len4[11], 1'b1, 1'b0, make_seq4(4, 5, 6, 7));

            expect_update("start-l5-0", o_updates_len5[0], 1'b0, 1'b0, '0);
            expect_update("start-l5-1", o_updates_len5[1], 1'b0, 1'b0, '0);
            expect_update("start-l5-2", o_updates_len5[2], 1'b0, 1'b0, '0);
            expect_update("start-l5-3", o_updates_len5[3], 1'b0, 1'b0, '0);
            expect_update("start-l5-4", o_updates_len5[4], 1'b1, 1'b1, make_seq5(REPL, 5, 6, 7, 8));
            expect_update("start-l5-5", o_updates_len5[5], 1'b0, 1'b0, '0);
            expect_update("start-l5-6", o_updates_len5[6], 1'b0, 1'b0, '0);
            expect_update("start-l5-7", o_updates_len5[7], 1'b0, 1'b0, '0);
            expect_update("start-l5-8", o_updates_len5[8], 1'b0, 1'b0, '0);
            expect_update("start-l5-9", o_updates_len5[9], 1'b1, 1'b0, make_seq5(0, 1, 2, 3, 4));
            expect_update("start-l5-10", o_updates_len5[10], 1'b1, 1'b0, make_seq5(1, 2, 3, 4, 5));
            expect_update("start-l5-11", o_updates_len5[11], 1'b1, 1'b0, make_seq5(2, 3, 4, 5, 6));
            expect_update("start-l5-12", o_updates_len5[12], 1'b1, 1'b0, make_seq5(3, 4, 5, 6, 7));
            expect_update("start-l5-13", o_updates_len5[13], 1'b1, 1'b0, make_seq5(4, 5, 6, 7, 8));
        end
    endtask

    task automatic setup_middle_seq3_case;
        localparam int REPL = 9'h1A5;
        begin
            clear_arrays();
            sel_seq_len = 3'd3;
            pre_sub_sites[4] = 1'b1;
            post_sub_sites[4] = 1'b1;
            for (int i = 0; i < 16; i++) begin
                set_pre(i, i, 1'b1);
            end
            for (int i = 0; i < 4; i++) begin
                set_post(i, i, 1'b1);
            end
            set_post(4, REPL, 1'b1);
            for (int i = 5; i < 14; i++) begin
                set_post(i, i + 2, 1'b1);
            end
        end
    endtask

    task automatic setup_start_seq5_case;
        localparam int REPL = 9'h1B4;
        begin
            clear_arrays();
            sel_seq_len = 3'd5;
            pre_sub_sites[0] = 1'b1;
            post_sub_sites[0] = 1'b1;
            for (int i = 0; i < 13; i++) begin
                set_pre(i, i, 1'b1);
            end
            set_post(0, REPL, 1'b1);
            for (int i = 1; i < 9; i++) begin
                set_post(i, i + 4, 1'b1);
            end
        end
    endtask

    task automatic setup_backpressure_case;
        localparam int REPL = 9'h1C0;
        begin
            clear_arrays();
            sel_seq_len = 3'd2;
            pre_sub_sites[4] = 1'b1;
            pre_sub_sites[10] = 1'b1;
            post_sub_sites[4] = 1'b1;
            post_sub_sites[9] = 1'b1;
            for (int i = 0; i < 19; i++) begin
                set_pre(i, i, 1'b1);
            end
            for (int i = 0; i < 4; i++) begin
                set_post(i, i, 1'b1);
            end
            set_post(4, REPL, 1'b1);
            set_post(5, 6, 1'b1);
            set_post(6, 7, 1'b1);
            set_post(7, 8, 1'b1);
            set_post(8, 9, 1'b1);
            set_post(9, REPL, 1'b1);
            for (int i = 10; i < 17; i++) begin
                set_post(i, i + 2, 1'b1);
            end
        end
    endtask

    task automatic check_dual_site_backpressure_batch;
        localparam int REPL = 9'h1C0;
        begin
            expect_update("bp-site0-l2-0", o_updates_len2[0], 1'b1, 1'b1, make_seq2(3, REPL));
            expect_update("bp-site0-l2-1", o_updates_len2[1], 1'b1, 1'b1, make_seq2(REPL, 6));
            expect_update("bp-site0-l2-2", o_updates_len2[2], 1'b1, 1'b0, make_seq2(3, 4));
            expect_update("bp-site0-l2-3", o_updates_len2[3], 1'b1, 1'b0, make_seq2(4, 5));
            expect_update("bp-site0-l2-4", o_updates_len2[4], 1'b1, 1'b0, make_seq2(5, 6));
            for (int i = 5; i < PIPE_WIDTH_SEQ2 / 2; i++) begin
                expect_update($sformatf("bp-site0-l2-tail[%0d]", i), o_updates_len2[i], 1'b0, 1'b0, '0);
            end

            expect_update("bp-site1-l2-0", o_updates_len2[PIPE_WIDTH_SEQ2 / 2 + 0], 1'b1, 1'b1, make_seq2(9, REPL));
            expect_update("bp-site1-l2-1", o_updates_len2[PIPE_WIDTH_SEQ2 / 2 + 1], 1'b1, 1'b1, make_seq2(REPL, 12));
            expect_update("bp-site1-l2-2", o_updates_len2[PIPE_WIDTH_SEQ2 / 2 + 2], 1'b1, 1'b0, make_seq2(9, 10));
            expect_update("bp-site1-l2-3", o_updates_len2[PIPE_WIDTH_SEQ2 / 2 + 3], 1'b1, 1'b0, make_seq2(10, 11));
            expect_update("bp-site1-l2-4", o_updates_len2[PIPE_WIDTH_SEQ2 / 2 + 4], 1'b1, 1'b0, make_seq2(11, 12));
            for (int i = PIPE_WIDTH_SEQ2 / 2 + 5; i < PIPE_WIDTH_SEQ2; i++) begin
                expect_update($sformatf("bp-site1-l2-tail[%0d]", i), o_updates_len2[i], 1'b0, 1'b0, '0);
            end

            expect_update("bp-site1-l3-0", o_updates_len3[PIPE_WIDTH_SEQ3 / 2 + 0], 1'b1, 1'b1, make_seq3(8, 9, REPL));
            expect_update("bp-site1-l4-0", o_updates_len4[PIPE_WIDTH_SEQ4 / 2 + 0], 1'b1, 1'b1, make_seq4(7, 8, 9, REPL));
            expect_update("bp-site1-l5-0", o_updates_len5[PIPE_WIDTH_SEQ5 / 2 + 0], 1'b1, 1'b1, make_seq5(6, 7, 8, 9, REPL));
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        start = 1'b0;
        i_busy = 1'b0;

        rst = 1'b1;
        clear_arrays();
        @(posedge clk);
        #1;
        rst = 1'b0;

        setup_middle_seq3_case();
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
        if (!o_valid) begin
            $fatal(1, "SeqUpdateGen failed to present the first site");
        end
        check_middle_seq3_vectors();
        expect_invalid_suffix();
        @(posedge clk);
        #1;
        if (!done || o_valid) begin
            $fatal(1, "single-site middle case did not complete cleanly");
        end

        rst = 1'b1;
        start = 1'b0;
        i_busy = 1'b0;
        clear_arrays();
        @(posedge clk);
        #1;
        rst = 1'b0;

        setup_start_seq5_case();
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
        if (!o_valid) begin
            $fatal(1, "SeqUpdateGen failed to present the first site");
        end
        check_start_seq5_vectors();
        expect_invalid_suffix();
        @(posedge clk);
        #1;
        if (!done || o_valid) begin
            $fatal(1, "start-of-page case did not complete cleanly");
        end

        rst = 1'b1;
        start = 1'b0;
        i_busy = 1'b0;
        clear_arrays();
        @(posedge clk);
        #1;
        rst = 1'b0;

        setup_backpressure_case();
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
        if (!o_valid) begin
            $fatal(1, "SeqUpdateGen failed to present the dual-site batch");
        end
        check_dual_site_backpressure_batch();

        i_busy = 1'b1;
        @(posedge clk);
        #1;
        if (!o_valid || done) begin
            $fatal(1, "backpressure should hold the merged dual-site batch without finishing");
        end
        check_dual_site_backpressure_batch();

        i_busy = 1'b0;
        @(posedge clk);
        #1;
        if (!done || o_valid) begin
            $fatal(1, "dual-site backpressure case did not finish after the held batch was accepted");
        end

        $finish;
    end
endmodule
