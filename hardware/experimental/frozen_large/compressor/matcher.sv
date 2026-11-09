`timescale 1ps / 1ps
`default_nettype none

module Matcher
    import rst_pkg::*;
(
    input  vsym_t symbols [CHUNK_WIDTH],
    input  seq_t  seq,
    input  logic [2:0] seq_len,
    output logic [CHUNK_WIDTH-1:0] match_vec
);
    always_comb begin
        match_vec = '0;
        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            int seq_len_i;
            logic hit;
            seq_len_i = seq_len;
            hit = 1'b1;
            if (seq_len_i < MIN_SEQ_LEN || seq_len_i > MAX_SEQ_LEN) begin
                hit = 1'b0;
            end else if (i + seq_len_i > CHUNK_WIDTH) begin
                hit = 1'b0;
            end else begin
                for (int j = 0; j < MAX_SEQ_LEN; j++) begin
                    if (j < seq_len_i) begin
                        if (!symbols[i + j].valid || symbols[i + j].sym != seq[j]) begin
                            hit = 1'b0;
                        end
                    end
                end
            end
            match_vec[i] = hit;
        end
    end
endmodule
