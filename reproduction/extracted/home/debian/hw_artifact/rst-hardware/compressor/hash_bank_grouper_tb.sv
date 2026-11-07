`timescale 1ps / 1ps
`default_nettype none

module tb_HashBankGrouper;
    import rst_pkg::*;

    localparam int W = PIPE_WIDTH_SEQ3;
    localparam int NUM_BANKS = BANKS_SEQ3;

    typedef agg_update_t bank_updates_t [W];

    agg_update_t i_updates [W];
    logic [$clog2(W + 1)-1:0] i_count;
    bank_updates_t o_updates [NUM_BANKS];
    logic [$clog2(W + 1)-1:0] o_counts [NUM_BANKS];

    BankGrouper #(
        .PIPE_WIDTH(W),
        .NUM_BANKS(NUM_BANKS)
    ) dut (
        .i_updates(i_updates),
        .i_count(i_count),
        .o_updates(o_updates),
        .o_counts(o_counts)
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

    initial begin
        for (int i = 0; i < W; i++) begin
            i_updates[i] = '0;
        end

        // BankGrouper now relies on the bank-major order produced by the
        // sorter+aggregator path in UpdatePipelineN.
        seed_update(i_updates[0], 0, 1, {9'h000, 9'h000, 9'h000, 9'h010, 9'h001}, 3);
        seed_update(i_updates[1], 0, 3, {9'h000, 9'h000, 9'h000, 9'h030, 9'h003}, 1);
        seed_update(i_updates[2], 2, 2, {9'h000, 9'h000, 9'h000, 9'h020, 9'h002}, -1);
        seed_update(i_updates[3], 6, 4, {9'h000, 9'h000, 9'h000, 9'h040, 9'h004}, 2);
        i_count = 4;

        #1;
        if (o_counts[0] !== 2 || o_counts[2] !== 1 || o_counts[6] !== 1) begin
            $fatal(1, "bank counts were not grouped correctly");
        end
        if (!o_updates[0][0].valid || o_updates[0][0].count !== 3 || o_updates[0][0].set_idx !== 1) begin
            $fatal(1, "first bank-0 entry mismatch");
        end
        if (!o_updates[0][1].valid || o_updates[0][1].count !== 1 || o_updates[0][1].set_idx !== 3) begin
            $fatal(1, "second bank-0 entry mismatch");
        end
        if (!o_updates[2][0].valid || o_updates[2][0].count !== -1) begin
            $fatal(1, "bank-2 entry mismatch");
        end
        if (!o_updates[6][0].valid || o_updates[6][0].count !== 2) begin
            $fatal(1, "bank-6 entry mismatch");
        end
        $finish;
    end
endmodule
