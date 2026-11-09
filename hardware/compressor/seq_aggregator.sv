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
    localparam int PREFIX_W = $clog2(PIPE_WIDTH + 1);
    localparam int START_W = (PIPE_WIDTH > 1) ? $clog2(PIPE_WIDTH) : 1;

    logic [PIPE_WIDTH-1:0] edges;
    logic [PIPE_WIDTH-1:0] valids;
    logic [PREFIX_W-1:0] edge_prefix [PIPE_WIDTH];
    logic [PREFIX_W-1:0] valid_prefix [PIPE_WIDTH];
    logic [START_W-1:0] grouped_start [PIPE_WIDTH];

    generate
        if (PIPE_WIDTH == 8) begin : gen_ps8
            PrefixSum8 edge_psum (.in(edges), .out(edge_prefix));
            PrefixSum8 valid_psum (.in(valids), .out(valid_prefix));
        end else if (PIPE_WIDTH == 10) begin : gen_ps10
            PrefixSum10 edge_psum (.in(edges), .out(edge_prefix));
            PrefixSum10 valid_psum (.in(valids), .out(valid_prefix));
        end else if (PIPE_WIDTH == 12) begin : gen_ps12
            PrefixSum12 edge_psum (.in(edges), .out(edge_prefix));
            PrefixSum12 valid_psum (.in(valids), .out(valid_prefix));
        end else if (PIPE_WIDTH == 14) begin : gen_ps14
            PrefixSum14 edge_psum (.in(edges), .out(edge_prefix));
            PrefixSum14 valid_psum (.in(valids), .out(valid_prefix));
        end else if (PIPE_WIDTH == 16) begin : gen_ps16
            PrefixSum16 edge_psum (.in(edges), .out(edge_prefix));
            PrefixSum16 valid_psum (.in(valids), .out(valid_prefix));
        end
    endgenerate

    always_comb begin
        logic [PREFIX_W-1:0] group_count;
        logic [PREFIX_W-1:0] valid_count;

        edges = '0;
        valids = '0;
        group_count = '0;
        valid_count = '0;
        o_count = '0;

        for (int i = 0; i < PIPE_WIDTH; i++) begin
            grouped_start[i] = '0;
            o_updates[i] = '0;
        end

        for (int i = 0; i < PIPE_WIDTH; i++) begin
            logic key_break;

            key_break = 1'b0;
            valids[i] = i_updates[i].valid;
            if (i_updates[i].valid) begin
                if (i == 0 || !i_updates[i - 1].valid) begin
                    key_break = 1'b1;
                end else begin
                    key_break = (i_updates[i].bank_idx != i_updates[i - 1].bank_idx) ||
                        (i_updates[i].set_idx != i_updates[i - 1].set_idx) ||
                        (i_updates[i].seq != i_updates[i - 1].seq) ||
                        (i_updates[i].inc != i_updates[i - 1].inc);
                end
            end

            edges[i] = key_break;
        end

        group_count = edge_prefix[PIPE_WIDTH - 1];
        valid_count = valid_prefix[PIPE_WIDTH - 1];
        o_count = group_count[$bits(o_count)-1:0];

        for (int i = 0; i < PIPE_WIDTH; i++) begin
            if (edges[i]) begin
                grouped_start[edge_prefix[i] - 1] = i[START_W-1:0];
            end
        end

        for (int g = 0; g < PIPE_WIDTH; g++) begin
            if (g < group_count) begin
                int start_idx = 0;
                int end_idx = 0;
                int run_length = 0;

                start_idx = grouped_start[g];
                if (g + 1 < group_count) begin
                    end_idx = grouped_start[g + 1];
                end else begin
                    end_idx = valid_count;
                end

                run_length = end_idx - start_idx;
                if (run_length > 0 && i_updates[start_idx].valid) begin
                    o_updates[g].bank_idx = i_updates[start_idx].bank_idx;
                    o_updates[g].set_idx = i_updates[start_idx].set_idx;
                    o_updates[g].seq = i_updates[start_idx].seq;
                    o_updates[g].count = i_updates[start_idx].inc ? run_length : -run_length;
                    o_updates[g].valid = 1'b1;
                end
            end
        end
    end
endmodule
