`timescale 1ps / 1ps
`default_nettype none

module SeqAggregator
    import rst_pkg::*;
#(
    parameter int PIPE_WIDTH = PIPE_WIDTH_SEQ2
) (
    input  hashed_update_t i_updates [PIPE_WIDTH],
    output logic [$clog2(PIPE_WIDTH + 1)-1:0] o_count,
    output agg_update_t o_updates [PIPE_WIDTH]
);
    always_comb begin
        int group_count_i;
        int idx;

        o_count = '0;
        for (int slot = 0; slot < PIPE_WIDTH; slot++) begin
            o_updates[slot] = '0;
        end

        group_count_i = 0;
        idx = 0;
        while (idx < PIPE_WIDTH) begin
            if (i_updates[idx].valid) begin
                int next_idx;
                integer signed count_accum;

                next_idx = idx;
                count_accum = 0;
                while ((next_idx < PIPE_WIDTH) &&
                       i_updates[next_idx].valid &&
                       (i_updates[next_idx].bank_idx == i_updates[idx].bank_idx) &&
                       (i_updates[next_idx].set_idx == i_updates[idx].set_idx) &&
                       (i_updates[next_idx].seq == i_updates[idx].seq)) begin
                    if (i_updates[next_idx].inc) begin
                        count_accum = count_accum + 1;
                    end else begin
                        count_accum = count_accum - 1;
                    end
                    next_idx = next_idx + 1;
                end

                if (count_accum != 0) begin
                    o_updates[group_count_i].bank_idx = i_updates[idx].bank_idx;
                    o_updates[group_count_i].set_idx = i_updates[idx].set_idx;
                    o_updates[group_count_i].seq = i_updates[idx].seq;
                    o_updates[group_count_i].count = count_accum;
                    o_updates[group_count_i].valid = 1'b1;
                    group_count_i = group_count_i + 1;
                end
                idx = next_idx;
            end else begin
                idx = idx + 1;
            end
        end

        o_count = group_count_i[$bits(o_count)-1:0];
    end
endmodule
