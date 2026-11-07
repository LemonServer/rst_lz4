`timescale 1ps / 1ps
`default_nettype none

module Filter
    import rst_pkg::*;
(
    input  logic [CHUNK_WIDTH-1:0] candidates,
    input  logic [2:0] seq_len,
    output logic [CHUNK_WIDTH-1:0] filtered_matches
);
    typedef struct packed {
        logic [3:0] mod;
        logic [2:0] filter_idx;
    } group_filter_idx;

    localparam int INDEX_W = $clog2(CHUNK_WIDTH);
    localparam int PROP_STAGES = (CHUNK_WIDTH > 1) ? $clog2(CHUNK_WIDTH) : 1;

    logic [CHUNK_WIDTH-1:0] rs1, rs2, rs3, rs4;
    logic [CHUNK_WIDTH+3-1:0] extended_candidates;
    logic [CHUNK_WIDTH-1:0] edges;
    logic edge_group_valid [CHUNK_WIDTH];
    logic [3:0] edge_group_mod [CHUNK_WIDTH];
    logic [2:0] edge_group_idx [CHUNK_WIDTH];
    logic propagated_group_valid [PROP_STAGES+1][CHUNK_WIDTH];
    logic [3:0] propagated_group_mod [PROP_STAGES+1][CHUNK_WIDTH];
    logic [2:0] propagated_group_idx [PROP_STAGES+1][CHUNK_WIDTH];

    generate
        // Carry the latest edge's selection metadata forward in log-depth instead of
        // counting all prior edges through a full numeric prefix sum.
        for (genvar lane = 0; lane < CHUNK_WIDTH; lane++) begin : gen_propagate_base
            assign propagated_group_valid[0][lane] = edge_group_valid[lane];
            assign propagated_group_mod[0][lane] = edge_group_mod[lane];
            assign propagated_group_idx[0][lane] = edge_group_idx[lane];
        end

        for (genvar stage = 0; stage < PROP_STAGES; stage++) begin : gen_propagate_stage
            localparam int DIST = 1 << stage;
            for (genvar lane = 0; lane < CHUNK_WIDTH; lane++) begin : gen_propagate_lane
                if (lane < DIST) begin : gen_passthrough
                    assign propagated_group_valid[stage + 1][lane] = propagated_group_valid[stage][lane];
                    assign propagated_group_mod[stage + 1][lane] = propagated_group_mod[stage][lane];
                    assign propagated_group_idx[stage + 1][lane] = propagated_group_idx[stage][lane];
                end else begin : gen_merge
                    assign propagated_group_valid[stage + 1][lane] =
                        propagated_group_valid[stage][lane] |
                        propagated_group_valid[stage][lane - DIST];
                    assign propagated_group_mod[stage + 1][lane] =
                        propagated_group_valid[stage][lane] ?
                        propagated_group_mod[stage][lane] :
                        propagated_group_mod[stage][lane - DIST];
                    assign propagated_group_idx[stage + 1][lane] =
                        propagated_group_valid[stage][lane] ?
                        propagated_group_idx[stage][lane] :
                        propagated_group_idx[stage][lane - DIST];
                end
            end
        end
    endgenerate

    function automatic logic [2:0] mod_lut(
        input logic [INDEX_W-1:0] idx,
        input logic [3:0] mod
    );
        logic [3:0] rem;
        case (mod)
            4'd2: mod_lut = {2'b00, idx[0]};
            4'd3: begin
                rem = '0;
                for (int step = 0; step < INDEX_W; step++) begin
                    rem = {rem[2:0], idx[INDEX_W - 1 - step]};
                    if (rem >= 4'd3) begin
                        rem = rem - 4'd3;
                    end
                end
                mod_lut = rem[2:0];
            end
            4'd4: mod_lut = {1'b0, idx[1:0]};
            4'd5: begin
                rem = '0;
                for (int step = 0; step < INDEX_W; step++) begin
                    rem = {rem[2:0], idx[INDEX_W - 1 - step]};
                    if (rem >= 4'd5) begin
                        rem = rem - 4'd5;
                    end
                end
                mod_lut = rem[2:0];
            end
            4'd8: mod_lut = idx[2:0];
            default: mod_lut = '0;
        endcase
    endfunction

    always_comb begin
        extended_candidates = '0;
        rs1 = candidates << 1;
        rs2 = candidates << 2;
        rs3 = candidates << 3;
        rs4 = candidates << 4;
        filtered_matches = '0;

        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            extended_candidates[i] = candidates[i];
            edge_group_valid[i] = 1'b0;
            edge_group_mod[i] = '0;
            edge_group_idx[i] = '0;
            case (seq_len)
                3'd2: edges[i] = (~rs1[i] & candidates[i]);
                3'd3: edges[i] = (~rs1[i] & ~rs2[i] & candidates[i]);
                3'd4: edges[i] = (~rs1[i] & ~rs2[i] & ~rs3[i] & candidates[i]);
                3'd5: edges[i] = (~rs1[i] & ~rs2[i] & ~rs3[i] & ~rs4[i] & candidates[i]);
                default: edges[i] = 1'b0;
            endcase
        end

        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            if (edges[i]) begin
                group_filter_idx new_filter_idx;
                new_filter_idx = '0;

                if (extended_candidates[i + 1]) begin
                    new_filter_idx.mod = seq_len;
                end else if (extended_candidates[i + 2]) begin
                    new_filter_idx.mod = (seq_len == 3'd5) ? 4'd3 : 4'd4;
                end else if (extended_candidates[i + 3]) begin
                    new_filter_idx.mod = 4'd2;
                end else begin
                    new_filter_idx.mod = 4'd8;
                end

                new_filter_idx.filter_idx = mod_lut(i[INDEX_W-1:0], new_filter_idx.mod);
                edge_group_valid[i] = 1'b1;
                edge_group_mod[i] = new_filter_idx.mod;
                edge_group_idx[i] = new_filter_idx.filter_idx;
            end
        end

        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            filtered_matches[i] = candidates[i] &&
                propagated_group_valid[PROP_STAGES][i] &&
                (mod_lut(i[INDEX_W-1:0], propagated_group_mod[PROP_STAGES][i]) ==
                    propagated_group_idx[PROP_STAGES][i]);
        end
    end
endmodule
