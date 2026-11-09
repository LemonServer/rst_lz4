`timescale 1ps / 1ps
`default_nettype none

module tb_SeqSorterPipelineVariants;
    import rst_pkg::*;

    localparam int W8 = PIPE_WIDTH_SEQ2;
    localparam int W10 = PIPE_WIDTH_SEQ3;
    localparam int W12 = PIPE_WIDTH_SEQ4;
    localparam int W14 = PIPE_WIDTH_SEQ5;
    localparam int ACTIVE_CYCLES = 24;

    logic clk;
    logic rst;
    logic i_valid;

    hashed_update_t i_updates8 [W8];
    hashed_update_t i_updates10 [W10];
    hashed_update_t i_updates12 [W12];
    hashed_update_t i_updates14 [W14];

    hashed_update_t golden8 [W8];
    hashed_update_t golden10 [W10];
    hashed_update_t golden12 [W12];
    hashed_update_t golden14 [W14];

    hashed_update_t pipe1_8 [W8];
    hashed_update_t pipe1_10 [W10];
    hashed_update_t pipe1_12 [W12];
    hashed_update_t pipe1_14 [W14];
    hashed_update_t pipe2_8 [W8];
    hashed_update_t pipe2_10 [W10];
    hashed_update_t pipe2_12 [W12];
    hashed_update_t pipe2_14 [W14];
    hashed_update_t pipe3_8 [W8];
    hashed_update_t pipe3_10 [W10];
    hashed_update_t pipe3_12 [W12];
    hashed_update_t pipe3_14 [W14];

    logic pipe1_valid_8;
    logic pipe1_valid_10;
    logic pipe1_valid_12;
    logic pipe1_valid_14;
    logic pipe2_valid_8;
    logic pipe2_valid_10;
    logic pipe2_valid_12;
    logic pipe2_valid_14;
    logic pipe3_valid_8;
    logic pipe3_valid_10;
    logic pipe3_valid_12;
    logic pipe3_valid_14;

    hashed_update_t prev1_8 [W8];
    hashed_update_t prev1_10 [W10];
    hashed_update_t prev1_12 [W12];
    hashed_update_t prev1_14 [W14];
    hashed_update_t prev2_8 [W8];
    hashed_update_t prev2_10 [W10];
    hashed_update_t prev2_12 [W12];
    hashed_update_t prev2_14 [W14];

    logic prev1_valid;
    logic prev2_valid;

    always #5 clk = ~clk;

    SeqSorter #(
        .PIPE_WIDTH(W8)
    ) golden_sorter8 (
        .i_updates(i_updates8),
        .o_updates(golden8)
    );

    SeqSorter #(
        .PIPE_WIDTH(W10)
    ) golden_sorter10 (
        .i_updates(i_updates10),
        .o_updates(golden10)
    );

    SeqSorter #(
        .PIPE_WIDTH(W12)
    ) golden_sorter12 (
        .i_updates(i_updates12),
        .o_updates(golden12)
    );

    SeqSorter #(
        .PIPE_WIDTH(W14)
    ) golden_sorter14 (
        .i_updates(i_updates14),
        .o_updates(golden14)
    );

    SeqSorterPipe1 #(
        .PIPE_WIDTH(W8)
    ) pipe1_sorter8 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates8),
        .o_valid(pipe1_valid_8),
        .o_updates(pipe1_8)
    );

    SeqSorterPipe1 #(
        .PIPE_WIDTH(W10)
    ) pipe1_sorter10 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates10),
        .o_valid(pipe1_valid_10),
        .o_updates(pipe1_10)
    );

    SeqSorterPipe1 #(
        .PIPE_WIDTH(W12)
    ) pipe1_sorter12 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates12),
        .o_valid(pipe1_valid_12),
        .o_updates(pipe1_12)
    );

    SeqSorterPipe1 #(
        .PIPE_WIDTH(W14)
    ) pipe1_sorter14 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates14),
        .o_valid(pipe1_valid_14),
        .o_updates(pipe1_14)
    );

    SeqSorterPipe2 #(
        .PIPE_WIDTH(W8)
    ) pipe2_sorter8 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates8),
        .o_valid(pipe2_valid_8),
        .o_updates(pipe2_8)
    );

    SeqSorterPipe2 #(
        .PIPE_WIDTH(W10)
    ) pipe2_sorter10 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates10),
        .o_valid(pipe2_valid_10),
        .o_updates(pipe2_10)
    );

    SeqSorterPipe2 #(
        .PIPE_WIDTH(W12)
    ) pipe2_sorter12 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates12),
        .o_valid(pipe2_valid_12),
        .o_updates(pipe2_12)
    );

    SeqSorterPipe2 #(
        .PIPE_WIDTH(W14)
    ) pipe2_sorter14 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates14),
        .o_valid(pipe2_valid_14),
        .o_updates(pipe2_14)
    );

    SeqSorterPipe3 #(
        .PIPE_WIDTH(W8)
    ) pipe3_sorter8 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates8),
        .o_valid(pipe3_valid_8),
        .o_updates(pipe3_8)
    );

    SeqSorterPipe3 #(
        .PIPE_WIDTH(W10)
    ) pipe3_sorter10 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates10),
        .o_valid(pipe3_valid_10),
        .o_updates(pipe3_10)
    );

    SeqSorterPipe3 #(
        .PIPE_WIDTH(W12)
    ) pipe3_sorter12 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates12),
        .o_valid(pipe3_valid_12),
        .o_updates(pipe3_12)
    );

    SeqSorterPipe3 #(
        .PIPE_WIDTH(W14)
    ) pipe3_sorter14 (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .i_updates(i_updates14),
        .o_valid(pipe3_valid_14),
        .o_updates(pipe3_14)
    );

    function automatic hashed_update_t make_update(
        input int cycle,
        input int salt,
        input int slot
    );
        hashed_update_t update;
        int bank_val;
        int set_val;
        logic [63:0] seq_bits;
        begin
            bank_val = cycle * 3 + salt + slot;
            set_val = cycle * 11 + salt * 5 + slot * 7;
            update = '0;
            update.valid = (((cycle + salt + slot) % 4) != 0);
            update.bank_idx = bank_val[$bits(update.bank_idx)-1:0];
            update.set_idx = set_val[$bits(update.set_idx)-1:0];
            update.inc = ((cycle ^ salt ^ slot) & 1);
            seq_bits = {
                32'(cycle * 17 + salt * 13 + slot * 29),
                32'(cycle * 31 + salt * 19 + slot * 37)
            };
            update.seq = seq_t'(seq_bits[$bits(seq_t)-1:0]);
            return update;
        end
    endfunction

    task automatic fill_updates8(input int cycle, input int salt);
        begin
            for (int i = 0; i < W8; i++) begin
                i_updates8[i] = make_update(cycle, salt, i);
            end
            i_updates8[1] = i_updates8[0];
            i_updates8[W8 - 2] = i_updates8[2];
            i_updates8[W8 - 2].valid = 1'b0;
            if ((cycle % 3) == 0) begin
                i_updates8[W8 - 1].valid = 1'b0;
            end
        end
    endtask

    task automatic fill_updates10(input int cycle, input int salt);
        begin
            for (int i = 0; i < W10; i++) begin
                i_updates10[i] = make_update(cycle, salt, i);
            end
            i_updates10[1] = i_updates10[0];
            i_updates10[W10 - 2] = i_updates10[2];
            i_updates10[W10 - 2].valid = 1'b0;
            if ((cycle % 3) == 0) begin
                i_updates10[W10 - 1].valid = 1'b0;
            end
        end
    endtask

    task automatic fill_updates12(input int cycle, input int salt);
        begin
            for (int i = 0; i < W12; i++) begin
                i_updates12[i] = make_update(cycle, salt, i);
            end
            i_updates12[1] = i_updates12[0];
            i_updates12[W12 - 2] = i_updates12[2];
            i_updates12[W12 - 2].valid = 1'b0;
            if ((cycle % 3) == 0) begin
                i_updates12[W12 - 1].valid = 1'b0;
            end
        end
    endtask

    task automatic fill_updates14(input int cycle, input int salt);
        begin
            for (int i = 0; i < W14; i++) begin
                i_updates14[i] = make_update(cycle, salt, i);
            end
            i_updates14[1] = i_updates14[0];
            i_updates14[W14 - 2] = i_updates14[2];
            i_updates14[W14 - 2].valid = 1'b0;
            if ((cycle % 3) == 0) begin
                i_updates14[W14 - 1].valid = 1'b0;
            end
        end
    endtask

    task automatic clear_inputs;
        begin
            for (int i = 0; i < W8; i++) begin
                i_updates8[i] = '0;
            end
            for (int i = 0; i < W10; i++) begin
                i_updates10[i] = '0;
            end
            for (int i = 0; i < W12; i++) begin
                i_updates12[i] = '0;
            end
            for (int i = 0; i < W14; i++) begin
                i_updates14[i] = '0;
            end
        end
    endtask

    task automatic clear_histories;
        begin
            for (int i = 0; i < W8; i++) begin
                prev1_8[i] = '0;
                prev2_8[i] = '0;
            end
            for (int i = 0; i < W10; i++) begin
                prev1_10[i] = '0;
                prev2_10[i] = '0;
            end
            for (int i = 0; i < W12; i++) begin
                prev1_12[i] = '0;
                prev2_12[i] = '0;
            end
            for (int i = 0; i < W14; i++) begin
                prev1_14[i] = '0;
                prev2_14[i] = '0;
            end
        end
    endtask

    task automatic expect_updates(
        input string label,
        input int count,
        input hashed_update_t expected[],
        input hashed_update_t actual[]
    );
        begin
            for (int i = 0; i < count; i++) begin
                if (expected[i] !== actual[i]) begin
                    $fatal(1, "%s mismatch at %0d got=%p expected=%p", label, i, actual[i], expected[i]);
                end
            end
        end
    endtask

    task automatic expect_valid(
        input string label,
        input logic actual,
        input logic expected
    );
        begin
            if (actual !== expected) begin
                $fatal(1, "%s valid mismatch got=%0b expected=%0b", label, actual, expected);
            end
        end
    endtask

    task automatic shift_histories;
        begin
            for (int i = 0; i < W8; i++) begin
                prev2_8[i] = prev1_8[i];
                prev1_8[i] = golden8[i];
            end
            for (int i = 0; i < W10; i++) begin
                prev2_10[i] = prev1_10[i];
                prev1_10[i] = golden10[i];
            end
            for (int i = 0; i < W12; i++) begin
                prev2_12[i] = prev1_12[i];
                prev1_12[i] = golden12[i];
            end
            for (int i = 0; i < W14; i++) begin
                prev2_14[i] = prev1_14[i];
                prev1_14[i] = golden14[i];
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        i_valid = 1'b0;
        prev1_valid = 1'b0;
        prev2_valid = 1'b0;

        clear_inputs();
        clear_histories();

        repeat (2) begin
            @(posedge clk);
            #1;
            expect_valid("reset_pipe1_w8", pipe1_valid_8, 1'b0);
            expect_valid("reset_pipe2_w8", pipe2_valid_8, 1'b0);
            expect_valid("reset_pipe3_w8", pipe3_valid_8, 1'b0);
        end

        rst = 1'b0;

        for (int cycle = 0; cycle < ACTIVE_CYCLES; cycle++) begin
            fill_updates8(cycle, 8);
            fill_updates10(cycle, 10);
            fill_updates12(cycle, 12);
            fill_updates14(cycle, 14);
            i_valid = 1'b1;

            @(posedge clk);
            #1;

            expect_valid("pipe1_w8", pipe1_valid_8, 1'b1);
            expect_valid("pipe1_w10", pipe1_valid_10, 1'b1);
            expect_valid("pipe1_w12", pipe1_valid_12, 1'b1);
            expect_valid("pipe1_w14", pipe1_valid_14, 1'b1);
            expect_valid("pipe2_w8", pipe2_valid_8, prev1_valid);
            expect_valid("pipe2_w10", pipe2_valid_10, prev1_valid);
            expect_valid("pipe2_w12", pipe2_valid_12, prev1_valid);
            expect_valid("pipe2_w14", pipe2_valid_14, prev1_valid);
            expect_valid("pipe3_w8", pipe3_valid_8, prev2_valid);
            expect_valid("pipe3_w10", pipe3_valid_10, prev2_valid);
            expect_valid("pipe3_w12", pipe3_valid_12, prev2_valid);
            expect_valid("pipe3_w14", pipe3_valid_14, prev2_valid);

            expect_updates("pipe1_w8", W8, golden8, pipe1_8);
            expect_updates("pipe1_w10", W10, golden10, pipe1_10);
            expect_updates("pipe1_w12", W12, golden12, pipe1_12);
            expect_updates("pipe1_w14", W14, golden14, pipe1_14);

            if (prev1_valid) begin
                expect_updates("pipe2_w8", W8, prev1_8, pipe2_8);
                expect_updates("pipe2_w10", W10, prev1_10, pipe2_10);
                expect_updates("pipe2_w12", W12, prev1_12, pipe2_12);
                expect_updates("pipe2_w14", W14, prev1_14, pipe2_14);
            end

            if (prev2_valid) begin
                expect_updates("pipe3_w8", W8, prev2_8, pipe3_8);
                expect_updates("pipe3_w10", W10, prev2_10, pipe3_10);
                expect_updates("pipe3_w12", W12, prev2_12, pipe3_12);
                expect_updates("pipe3_w14", W14, prev2_14, pipe3_14);
            end

            shift_histories();
            prev2_valid = prev1_valid;
            prev1_valid = 1'b1;
        end

        i_valid = 1'b0;
        clear_inputs();

        repeat (2) begin
            @(posedge clk);
            #1;

            expect_valid("drain_pipe1_w8", pipe1_valid_8, 1'b0);
            expect_valid("drain_pipe2_w8", pipe2_valid_8, prev1_valid);
            expect_valid("drain_pipe3_w8", pipe3_valid_8, prev2_valid);

            if (prev1_valid) begin
                expect_updates("drain_pipe2_w8", W8, prev1_8, pipe2_8);
                expect_updates("drain_pipe2_w10", W10, prev1_10, pipe2_10);
                expect_updates("drain_pipe2_w12", W12, prev1_12, pipe2_12);
                expect_updates("drain_pipe2_w14", W14, prev1_14, pipe2_14);
            end

            if (prev2_valid) begin
                expect_updates("drain_pipe3_w8", W8, prev2_8, pipe3_8);
                expect_updates("drain_pipe3_w10", W10, prev2_10, pipe3_10);
                expect_updates("drain_pipe3_w12", W12, prev2_12, pipe3_12);
                expect_updates("drain_pipe3_w14", W14, prev2_14, pipe3_14);
            end

            shift_histories();
            prev2_valid = prev1_valid;
            prev1_valid = 1'b0;
        end

        @(posedge clk);
        #1;
        expect_valid("final_pipe2_w8", pipe2_valid_8, 1'b0);
        expect_valid("final_pipe3_w8", pipe3_valid_8, prev2_valid);
        if (prev2_valid) begin
            expect_updates("final_pipe3_w8", W8, prev2_8, pipe3_8);
            expect_updates("final_pipe3_w10", W10, prev2_10, pipe3_10);
            expect_updates("final_pipe3_w12", W12, prev2_12, pipe3_12);
            expect_updates("final_pipe3_w14", W14, prev2_14, pipe3_14);
        end

        $finish;
    end
endmodule
