`timescale 1ps / 1ps
`default_nettype none

module MatchFilterReplace
    import rst_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic i_valid,
    input  vsym_t pre_sub [CHUNK_WIDTH],
    input  seq_t  sel_seq,
    input  logic [2:0] sel_seq_len,
    input  symbol_t repl_sym,
    output logic o_valid,
    output vsym_t post_sub [CHUNK_WIDTH],
    output logic [CHUNK_WIDTH-1:0] sub_sites
);
    logic [CHUNK_WIDTH-1:0] match_vec;
    logic [CHUNK_WIDTH-1:0] filtered_matches;
    logic stage1_valid_r;
    vsym_t pre_sub_r [CHUNK_WIDTH];
    logic [CHUNK_WIDTH-1:0] sub_sites_r;
    logic [2:0] seq_len_r;
    symbol_t repl_sym_r;
    vsym_t replaced_symbols [CHUNK_WIDTH];

    Matcher matcher (
        .symbols(pre_sub),
        .seq(sel_seq),
        .seq_len(sel_seq_len),
        .match_vec(match_vec)
    );

    Filter filter (
        .candidates(match_vec),
        .seq_len(sel_seq_len),
        .filtered_matches(filtered_matches)
    );

    Replacer replacer (
        .pre_sub(pre_sub_r),
        .filtered_matches(sub_sites_r),
        .repl_sym(repl_sym_r),
        .seq_len(seq_len_r),
        .post_sub(replaced_symbols)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            stage1_valid_r <= 1'b0;
            o_valid <= 1'b0;
            seq_len_r <= '0;
            repl_sym_r <= '0;
            sub_sites_r <= '0;
            sub_sites <= '0;

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                pre_sub_r[i] <= '0;
                post_sub[i] <= '0;
            end
        end else begin
            stage1_valid_r <= i_valid;
            o_valid <= stage1_valid_r;

            if (i_valid) begin
                seq_len_r <= sel_seq_len;
                repl_sym_r <= repl_sym;
                sub_sites_r <= filtered_matches;

                for (int i = 0; i < CHUNK_WIDTH; i++) begin
                    pre_sub_r[i] <= pre_sub[i];
                end
            end

            if (stage1_valid_r) begin
                sub_sites <= sub_sites_r;
                for (int i = 0; i < CHUNK_WIDTH; i++) begin
                    post_sub[i] <= replaced_symbols[i];
                end
            end
        end
    end
endmodule
