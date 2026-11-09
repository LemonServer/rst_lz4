`timescale 1ps / 1ps
`default_nettype none

module UpdatePipelineN
    import rst_pkg::*;
#(
    parameter int PIPE_WIDTH = PIPE_WIDTH_SEQ2,
    parameter int NUM_BANKS = BANKS_SEQ2,
    parameter int FIFO_DEPTH_P = FIFO_DEPTH
) (
    input  logic clk,
    input  logic rst,
    input  seq_update_t i_updates [PIPE_WIDTH],
    input  logic i_valid,
    output logic i_busy,
    output logic all_fifos_empty,
    output agg_update_t ht_updates [NUM_BANKS],
    output logic ht_update_valid [NUM_BANKS]
);
    localparam int COUNT_W = $clog2(PIPE_WIDTH + 1);
    localparam int FIFO_SPACE_W = $clog2(FIFO_DEPTH_P + 1);

    hashed_update_t hashed_updates [PIPE_WIDTH];
    hashed_update_t buffered_hashed_updates [PIPE_WIDTH];
    hashed_update_t sorted_updates [PIPE_WIDTH];
    logic sorter_accept;
    logic sorter_valid;
    logic sorter_busy_unused;
    logic launch_buffered;
    logic buffered_input_valid;
    logic sorter_active_r;
    hashed_update_t sorter_input_updates [PIPE_WIDTH];
    hashed_update_t sorted_stage_updates [PIPE_WIDTH];
    logic sorted_stage_valid;
    agg_update_t aggregated_updates [PIPE_WIDTH];
    logic [COUNT_W-1:0] aggregated_count;
    agg_update_t aggregated_stage_updates [PIPE_WIDTH];
    logic [COUNT_W-1:0] aggregated_stage_count;
    logic aggregated_stage_valid;
    agg_update_t grouped_updates [NUM_BANKS][PIPE_WIDTH];
    logic [COUNT_W-1:0] grouped_counts [NUM_BANKS];
    agg_update_t pending_updates [NUM_BANKS][PIPE_WIDTH];
    logic [COUNT_W-1:0] pending_counts [NUM_BANKS];
    agg_update_t fifo_ht_updates [NUM_BANKS];
    logic fifo_ht_update_valid [NUM_BANKS];
    logic fifo_push_req [NUM_BANKS];
    logic fifo_busy [NUM_BANKS];
    logic fifo_empty [NUM_BANKS];
    logic [FIFO_SPACE_W-1:0] fifo_free_slots [NUM_BANKS];
    logic [COUNT_W-1:0] fifo_push_counts [NUM_BANKS];
    logic pending_valid;

    function automatic logic [COUNT_W-1:0] min_push_count(
        input logic [COUNT_W-1:0] pending_count,
        input logic [FIFO_SPACE_W-1:0] free_slots
    );
        int unsigned pending_count_i;
        int unsigned free_slots_i;
        begin
            pending_count_i = pending_count;
            free_slots_i = free_slots;
            if (pending_count_i < free_slots_i) begin
                min_push_count = COUNT_W'(pending_count_i);
            end else begin
                min_push_count = COUNT_W'(free_slots_i);
            end
        end
    endfunction

    SeqHasher #(
        .PIPE_WIDTH(PIPE_WIDTH),
        .NUM_BANKS(NUM_BANKS)
    ) hasher (
        .i_updates(i_updates),
        .o_updates(hashed_updates)
    );

    SeqSorterStagedBest #(
        .PIPE_WIDTH(PIPE_WIDTH)
    ) sorter (
        .clk(clk),
        .rst(rst),
        .i_valid(sorter_accept),
        .i_updates(sorter_input_updates),
        .o_valid(sorter_valid),
        .o_busy(sorter_busy_unused),
        .o_updates(sorted_updates)
    );

    SeqAggregator #(
        .PIPE_WIDTH(PIPE_WIDTH)
    ) aggregator (
        .i_updates(sorted_stage_updates),
        .o_count(aggregated_count),
        .o_updates(aggregated_updates)
    );

    BankGrouper #(
        .PIPE_WIDTH(PIPE_WIDTH),
        .NUM_BANKS(NUM_BANKS)
    ) grouper (
        .i_updates(aggregated_stage_updates),
        .i_count(aggregated_stage_count),
        .o_updates(grouped_updates),
        .o_counts(grouped_counts)
    );

    generate
        for (genvar bank = 0; bank < NUM_BANKS; bank++) begin : gen_fifos
            assign fifo_push_counts[bank] = min_push_count(pending_counts[bank], fifo_free_slots[bank]);
            assign fifo_push_req[bank] = pending_valid && (fifo_push_counts[bank] != 0);

            FIFO #(
                .PIPE_WIDTH(PIPE_WIDTH),
                .DEPTH(FIFO_DEPTH_P)
            ) fifo_inst (
                .clk(clk),
                .rst(rst),
                .i_batch(pending_updates[bank]),
                .i_count(fifo_push_counts[bank]),
                .i_valid(fifo_push_req[bank]),
                .i_busy(fifo_busy[bank]),
                .free_slots(fifo_free_slots[bank]),
                .o_data(fifo_ht_updates[bank]),
                .o_valid(fifo_ht_update_valid[bank]),
                .o_busy(1'b0),
                .empty(fifo_empty[bank])
            );
        end
    endgenerate

    always_comb begin
        pending_valid = 1'b0;
        all_fifos_empty = !buffered_input_valid && !sorter_active_r &&
            !sorted_stage_valid && !aggregated_stage_valid;
        for (int bank = 0; bank < NUM_BANKS; bank++) begin
            pending_valid |= (pending_counts[bank] != 0);
            all_fifos_empty &= fifo_empty[bank] && (pending_counts[bank] == 0) &&
                !ht_update_valid[bank];
        end

        launch_buffered = buffered_input_valid && !sorter_active_r &&
            !sorted_stage_valid && !aggregated_stage_valid && !pending_valid;
        sorter_accept = launch_buffered;

        // Hold the sorter input on the staged register contents so the sorter
        // launch boundary is a real sequential cut, not a mux with a live
        // combinational hasher leg still visible to STA.
        for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
            sorter_input_updates[slot] = buffered_hashed_updates[slot];
        end

        // Keep the new one-deep front-end register ahead of the sorter, but
        // retain the existing backpressure behavior once staged work is already
        // draining through the later pipeline phases.
        i_busy = sorted_stage_valid || aggregated_stage_valid || pending_valid ||
            (sorter_active_r && buffered_input_valid);
    end

    always_ff @(posedge clk) begin
        logic next_pending_valid;
        logic next_sorted_stage_valid;
        logic next_aggregated_stage_valid;
        agg_update_t next_pending_updates [NUM_BANKS][PIPE_WIDTH];
        logic [COUNT_W-1:0] next_pending_counts [NUM_BANKS];
        hashed_update_t next_sorted_stage_updates [PIPE_WIDTH];
        agg_update_t next_aggregated_stage_updates [PIPE_WIDTH];
        logic [COUNT_W-1:0] next_aggregated_stage_count;

        if (rst) begin
            buffered_input_valid <= 1'b0;
            sorter_active_r <= 1'b0;
            sorted_stage_valid <= 1'b0;
            aggregated_stage_valid <= 1'b0;
            aggregated_stage_count <= '0;
            for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                buffered_hashed_updates[slot] <= '0;
            end
            for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                sorted_stage_updates[slot] <= '0;
                aggregated_stage_updates[slot] <= '0;
            end
            for (int bank = 0; bank < NUM_BANKS; bank++) begin
                ht_updates[bank] <= '0;
                ht_update_valid[bank] <= 1'b0;
                pending_counts[bank] <= '0;
                for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                    pending_updates[bank][slot] <= '0;
                end
            end
        end else begin
            for (int bank = 0; bank < NUM_BANKS; bank++) begin
                ht_updates[bank] <= fifo_ht_updates[bank];
                ht_update_valid[bank] <= fifo_ht_update_valid[bank];
            end

            if (launch_buffered) begin
                if (i_valid) begin
                    for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                        buffered_hashed_updates[slot] <= hashed_updates[slot];
                    end
                end else begin
                    buffered_input_valid <= 1'b0;
                end
            end else if (!buffered_input_valid && i_valid) begin
                buffered_input_valid <= 1'b1;
                for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                    buffered_hashed_updates[slot] <= hashed_updates[slot];
                end
            end

            if (sorter_accept) begin
                sorter_active_r <= 1'b1;
            end
            if (sorter_valid) begin
                sorter_active_r <= 1'b0;
            end

            next_sorted_stage_valid = sorted_stage_valid;
            next_aggregated_stage_valid = aggregated_stage_valid;
            next_aggregated_stage_count = aggregated_stage_count;
            for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                next_sorted_stage_updates[slot] = sorted_stage_updates[slot];
                next_aggregated_stage_updates[slot] = aggregated_stage_updates[slot];
            end

            for (int bank = 0; bank < NUM_BANKS; bank++) begin
                next_pending_counts[bank] = pending_counts[bank];
                for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                    next_pending_updates[bank][slot] = pending_updates[bank][slot];
                end

                if (pending_valid && (fifo_push_counts[bank] != 0)) begin
                    next_pending_counts[bank] = pending_counts[bank] - fifo_push_counts[bank];
                    for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                        if ((slot + fifo_push_counts[bank]) < PIPE_WIDTH) begin
                            next_pending_updates[bank][slot] =
                                pending_updates[bank][slot + fifo_push_counts[bank]];
                        end else begin
                            next_pending_updates[bank][slot] = '0;
                        end
                    end
                end
            end

            next_pending_valid = 1'b0;
            for (int bank = 0; bank < NUM_BANKS; bank++) begin
                next_pending_valid |= (next_pending_counts[bank] != 0);
            end

            if (aggregated_stage_valid && !next_pending_valid) begin
                next_pending_valid = 1'b0;
                for (int bank = 0; bank < NUM_BANKS; bank++) begin
                    next_pending_counts[bank] = grouped_counts[bank];
                    next_pending_valid |= (grouped_counts[bank] != 0);
                    for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                        next_pending_updates[bank][slot] = grouped_updates[bank][slot];
                    end
                end
                next_aggregated_stage_valid = 1'b0;
                next_aggregated_stage_count = '0;
                for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                    next_aggregated_stage_updates[slot] = '0;
                end
            end

            if (sorted_stage_valid) begin
                if (next_aggregated_stage_valid) begin
                    // synopsys translate_off
                    $fatal(1, "UpdatePipelineN aggregator stage overflow");
                    // synopsys translate_on
                end else begin
                    next_aggregated_stage_valid = 1'b1;
                    next_aggregated_stage_count = aggregated_count;
                    next_sorted_stage_valid = 1'b0;
                    for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                        next_aggregated_stage_updates[slot] = aggregated_updates[slot];
                        next_sorted_stage_updates[slot] = '0;
                    end
                end
            end

            if (sorter_valid) begin
                if (next_sorted_stage_valid) begin
                    // synopsys translate_off
                    $fatal(1, "UpdatePipelineN sorter stage overflow");
                    // synopsys translate_on
                end else begin
                    next_sorted_stage_valid = 1'b1;
                    for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                        next_sorted_stage_updates[slot] = sorted_updates[slot];
                    end
                end
            end

            sorted_stage_valid <= next_sorted_stage_valid;
            aggregated_stage_valid <= next_aggregated_stage_valid;
            aggregated_stage_count <= next_aggregated_stage_count;
            for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                sorted_stage_updates[slot] <= next_sorted_stage_updates[slot];
                aggregated_stage_updates[slot] <= next_aggregated_stage_updates[slot];
            end
            for (int bank = 0; bank < NUM_BANKS; bank++) begin
                pending_counts[bank] <= next_pending_counts[bank];
                for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                    pending_updates[bank][slot] <= next_pending_updates[bank][slot];
                end
            end
        end
    end
endmodule
