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
    hashed_update_t sorted_updates [PIPE_WIDTH];
    agg_update_t aggregated_updates [PIPE_WIDTH];
    logic [COUNT_W-1:0] aggregated_count;
    agg_update_t grouped_updates [NUM_BANKS][PIPE_WIDTH];
    logic [COUNT_W-1:0] grouped_counts [NUM_BANKS];
    agg_update_t fifo_ht_updates [NUM_BANKS];
    logic fifo_ht_update_valid [NUM_BANKS];
    logic fifo_push_req [NUM_BANKS];
    logic fifo_busy [NUM_BANKS];
    logic fifo_empty [NUM_BANKS];
    logic [FIFO_SPACE_W-1:0] fifo_free_slots [NUM_BANKS];
    logic can_accept_batch;

    function automatic logic count_fits_fifo(
        input logic [COUNT_W-1:0] count,
        input logic [FIFO_SPACE_W-1:0] free_slots
    );
        int unsigned count_i;
        int unsigned free_slots_i;
        begin
            count_i = count;
            free_slots_i = free_slots;
            count_fits_fifo = (count_i <= free_slots_i);
        end
    endfunction

    SeqHasher #(
        .PIPE_WIDTH(PIPE_WIDTH),
        .NUM_BANKS(NUM_BANKS)
    ) hasher (
        .i_updates(i_updates),
        .o_updates(hashed_updates)
    );

    // Throughput-first mode: treat the wide sorter as part of the
    // combinational front end and let FIFO capacity drive backpressure.
    SeqSorter #(
        .PIPE_WIDTH(PIPE_WIDTH)
    ) sorter (
        .i_updates(hashed_updates),
        .o_updates(sorted_updates)
    );

    SeqAggregator #(
        .PIPE_WIDTH(PIPE_WIDTH)
    ) aggregator (
        .i_updates(sorted_updates),
        .o_count(aggregated_count),
        .o_updates(aggregated_updates)
    );

    BankGrouper #(
        .PIPE_WIDTH(PIPE_WIDTH),
        .NUM_BANKS(NUM_BANKS)
    ) grouper (
        .i_updates(aggregated_updates),
        .i_count(aggregated_count),
        .o_updates(grouped_updates),
        .o_counts(grouped_counts)
    );

    generate
        for (genvar bank = 0; bank < NUM_BANKS; bank++) begin : gen_fifos
            assign fifo_push_req[bank] =
                i_valid && can_accept_batch && (grouped_counts[bank] != 0);

            FIFO #(
                .PIPE_WIDTH(PIPE_WIDTH),
                .DEPTH(FIFO_DEPTH_P)
            ) fifo_inst (
                .clk(clk),
                .rst(rst),
                .i_batch(grouped_updates[bank]),
                .i_count(grouped_counts[bank]),
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
        can_accept_batch = 1'b1;
        all_fifos_empty = !i_valid;
        i_busy = 1'b0;

        for (int bank = 0; bank < NUM_BANKS; bank++) begin
            ht_updates[bank] = fifo_ht_updates[bank];
            ht_update_valid[bank] = fifo_ht_update_valid[bank];
            all_fifos_empty &= fifo_empty[bank];

            if (!count_fits_fifo(grouped_counts[bank], fifo_free_slots[bank])) begin
                can_accept_batch = 1'b0;
            end
        end

        i_busy = !can_accept_batch;
    end
endmodule
