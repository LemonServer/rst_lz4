`timescale 1ps / 1ps
`default_nettype none

module tb_SeqAggregator;
    import rst_pkg::*;

    localparam int W10 = PIPE_WIDTH_SEQ3;
    localparam int W14 = PIPE_WIDTH_SEQ5;

    hashed_update_t i_updates10 [W10];
    logic [$clog2(W10 + 1)-1:0] o_count10;
    agg_update_t o_updates10 [W10];

    hashed_update_t i_updates14 [W14];
    logic [$clog2(W14 + 1)-1:0] o_count14;
    agg_update_t o_updates14 [W14];

    SeqAggregator #(
        .PIPE_WIDTH(W10)
    ) dut10 (
        .i_updates(i_updates10),
        .o_count(o_count10),
        .o_updates(o_updates10)
    );

    SeqAggregator #(
        .PIPE_WIDTH(W14)
    ) dut14 (
        .i_updates(i_updates14),
        .o_count(o_count14),
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

    task automatic clear_updates10;
        for (int i = 0; i < W10; i++) begin
            i_updates10[i] = '0;
        end
    endtask

    task automatic clear_updates14;
        for (int i = 0; i < W14; i++) begin
            i_updates14[i] = '0;
        end
    endtask

    task automatic show_groups10(input string label);
        begin
            $display("%s: groups=%0d", label, o_count10);
            for (int i = 0; i < o_count10; i++) begin
                $display("  g%0d bank=%0d set=%0d count=%0d valid=%0b",
                    i, o_updates10[i].bank_idx, o_updates10[i].set_idx, o_updates10[i].count, o_updates10[i].valid);
            end
        end
    endtask

    task automatic show_groups14(input string label);
        begin
            $display("%s: groups=%0d", label, o_count14);
            for (int i = 0; i < o_count14; i++) begin
                $display("  g%0d bank=%0d set=%0d count=%0d valid=%0b",
                    i, o_updates14[i].bank_idx, o_updates14[i].set_idx, o_updates14[i].count, o_updates14[i].valid);
            end
        end
    endtask

    initial begin
        clear_updates10();
        clear_updates14();

        seed_update(i_updates10[0], 0, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h011});
        seed_update(i_updates10[1], 0, 1, 1'b0, {9'h000, 9'h000, 9'h000, 9'h000, 9'h011});
        seed_update(i_updates10[2], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h011});
        seed_update(i_updates10[3], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h011});
        seed_update(i_updates10[4], 0, 1, 1'b1, {9'h000, 9'h000, 9'h000, 9'h000, 9'h011});
        seed_update(i_updates10[5], 2, 3, 1'b1, {9'h000, 9'h000, 9'h000, 9'h012, 9'h013});

        seed_update(i_updates14[0], 1, 2, 1'b1, {9'h000, 9'h000, 9'h000, 9'h020, 9'h001});
        seed_update(i_updates14[1], 1, 2, 1'b1, {9'h000, 9'h000, 9'h000, 9'h020, 9'h001});
        seed_update(i_updates14[2], 1, 2, 1'b0, {9'h000, 9'h000, 9'h000, 9'h020, 9'h001});
        seed_update(i_updates14[3], 1, 2, 1'b0, {9'h000, 9'h000, 9'h000, 9'h020, 9'h001});
        seed_update(i_updates14[4], 4, 5, 1'b1, {9'h000, 9'h000, 9'h000, 9'h030, 9'h002});
        seed_update(i_updates14[5], 4, 5, 1'b1, {9'h000, 9'h000, 9'h000, 9'h030, 9'h002});
        seed_update(i_updates14[6], 4, 5, 1'b1, {9'h000, 9'h000, 9'h000, 9'h030, 9'h002});
    end

    initial begin
        #1;

        show_groups10("20-wide");
        if (o_count10 !== 2) begin
            $fatal(1, "unexpected 20-wide aggregated count: %0d", o_count10);
        end
        if (!o_updates10[0].valid || o_updates10[0].count !== 1 || o_updates10[0].bank_idx !== 0 || o_updates10[0].set_idx !== 1) begin
            $fatal(1, "20-wide signed net aggregation failed");
        end
        if (!o_updates10[1].valid || o_updates10[1].count !== 1 || o_updates10[1].bank_idx !== 2 || o_updates10[1].set_idx !== 3) begin
            $fatal(1, "20-wide second group failed");
        end

        show_groups14("28-wide");
        if (o_count14 !== 1) begin
            $fatal(1, "unexpected 28-wide aggregated count: %0d", o_count14);
        end
        if (!o_updates14[0].valid || o_updates14[0].count !== 3 || o_updates14[0].bank_idx !== 4) begin
            $fatal(1, "28-wide surviving group failed");
        end

        clear_updates10();
        clear_updates14();
        #1;
        if (o_count10 !== 0 || o_count14 !== 0 || o_updates10[0].valid || o_updates14[0].valid) begin
            $fatal(1, "all-invalid input should yield no groups");
        end

        $finish;
    end
endmodule
