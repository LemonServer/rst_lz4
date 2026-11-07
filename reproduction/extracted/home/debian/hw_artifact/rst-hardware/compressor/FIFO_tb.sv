`timescale 1ps / 1ps
`default_nettype none

module tb_FIFO;
    import rst_pkg::*;

    localparam int W = PIPE_WIDTH_SEQ2;
    localparam int DEPTH = 3;

    logic clk;
    logic rst;
    agg_update_t i_batch [W];
    logic [$clog2(W + 1)-1:0] i_count;
    logic i_valid;
    logic i_busy;
    logic [$clog2(DEPTH + 1)-1:0] free_slots;
    agg_update_t o_data;
    logic o_valid;
    logic o_busy;
    logic empty;

    FIFO #(
        .PIPE_WIDTH(W),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .i_batch(i_batch),
        .i_count(i_count),
        .i_valid(i_valid),
        .i_busy(i_busy),
        .free_slots(free_slots),
        .o_data(o_data),
        .o_valid(o_valid),
        .o_busy(o_busy),
        .empty(empty)
    );

    task automatic seed_update(
        output agg_update_t update,
        input int bank_idx,
        input int set_idx,
        input seq_t seq,
        input int count
    );
        begin
            update = '0;
            update.valid = 1'b1;
            update.bank_idx = bank_idx[$bits(update.bank_idx)-1:0];
            update.set_idx = set_idx[$bits(update.set_idx)-1:0];
            update.seq = seq;
            update.count = count;
        end
    endtask

    task automatic clear_batch;
        for (int i = 0; i < W; i++) begin
            i_batch[i] = '0;
        end
    endtask

    task automatic expect_pop(
        input string label,
        input int exp_count,
        input int exp_bank,
        input int exp_set,
        input logic expect_valid_after,
        input logic expect_empty_after
    );
        begin
            $display("%s pop: valid=%0b bank=%0d set=%0d count=%0d empty=%0b",
                label, o_valid, o_data.bank_idx, o_data.set_idx, o_data.count, empty);
            if (!o_data.valid || o_data.count !== exp_count ||
                o_data.bank_idx !== exp_bank || o_data.set_idx !== exp_set) begin
                $fatal(1, "%s mismatch", label);
            end
            if (o_valid !== expect_valid_after || empty !== expect_empty_after) begin
                $fatal(1, "%s post-pop status mismatch", label);
            end
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        i_valid = 1'b0;
        i_count = '0;
        o_busy = 1'b1;
        clear_batch();

        #12;
        rst = 1'b0;

        $display("FIFO depth=%0d, pipe width=%0d", DEPTH, W);

        seed_update(i_batch[0], 0, 1, {9'h000, 9'h000, 9'h000, 9'h001, 9'h010}, 3);
        seed_update(i_batch[1], 1, 2, {9'h000, 9'h000, 9'h000, 9'h002, 9'h020}, -1);
        seed_update(i_batch[2], 2, 3, {9'h000, 9'h000, 9'h000, 9'h003, 9'h030}, 5);
        i_count = 3;
        i_valid = 1'b1;
        #1;
        if (i_busy) begin
            $fatal(1, "FIFO unexpectedly reported busy on the first push");
        end

        #9;
        i_valid = 1'b0;
        i_count = '0;
        o_busy = 1'b0;

        #4;
        expect_pop("drain-1", 3, 0, 1, 1'b1, 1'b0);
        #10;
        expect_pop("drain-2", -1, 1, 2, 1'b1, 1'b0);
        #10;
        expect_pop("drain-3", 5, 2, 3, 1'b0, 1'b1);

        clear_batch();
        seed_update(i_batch[0], 3, 4, {9'h000, 9'h000, 9'h000, 9'h004, 9'h040}, 7);
        seed_update(i_batch[1], 4, 5, {9'h000, 9'h000, 9'h000, 9'h005, 9'h050}, 9);
        seed_update(i_batch[2], 5, 6, {9'h000, 9'h000, 9'h000, 9'h006, 9'h060}, 11);
        seed_update(i_batch[3], 6, 7, {9'h000, 9'h000, 9'h000, 9'h007, 9'h070}, 13);
        i_count = 4;
        i_valid = 1'b1;
        o_busy = 1'b1;
        #1;
        if (!i_busy) begin
            $fatal(1, "FIFO failed to assert busy on overflow attempt");
        end
        #9;
        i_valid = 1'b0;
        i_count = '0;
        #1;
        if (!empty) begin
            $fatal(1, "overflow attempt should not have changed FIFO occupancy");
        end

        clear_batch();
        seed_update(i_batch[0], 7, 8, {9'h000, 9'h000, 9'h000, 9'h008, 9'h080}, 21);
        seed_update(i_batch[1], 8, 9, {9'h000, 9'h000, 9'h000, 9'h009, 9'h090}, 23);
        seed_update(i_batch[2], 9, 10, {9'h000, 9'h000, 9'h000, 9'h00A, 9'h0A0}, 25);
        i_count = 3;
        i_valid = 1'b1;
        o_busy = 1'b1;
        #1;
        if (i_busy) begin
            $fatal(1, "FIFO should accept a fresh 3-entry push after the rejected one");
        end
        #9;
        i_valid = 1'b0;
        i_count = '0;
        o_busy = 1'b0;

        #9;
        expect_pop("wrap-1", 21, 7, 8, 1'b1, 1'b0);
        #10;
        expect_pop("wrap-2", 23, 8, 9, 1'b1, 1'b0);
        #10;
        expect_pop("wrap-3", 25, 9, 10, 1'b0, 1'b1);

        $finish;
    end
endmodule
