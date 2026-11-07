`timescale 1ps / 1ps
`default_nettype none

module tb_InitSeqCountGen;
    import rst_pkg::*;

    logic clk;
    logic rst;
    logic start;
    logic i_busy;
    vsym_t data [CHUNK_WIDTH];
    logic o_valid;
    seq_update_t o_updates_len2 [PIPE_WIDTH_SEQ2];
    seq_update_t o_updates_len3 [PIPE_WIDTH_SEQ3];
    seq_update_t o_updates_len4 [PIPE_WIDTH_SEQ4];
    seq_update_t o_updates_len5 [PIPE_WIDTH_SEQ5];
    logic done;

    InitSeqCountGen dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .i_busy(i_busy),
        .data(data),
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

    function automatic int expected_valid_count(
        input int base,
        input int seq_len
    );
        int remaining;
        begin
            remaining = CHUNK_WIDTH - base - seq_len + 1;
            if (remaining <= 0) begin
                return 0;
            end
            if (remaining >= INIT_COUNT_POSITIONS_PER_CYCLE) begin
                return INIT_COUNT_POSITIONS_PER_CYCLE;
            end
            return remaining;
        end
    endfunction

    task automatic initialize_data;
        begin
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                data[i].sym = symbol_t'(i);
                data[i].valid = 1'b1;
            end
        end
    endtask

    task automatic expect_update(
        input string label,
        input seq_update_t actual,
        input logic expected_valid,
        input seq_t expected_seq
    );
        begin
            if (actual.valid !== expected_valid) begin
                $fatal(1, "%s valid mismatch: got %0b expected %0b",
                    label, actual.valid, expected_valid);
            end
            if (expected_valid) begin
                if (!actual.inc || actual.seq !== expected_seq) begin
                    $fatal(1, "%s seq mismatch", label);
                end
            end else if (actual !== '0) begin
                $fatal(1, "%s should be zero when invalid", label);
            end
        end
    endtask

    task automatic expect_batch(input int base);
        int valid2;
        int valid3;
        int valid4;
        int valid5;
        begin
            if (!o_valid) begin
                $fatal(1, "expected a valid batch at base %0d", base);
            end

            valid2 = expected_valid_count(base, 2);
            valid3 = expected_valid_count(base, 3);
            valid4 = expected_valid_count(base, 4);
            valid5 = expected_valid_count(base, 5);

            for (int i = 0; i < PIPE_WIDTH_SEQ2; i++) begin
                expect_update($sformatf("len2[%0d]@%0d", i, base), o_updates_len2[i],
                    (i < valid2), make_seq2(base + i, base + i + 1));
            end

            for (int i = 0; i < PIPE_WIDTH_SEQ3; i++) begin
                expect_update($sformatf("len3[%0d]@%0d", i, base), o_updates_len3[i],
                    (i < valid3), make_seq3(base + i, base + i + 1, base + i + 2));
            end

            for (int i = 0; i < PIPE_WIDTH_SEQ4; i++) begin
                expect_update($sformatf("len4[%0d]@%0d", i, base), o_updates_len4[i],
                    (i < valid4), make_seq4(base + i, base + i + 1, base + i + 2, base + i + 3));
            end

            for (int i = 0; i < PIPE_WIDTH_SEQ5; i++) begin
                expect_update($sformatf("len5[%0d]@%0d", i, base), o_updates_len5[i],
                    (i < valid5), make_seq5(base + i, base + i + 1, base + i + 2, base + i + 3, base + i + 4));
            end
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        int current_base;
        int final_base;

        clk = 1'b0;
        start = 1'b0;
        i_busy = 1'b0;

        rst = 1'b1;
        initialize_data();
        @(posedge clk);
        #1;
        rst = 1'b0;

        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;

        expect_batch(0);
        i_busy = 1'b1;
        @(posedge clk);
        #1;
        if (!o_valid || done) begin
            $fatal(1, "InitSeqCountGen should hold the current batch during backpressure");
        end
        expect_batch(0);

        i_busy = 1'b0;
        if (!o_valid) begin
            $fatal(1, "attempted to accept a batch while o_valid was low");
        end
        @(posedge clk);
        #1;
        current_base = INIT_COUNT_POSITIONS_PER_CYCLE;
        final_base = CHUNK_WIDTH - INIT_COUNT_POSITIONS_PER_CYCLE;
        expect_batch(current_base);

        while (current_base < final_base) begin
            if (!o_valid) begin
                $fatal(1, "attempted to accept a batch while o_valid was low");
            end
            @(posedge clk);
            #1;
            current_base = current_base + INIT_COUNT_POSITIONS_PER_CYCLE;
        end

        expect_batch(current_base);
        if (!o_valid) begin
            $fatal(1, "attempted to accept a batch while o_valid was low");
        end
        @(posedge clk);
        #1;
        if (!done || o_valid) begin
            $fatal(1, "InitSeqCountGen did not terminate after the final batch");
        end

        $finish;
    end
endmodule
