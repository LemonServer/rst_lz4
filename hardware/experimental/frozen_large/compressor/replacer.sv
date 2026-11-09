`timescale 1ps / 1ps
`default_nettype none

module Replacer
    import rst_pkg::*;
(
    input  vsym_t pre_sub [CHUNK_WIDTH],
    input  logic [CHUNK_WIDTH-1:0] filtered_matches,
    input  symbol_t repl_sym,
    input  logic [2:0] seq_len,
    output vsym_t post_sub [CHUNK_WIDTH]
);
    localparam int COUNT_W = $clog2(CHUNK_WIDTH + 1);
    localparam int PROP_STAGES = (CHUNK_WIDTH > 1) ? $clog2(CHUNK_WIDTH) : 1;
    typedef logic [COUNT_W-1:0] count_t;

    vsym_t uncompacted [CHUNK_WIDTH];
    logic [CHUNK_WIDTH-1:0] valid;
    count_t prefix_counts [PROP_STAGES+1][CHUNK_WIDTH];
    count_t prefix_sum [CHUNK_WIDTH];

    generate
        // Use a log-depth inclusive scan here so compaction does not depend on the
        // work-efficient adder tree depth from the generated prefix-sum blocks.
        for (genvar lane = 0; lane < CHUNK_WIDTH; lane++) begin : gen_prefix_base
            assign prefix_counts[0][lane] = valid[lane] ? count_t'(1) : '0;
            assign prefix_sum[lane] = prefix_counts[PROP_STAGES][lane];
        end

        for (genvar stage = 0; stage < PROP_STAGES; stage++) begin : gen_prefix_stage
            localparam int DIST = 1 << stage;
            for (genvar lane = 0; lane < CHUNK_WIDTH; lane++) begin : gen_prefix_lane
                if (lane < DIST) begin : gen_passthrough
                    assign prefix_counts[stage + 1][lane] = prefix_counts[stage][lane];
                end else begin : gen_merge
                    assign prefix_counts[stage + 1][lane] =
                        count_t'(prefix_counts[stage][lane] + prefix_counts[stage][lane - DIST]);
                end
            end
        end
    endgenerate

    always_comb begin
        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            uncompacted[i] = pre_sub[i];
        end

        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            if (filtered_matches[i]) begin
                uncompacted[i].sym = repl_sym;
                for (int j = 1; j < MAX_SEQ_LEN; j++) begin
                    if (j < seq_len && (i + j) < CHUNK_WIDTH) begin
                        uncompacted[i + j].valid = 1'b0;
                    end
                end
            end
        end

        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            valid[i] = uncompacted[i].valid;
            post_sub[i] = '0;
        end

        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            if (valid[i]) begin
                post_sub[prefix_sum[i] - 1] = uncompacted[i];
            end
        end
    end
endmodule
