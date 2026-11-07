`timescale 1ps / 1ps
`default_nettype none

module tb_SeqSorterSmoke;
    import rst_pkg::*;

    localparam int W8 = PIPE_WIDTH_SEQ2;
    localparam int W10 = PIPE_WIDTH_SEQ3;
    localparam int W12 = PIPE_WIDTH_SEQ4;
    localparam int W14 = PIPE_WIDTH_SEQ5;

    hashed_update_t i_updates8 [W8];
    hashed_update_t o_updates8 [W8];
    hashed_update_t expected8 [W8];
    hashed_update_t i_updates10 [W10];
    hashed_update_t o_updates10 [W10];
    hashed_update_t expected10 [W10];
    hashed_update_t i_updates12 [W12];
    hashed_update_t o_updates12 [W12];
    hashed_update_t expected12 [W12];
    hashed_update_t i_updates14 [W14];
    hashed_update_t o_updates14 [W14];
    hashed_update_t expected14 [W14];

    SeqSorter #(
        .PIPE_WIDTH(W8)
    ) dut8 (
        .i_updates(i_updates8),
        .o_updates(o_updates8)
    );

    SeqSorter #(
        .PIPE_WIDTH(W10)
    ) dut10 (
        .i_updates(i_updates10),
        .o_updates(o_updates10)
    );

    SeqSorter #(
        .PIPE_WIDTH(W12)
    ) dut12 (
        .i_updates(i_updates12),
        .o_updates(o_updates12)
    );

    SeqSorter #(
        .PIPE_WIDTH(W14)
    ) dut14 (
        .i_updates(i_updates14),
        .o_updates(o_updates14)
    );

    task automatic seed_valid(
        output hashed_update_t update,
        input int bank_idx,
        input int set_idx,
        input logic inc,
        input seq_t seq
    );
        begin
            update = '0;
            update.valid = 1'b1;
            update.bank_idx = bank_idx[$bits(update.bank_idx)-1:0];
            update.set_idx = set_idx[$bits(update.set_idx)-1:0];
            update.inc = inc;
            update.seq = seq;
        end
    endtask

    task automatic seed_invalid(
        output hashed_update_t update,
        input int bank_idx,
        input int set_idx,
        input logic inc,
        input seq_t seq
    );
        begin
            update = '0;
            update.valid = 1'b0;
            update.bank_idx = bank_idx[$bits(update.bank_idx)-1:0];
            update.set_idx = set_idx[$bits(update.set_idx)-1:0];
            update.inc = inc;
            update.seq = seq;
        end
    endtask

    task automatic clear_all;
        begin
            for (int i = 0; i < W8; i++) begin
                i_updates8[i] = '0;
                expected8[i] = '0;
            end
            for (int i = 0; i < W10; i++) begin
                i_updates10[i] = '0;
                expected10[i] = '0;
            end
            for (int i = 0; i < W12; i++) begin
                i_updates12[i] = '0;
                expected12[i] = '0;
            end
            for (int i = 0; i < W14; i++) begin
                i_updates14[i] = '0;
                expected14[i] = '0;
            end
        end
    endtask

    task automatic expect_update_eq(
        input string label,
        input int idx,
        input hashed_update_t actual,
        input hashed_update_t expected
    );
        begin
            if (actual !== expected) begin
                $fatal(1, "%s[%0d] mismatch got=%p expected=%p", label, idx, actual, expected);
            end
        end
    endtask

    task automatic expect_invalid(
        input string label,
        input int idx,
        input hashed_update_t actual
    );
        begin
            if (actual.valid) begin
                $fatal(1, "%s[%0d] expected invalid suffix but got valid=%p", label, idx, actual);
            end
        end
    endtask

    initial begin
        clear_all();

        seed_valid(i_updates8[0], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h005});
        seed_valid(i_updates8[1], 1, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h001, 9'h003});
        seed_valid(i_updates8[2], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h003});
        seed_valid(i_updates8[3], 0, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(expected8[0], 0, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(expected8[1], 1, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h001, 9'h003});
        seed_valid(expected8[2], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h003});
        seed_valid(expected8[3], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h005});

        seed_valid(i_updates10[0], 1, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h002});
        seed_valid(i_updates10[1], 1, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h002});
        seed_valid(i_updates10[2], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(i_updates10[3], 0, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(i_updates10[4], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h004});
        seed_valid(expected10[0], 0, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(expected10[1], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(expected10[2], 1, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h002});
        seed_valid(expected10[3], 1, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h002});
        seed_valid(expected10[4], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h004});

        seed_valid(i_updates12[0], 1, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h002});
        seed_valid(i_updates12[1], 1, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h001, 9'h002});
        seed_valid(i_updates12[2], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h002});
        seed_valid(i_updates12[3], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h004});
        seed_valid(i_updates12[4], 0, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(expected12[0], 0, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(expected12[1], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h002});
        seed_valid(expected12[2], 1, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h001, 9'h002});
        seed_valid(expected12[3], 1, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h002});
        seed_valid(expected12[4], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h004});

        seed_valid(i_updates14[0], 1, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h002, 9'h005});
        seed_valid(i_updates14[1], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(i_updates14[2], 0, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(i_updates14[3], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h002});
        seed_valid(i_updates14[4], 1, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h001});
        seed_valid(i_updates14[5], 0, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h003});
        seed_valid(expected14[0], 0, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(expected14[1], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(expected14[2], 0, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h003});
        seed_valid(expected14[3], 1, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h001});
        seed_valid(expected14[4], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h002});
        seed_valid(expected14[5], 1, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h002, 9'h005});

        #1;
        for (int i = 0; i < 4; i++) begin
            expect_update_eq("case1_w8", i, o_updates8[i], expected8[i]);
        end
        for (int i = 4; i < W8; i++) begin
            expect_invalid("case1_w8", i, o_updates8[i]);
        end

        for (int i = 0; i < 5; i++) begin
            expect_update_eq("case1_w10", i, o_updates10[i], expected10[i]);
        end
        for (int i = 5; i < W10; i++) begin
            expect_invalid("case1_w10", i, o_updates10[i]);
        end

        for (int i = 0; i < 5; i++) begin
            expect_update_eq("case1_w12", i, o_updates12[i], expected12[i]);
        end
        for (int i = 5; i < W12; i++) begin
            expect_invalid("case1_w12", i, o_updates12[i]);
        end

        for (int i = 0; i < 6; i++) begin
            expect_update_eq("case1_w14", i, o_updates14[i], expected14[i]);
        end
        for (int i = 6; i < W14; i++) begin
            expect_invalid("case1_w14", i, o_updates14[i]);
        end

        for (int i = 0; i < W14; i++) begin
            i_updates14[i] = '0;
            expected14[i] = '0;
        end

        seed_valid(i_updates14[0], 1, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h001, 9'h000});
        seed_valid(i_updates14[1], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h002});
        seed_valid(i_updates14[2], 0, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_invalid(i_updates14[3], 1, 1, 1'b1, {9'h001, 9'h002, 9'h003, 9'h004, 9'h005});
        seed_invalid(i_updates14[4], 1, 0, 1'b0, {9'h000, 9'h010, 9'h020, 9'h030, 9'h040});
        seed_invalid(i_updates14[5], 0, 1, 1'b1, {9'h001, 9'h001, 9'h001, 9'h001, 9'h001});
        seed_valid(expected14[0], 0, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_valid(expected14[1], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h002});
        seed_valid(expected14[2], 1, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h001, 9'h000});

        #1;
        for (int i = 0; i < 3; i++) begin
            expect_update_eq("case2_w14", i, o_updates14[i], expected14[i]);
        end
        for (int i = 3; i < W14; i++) begin
            expect_invalid("case2_w14", i, o_updates14[i]);
        end

        $finish;
    end
endmodule
