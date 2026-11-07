`timescale 1ps / 1ps
`default_nettype none

module SeqSorterStagedBest
    import rst_pkg::*;
#(
    parameter int PIPE_WIDTH = PIPE_WIDTH_SEQ2
) (
    input  logic clk,
    input  logic rst,
    input  logic i_valid,
    input  hashed_update_t i_updates [PIPE_WIDTH],
    output logic o_valid,
    output logic o_busy,
    output hashed_update_t o_updates [PIPE_WIDTH]
);
    // Settled live sorter family, validated against the real 400 ps target on
    // tiny and small tiers:
    //   W8  -> Pipe2
    //   W10 -> Pipe3
    //   W12 -> Pipe3
    //   W14 -> Pipe5
    // These staged variants are traveling-CE pipelines: they can accept a new
    // batch every cycle, and validity advances at a fixed latency.
    assign o_busy = 1'b0;

    generate
        if (PIPE_WIDTH == PIPE_WIDTH_SEQ2) begin : gen_w8
            SeqSorterPipe2 #(
                .PIPE_WIDTH(PIPE_WIDTH)
            ) sorter (
                .clk(clk),
                .rst(rst),
                .i_valid(i_valid),
                .i_updates(i_updates),
                .o_valid(o_valid),
                .o_updates(o_updates)
            );
        end else if (PIPE_WIDTH == PIPE_WIDTH_SEQ3) begin : gen_w10
            SeqSorterPipe3 #(
                .PIPE_WIDTH(PIPE_WIDTH)
            ) sorter (
                .clk(clk),
                .rst(rst),
                .i_valid(i_valid),
                .i_updates(i_updates),
                .o_valid(o_valid),
                .o_updates(o_updates)
            );
        end else if (PIPE_WIDTH == PIPE_WIDTH_SEQ4) begin : gen_w12
            SeqSorterPipe3 #(
                .PIPE_WIDTH(PIPE_WIDTH)
            ) sorter (
                .clk(clk),
                .rst(rst),
                .i_valid(i_valid),
                .i_updates(i_updates),
                .o_valid(o_valid),
                .o_updates(o_updates)
            );
        end else if (PIPE_WIDTH == PIPE_WIDTH_SEQ5) begin : gen_w14
            SeqSorterPipe5 #(
                .PIPE_WIDTH(PIPE_WIDTH)
            ) sorter (
                .clk(clk),
                .rst(rst),
                .i_valid(i_valid),
                .i_updates(i_updates),
                .o_valid(o_valid),
                .o_updates(o_updates)
            );
        end else begin : gen_fallback
            SeqSorter #(
                .PIPE_WIDTH(PIPE_WIDTH)
            ) sorter (
                .i_updates(i_updates),
                .o_updates(o_updates)
            );

            assign o_valid = i_valid;
        end
    endgenerate
endmodule
