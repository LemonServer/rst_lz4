`timescale 1ps / 1ps
`default_nettype none

module BankGrouper
    import rst_pkg::*;
#(
    parameter int PIPE_WIDTH = PIPE_WIDTH_SEQ2,
    parameter int NUM_BANKS = BANKS_SEQ2
) (
    input  agg_update_t i_updates [PIPE_WIDTH],
    input  logic [$clog2(PIPE_WIDTH + 1)-1:0] i_count,
    output agg_update_t o_updates [NUM_BANKS][PIPE_WIDTH],
    output logic [$clog2(PIPE_WIDTH + 1)-1:0] o_counts [NUM_BANKS]
);
    localparam int COUNT_W = $clog2(PIPE_WIDTH + 1);
    logic bank_present [NUM_BANKS];
    logic [COUNT_W-1:0] bank_starts [NUM_BANKS];
    logic [COUNT_W-1:0] bank_ends [NUM_BANKS];

    always_comb begin
        for (int bank = 0; bank < NUM_BANKS; bank++) begin
            o_counts[bank] = '0;
            bank_present[bank] = 1'b0;
            bank_starts[bank] = '0;
            bank_ends[bank] = '0;
            for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                o_updates[bank][slot] = '0;
            end
        end

        // UpdatePipelineN feeds this module with aggregator output that is
        // already sorted bank-major, so each bank appears as a single
        // contiguous run. Detect the start/end of that run for every bank,
        // derive the run length, then slice the segment directly.
        for (int bank = 0; bank < NUM_BANKS; bank++) begin
            for (int lane = 0; lane < PIPE_WIDTH; lane++) begin
                if ((lane < i_count) &&
                    i_updates[lane].valid &&
                    (i_updates[lane].bank_idx == bank)) begin
                    if (lane == 0) begin
                        bank_present[bank] = 1'b1;
                        bank_starts[bank] = COUNT_W'(lane);
                    end else if (!i_updates[lane - 1].valid ||
                                 (i_updates[lane - 1].bank_idx != bank)) begin
                        bank_present[bank] = 1'b1;
                        bank_starts[bank] = COUNT_W'(lane);
                    end

                    if ((lane + 1) >= i_count) begin
                        bank_ends[bank] = COUNT_W'(lane + 1);
                    end else if (!i_updates[lane + 1].valid ||
                                 (i_updates[lane + 1].bank_idx != bank)) begin
                        bank_ends[bank] = COUNT_W'(lane + 1);
                    end
                end
            end
        end

        for (int bank = 0; bank < NUM_BANKS; bank++) begin
            if (bank_present[bank]) begin
                o_counts[bank] = bank_ends[bank] - bank_starts[bank];
            end
            for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
                if (slot < o_counts[bank]) begin
                    o_updates[bank][slot] = i_updates[bank_starts[bank] + slot];
                end
            end
        end
    end
endmodule
