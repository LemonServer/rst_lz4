`timescale 1ps / 1ps
`default_nettype none

module PriorityEncoder #(
    parameter int WIDTH = rst_pkg::CHUNK_WIDTH
) (
    input  logic [WIDTH-1:0] in,
    output logic valid,
    output logic [$clog2(WIDTH)-1:0] pos
);
    always_comb begin
        valid = 1'b0;
        pos = '0;
        for (int i = 0; i < WIDTH; i++) begin
            if (!valid && in[i]) begin
                valid = 1'b1;
                pos = i[$clog2(WIDTH)-1:0];
            end
        end
    end
endmodule

module ProgrammablePE #(
    parameter int WIDTH = rst_pkg::CHUNK_WIDTH
) (
    input  logic clk,
    input  logic start,
    input  logic next,
    input  logic rst,
    input  logic [WIDTH-1:0] in,
    output logic valid,
    output logic [$clog2(WIDTH)-1:0] pos,
    output logic done
);
    logic [WIDTH-1:0] current_bits;
    logic pe_valid;
    logic [$clog2(WIDTH)-1:0] pe_pos;

    PriorityEncoder #(
        .WIDTH(WIDTH)
    ) pe (
        .in(current_bits),
        .valid(pe_valid),
        .pos(pe_pos)
    );

    assign done = !pe_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            current_bits <= '0;
            valid <= 1'b0;
            pos <= '0;
        end else begin
            if (start) begin
                current_bits <= in;
            end else if (next && pe_valid) begin
                current_bits[pe_pos] <= 1'b0;
            end

            valid <= pe_valid;
            pos <= pe_pos;
        end
    end
endmodule
