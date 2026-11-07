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
        .pre_sub(pre_sub),
        .filtered_matches(filtered_matches),
        .repl_sym(repl_sym),
        .seq_len(sel_seq_len),
        .post_sub(replaced_symbols)
    );

    always_comb begin
        o_valid = i_valid && !rst;
        sub_sites = filtered_matches;
        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            post_sub[i] = replaced_symbols[i];
        end
    end
endmodule
