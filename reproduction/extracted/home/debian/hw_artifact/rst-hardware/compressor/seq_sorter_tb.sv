`timescale 1ps / 1ps
`default_nettype none

module tb_SeqSorter;
    import rst_pkg::*;

    localparam int W8 = PIPE_WIDTH_SEQ2;
    localparam int W10 = PIPE_WIDTH_SEQ3;
    localparam int W12 = PIPE_WIDTH_SEQ4;
    localparam int W14 = PIPE_WIDTH_SEQ5;

    hashed_update_t i_updates8 [W8];
    hashed_update_t o_updates8 [W8];
    hashed_update_t i_updates10 [W10];
    hashed_update_t o_updates10 [W10];
    hashed_update_t i_updates12 [W12];
    hashed_update_t o_updates12 [W12];
    hashed_update_t i_updates14 [W14];
    hashed_update_t o_updates14 [W14];

    function automatic logic comes_before(
        input hashed_update_t lhs,
        input hashed_update_t rhs
    );
        if (lhs.valid != rhs.valid) begin
            return lhs.valid && !rhs.valid;
        end
        if (!lhs.valid && !rhs.valid) begin
            return 1'b0;
        end
        if (lhs.bank_idx != rhs.bank_idx) begin
            return lhs.bank_idx < rhs.bank_idx;
        end
        if (lhs.seq != rhs.seq) begin
            return lhs.seq < rhs.seq;
        end
        if (lhs.inc != rhs.inc) begin
            return lhs.inc < rhs.inc;
        end
        return 1'b0;
    endfunction

    task automatic swap_update(ref hashed_update_t lhs, ref hashed_update_t rhs);
        hashed_update_t tmp;
        begin
            tmp = lhs;
            lhs = rhs;
            rhs = tmp;
        end
    endtask

    task automatic sort_updates8(ref hashed_update_t updates[W8]);
        begin
            for (int i = 0; i < W8; i++) begin
                for (int j = i + 1; j < W8; j++) begin
                    if (comes_before(updates[j], updates[i])) begin
                        swap_update(updates[i], updates[j]);
                    end
                end
            end
        end
    endtask

    task automatic sort_updates10(ref hashed_update_t updates[W10]);
        begin
            for (int i = 0; i < W10; i++) begin
                for (int j = i + 1; j < W10; j++) begin
                    if (comes_before(updates[j], updates[i])) begin
                        swap_update(updates[i], updates[j]);
                    end
                end
            end
        end
    endtask

    task automatic sort_updates12(ref hashed_update_t updates[W12]);
        begin
            for (int i = 0; i < W12; i++) begin
                for (int j = i + 1; j < W12; j++) begin
                    if (comes_before(updates[j], updates[i])) begin
                        swap_update(updates[i], updates[j]);
                    end
                end
            end
        end
    endtask

    task automatic sort_updates14(ref hashed_update_t updates[W14]);
        begin
            for (int i = 0; i < W14; i++) begin
                for (int j = i + 1; j < W14; j++) begin
                    if (comes_before(updates[j], updates[i])) begin
                        swap_update(updates[i], updates[j]);
                    end
                end
            end
        end
    endtask

    task automatic dump_updates(
        input string label,
        input int count,
        input hashed_update_t updates[]
    );
        begin
            $display("%s:", label);
            for (int i = 0; i < count; i++) begin
                $display("  [%0d] valid=%0b bank=%0d set=%0d inc=%0b seq=%p",
                    i, updates[i].valid, updates[i].bank_idx, updates[i].set_idx, updates[i].inc, updates[i].seq);
            end
        end
    endtask

    task automatic compare_updates(
        input string label,
        input int count,
        input hashed_update_t expected[],
        input hashed_update_t actual[]
    );
        begin
            dump_updates({label, " expected"}, count, expected);
            dump_updates({label, " actual"}, count, actual);
            for (int i = 0; i < count; i++) begin
                if (expected[i] !== actual[i]) begin
                    $fatal(1, "%s mismatch at %0d", label, i);
                end
            end
        end
    endtask

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

    task automatic seed_update(
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

    initial begin
        hashed_update_t ref8 [W8];
        hashed_update_t ref10 [W10];
        hashed_update_t ref12 [W12];
        hashed_update_t ref14 [W14];

        for (int i = 0; i < W8; i++) i_updates8[i] = '0;
        for (int i = 0; i < W10; i++) i_updates10[i] = '0;
        for (int i = 0; i < W12; i++) i_updates12[i] = '0;
        for (int i = 0; i < W14; i++) i_updates14[i] = '0;

        seed_update(i_updates8[0], 2, 3, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h005});
        seed_update(i_updates8[1], 1, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h001, 9'h003});
        seed_update(i_updates8[2], 1, 2, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h003});
        seed_update(i_updates8[3], 0, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});

        seed_update(i_updates10[0], 3, 2, 1'b1, {9'h000, 9'h000, 9'h000, 9'h010, 9'h001});
        seed_update(i_updates10[1], 2, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h005});
        seed_update(i_updates10[2], 2, 0, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h005});
        seed_update(i_updates10[3], 1, 7, 1'b1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h000});
        seed_update(i_updates10[4], 0, 2, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});

        seed_update(i_updates12[0], 2, 0, 1'b1, {9'h000, 9'h000, 9'h001, 9'h002, 9'h003});
        seed_update(i_updates12[1], 2, 0, 1'b0, {9'h000, 9'h000, 9'h001, 9'h002, 9'h003});
        seed_update(i_updates12[2], 1, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h002});
        seed_update(i_updates12[3], 3, 4, 1'b1, {9'h000, 9'h000, 9'h004, 9'h005, 9'h006});
        seed_update(i_updates12[4], 0, 0, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});

        seed_update(i_updates14[0], 4, 2, 1'b1, {9'h001, 9'h002, 9'h003, 9'h004, 9'h005});
        seed_update(i_updates14[1], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_update(i_updates14[2], 0, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h001});
        seed_update(i_updates14[3], 2, 3, 1'b1, {9'h000, 9'h000, 9'h000, 9'h002, 9'h002});
        seed_update(i_updates14[4], 2, 2, 1'b1, {9'h000, 9'h000, 9'h000, 9'h002, 9'h001});
        seed_update(i_updates14[5], 1, 5, 1'b0, {9'h000, 9'h000, 9'h000, 9'h001, 9'h007});

        for (int i = 0; i < W8; i++) ref8[i] = i_updates8[i];
        for (int i = 0; i < W10; i++) ref10[i] = i_updates10[i];
        for (int i = 0; i < W12; i++) ref12[i] = i_updates12[i];
        for (int i = 0; i < W14; i++) ref14[i] = i_updates14[i];

        sort_updates8(ref8);
        sort_updates10(ref10);
        sort_updates12(ref12);
        sort_updates14(ref14);

        #1;
        compare_updates("8-wide", W8, ref8, o_updates8);
        compare_updates("10-wide", W10, ref10, o_updates10);
        compare_updates("12-wide", W12, ref12, o_updates12);
        compare_updates("14-wide", W14, ref14, o_updates14);

        $finish;
    end
endmodule
