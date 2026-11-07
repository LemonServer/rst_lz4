`timescale 1ps / 1ps
`default_nettype none
import parameter_pkg::*;
module Partitioner (
    input logic clk, enable,
    input  logic [7:0] compressed_data [DATA_WIDTH],
    input  logic [$clog2(DATA_WIDTH+1)-1:0] length,
    output logic [7:0] lifo_inputs [LIFO_COUNT][LIFO_INPUT_WIDTH],
    output logic [$clog2(LIFO_INPUT_WIDTH+1)-1:0] lengths [LIFO_COUNT]
);
always_ff @(posedge clk) begin
if (enable) begin
for (int i=0; i<4; i++) begin
    for (int j=0; j<16; j++) begin
        lifo_inputs[i][j] <= '0;
    end
    lengths[i] <= '0;
end
case (length)
    7'd1: begin
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd1;
            end
        end
    end
    7'd2: begin
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd1;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[1][i]<=compressed_data[1+i];
                lengths[1]<=5'd1;
            end
        end
    end
    7'd3: begin
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd1;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[1][i]<=compressed_data[1+i];
                lengths[1]<=5'd1;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[2][i]<=compressed_data[2+i];
                lengths[2]<=5'd1;
            end
        end
    end
    7'd4: begin
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd1;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[1][i]<=compressed_data[1+i];
                lengths[1]<=5'd1;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[2][i]<=compressed_data[2+i];
                lengths[2]<=5'd1;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[3][i]<=compressed_data[3+i];
                lengths[3]<=5'd1;
            end
        end
    end
    7'd5: begin
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[1][i]<=compressed_data[2+i];
                lengths[1]<=5'd1;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[2][i]<=compressed_data[3+i];
                lengths[2]<=5'd1;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[3][i]<=compressed_data[4+i];
                lengths[3]<=5'd1;
            end
        end
    end
    7'd6: begin
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[1][i]<=compressed_data[2+i];
                lengths[1]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[2][i]<=compressed_data[4+i];
                lengths[2]<=5'd1;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[3][i]<=compressed_data[5+i];
                lengths[3]<=5'd1;
            end
        end
    end
    7'd7: begin
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[1][i]<=compressed_data[2+i];
                lengths[1]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[2][i]<=compressed_data[4+i];
                lengths[2]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<1) begin
                lifo_inputs[3][i]<=compressed_data[6+i];
                lengths[3]<=5'd1;
            end
        end
    end
    7'd8: begin
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[1][i]<=compressed_data[2+i];
                lengths[1]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[2][i]<=compressed_data[4+i];
                lengths[2]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[3][i]<=compressed_data[6+i];
                lengths[3]<=5'd2;
            end
        end
    end
    7'd9: begin
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[1][i]<=compressed_data[3+i];
                lengths[1]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[2][i]<=compressed_data[5+i];
                lengths[2]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[3][i]<=compressed_data[7+i];
                lengths[3]<=5'd2;
            end
        end
    end
    7'd10: begin
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[1][i]<=compressed_data[3+i];
                lengths[1]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[2][i]<=compressed_data[6+i];
                lengths[2]<=5'd2;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[3][i]<=compressed_data[8+i];
                lengths[3]<=5'd2;
            end
        end
    end
    7'd11: begin
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[1][i]<=compressed_data[3+i];
                lengths[1]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[2][i]<=compressed_data[6+i];
                lengths[2]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<2) begin
                lifo_inputs[3][i]<=compressed_data[9+i];
                lengths[3]<=5'd2;
            end
        end
    end
    7'd12: begin
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[1][i]<=compressed_data[3+i];
                lengths[1]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[2][i]<=compressed_data[6+i];
                lengths[2]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[3][i]<=compressed_data[9+i];
                lengths[3]<=5'd3;
            end
        end
    end
    7'd13: begin
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[1][i]<=compressed_data[4+i];
                lengths[1]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[2][i]<=compressed_data[7+i];
                lengths[2]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[3][i]<=compressed_data[10+i];
                lengths[3]<=5'd3;
            end
        end
    end
    7'd14: begin
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[1][i]<=compressed_data[4+i];
                lengths[1]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[2][i]<=compressed_data[8+i];
                lengths[2]<=5'd3;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[3][i]<=compressed_data[11+i];
                lengths[3]<=5'd3;
            end
        end
    end
    7'd15: begin
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[1][i]<=compressed_data[4+i];
                lengths[1]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[2][i]<=compressed_data[8+i];
                lengths[2]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<3) begin
                lifo_inputs[3][i]<=compressed_data[12+i];
                lengths[3]<=5'd3;
            end
        end
    end
    7'd16: begin
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[1][i]<=compressed_data[4+i];
                lengths[1]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[2][i]<=compressed_data[8+i];
                lengths[2]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[3][i]<=compressed_data[12+i];
                lengths[3]<=5'd4;
            end
        end
    end
    7'd17: begin
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[1][i]<=compressed_data[5+i];
                lengths[1]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[2][i]<=compressed_data[9+i];
                lengths[2]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[3][i]<=compressed_data[13+i];
                lengths[3]<=5'd4;
            end
        end
    end
    7'd18: begin
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[1][i]<=compressed_data[5+i];
                lengths[1]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[2][i]<=compressed_data[10+i];
                lengths[2]<=5'd4;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[3][i]<=compressed_data[14+i];
                lengths[3]<=5'd4;
            end
        end
    end
    7'd19: begin
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[1][i]<=compressed_data[5+i];
                lengths[1]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[2][i]<=compressed_data[10+i];
                lengths[2]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<4) begin
                lifo_inputs[3][i]<=compressed_data[15+i];
                lengths[3]<=5'd4;
            end
        end
    end
    7'd20: begin
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[1][i]<=compressed_data[5+i];
                lengths[1]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[2][i]<=compressed_data[10+i];
                lengths[2]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[3][i]<=compressed_data[15+i];
                lengths[3]<=5'd5;
            end
        end
    end
    7'd21: begin
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[1][i]<=compressed_data[6+i];
                lengths[1]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[2][i]<=compressed_data[11+i];
                lengths[2]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[3][i]<=compressed_data[16+i];
                lengths[3]<=5'd5;
            end
        end
    end
    7'd22: begin
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[1][i]<=compressed_data[6+i];
                lengths[1]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[2][i]<=compressed_data[12+i];
                lengths[2]<=5'd5;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[3][i]<=compressed_data[17+i];
                lengths[3]<=5'd5;
            end
        end
    end
    7'd23: begin
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[1][i]<=compressed_data[6+i];
                lengths[1]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[2][i]<=compressed_data[12+i];
                lengths[2]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<5) begin
                lifo_inputs[3][i]<=compressed_data[18+i];
                lengths[3]<=5'd5;
            end
        end
    end
    7'd24: begin
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[1][i]<=compressed_data[6+i];
                lengths[1]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[2][i]<=compressed_data[12+i];
                lengths[2]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[3][i]<=compressed_data[18+i];
                lengths[3]<=5'd6;
            end
        end
    end
    7'd25: begin
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[1][i]<=compressed_data[7+i];
                lengths[1]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[2][i]<=compressed_data[13+i];
                lengths[2]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[3][i]<=compressed_data[19+i];
                lengths[3]<=5'd6;
            end
        end
    end
    7'd26: begin
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[1][i]<=compressed_data[7+i];
                lengths[1]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[2][i]<=compressed_data[14+i];
                lengths[2]<=5'd6;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[3][i]<=compressed_data[20+i];
                lengths[3]<=5'd6;
            end
        end
    end
    7'd27: begin
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[1][i]<=compressed_data[7+i];
                lengths[1]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[2][i]<=compressed_data[14+i];
                lengths[2]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<6) begin
                lifo_inputs[3][i]<=compressed_data[21+i];
                lengths[3]<=5'd6;
            end
        end
    end
    7'd28: begin
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[1][i]<=compressed_data[7+i];
                lengths[1]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[2][i]<=compressed_data[14+i];
                lengths[2]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[3][i]<=compressed_data[21+i];
                lengths[3]<=5'd7;
            end
        end
    end
    7'd29: begin
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[1][i]<=compressed_data[8+i];
                lengths[1]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[2][i]<=compressed_data[15+i];
                lengths[2]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[3][i]<=compressed_data[22+i];
                lengths[3]<=5'd7;
            end
        end
    end
    7'd30: begin
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[1][i]<=compressed_data[8+i];
                lengths[1]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[2][i]<=compressed_data[16+i];
                lengths[2]<=5'd7;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[3][i]<=compressed_data[23+i];
                lengths[3]<=5'd7;
            end
        end
    end
    7'd31: begin
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[1][i]<=compressed_data[8+i];
                lengths[1]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[2][i]<=compressed_data[16+i];
                lengths[2]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<7) begin
                lifo_inputs[3][i]<=compressed_data[24+i];
                lengths[3]<=5'd7;
            end
        end
    end
    7'd32: begin
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[1][i]<=compressed_data[8+i];
                lengths[1]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[2][i]<=compressed_data[16+i];
                lengths[2]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[3][i]<=compressed_data[24+i];
                lengths[3]<=5'd8;
            end
        end
    end
    7'd33: begin
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[1][i]<=compressed_data[9+i];
                lengths[1]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[2][i]<=compressed_data[17+i];
                lengths[2]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[3][i]<=compressed_data[25+i];
                lengths[3]<=5'd8;
            end
        end
    end
    7'd34: begin
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[1][i]<=compressed_data[9+i];
                lengths[1]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[2][i]<=compressed_data[18+i];
                lengths[2]<=5'd8;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[3][i]<=compressed_data[26+i];
                lengths[3]<=5'd8;
            end
        end
    end
    7'd35: begin
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[1][i]<=compressed_data[9+i];
                lengths[1]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[2][i]<=compressed_data[18+i];
                lengths[2]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<8) begin
                lifo_inputs[3][i]<=compressed_data[27+i];
                lengths[3]<=5'd8;
            end
        end
    end
    7'd36: begin
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[1][i]<=compressed_data[9+i];
                lengths[1]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[2][i]<=compressed_data[18+i];
                lengths[2]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[3][i]<=compressed_data[27+i];
                lengths[3]<=5'd9;
            end
        end
    end
    7'd37: begin
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[1][i]<=compressed_data[10+i];
                lengths[1]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[2][i]<=compressed_data[19+i];
                lengths[2]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[3][i]<=compressed_data[28+i];
                lengths[3]<=5'd9;
            end
        end
    end
    7'd38: begin
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[1][i]<=compressed_data[10+i];
                lengths[1]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[2][i]<=compressed_data[20+i];
                lengths[2]<=5'd9;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[3][i]<=compressed_data[29+i];
                lengths[3]<=5'd9;
            end
        end
    end
    7'd39: begin
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[1][i]<=compressed_data[10+i];
                lengths[1]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[2][i]<=compressed_data[20+i];
                lengths[2]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<9) begin
                lifo_inputs[3][i]<=compressed_data[30+i];
                lengths[3]<=5'd9;
            end
        end
    end
    7'd40: begin
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[1][i]<=compressed_data[10+i];
                lengths[1]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[2][i]<=compressed_data[20+i];
                lengths[2]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[3][i]<=compressed_data[30+i];
                lengths[3]<=5'd10;
            end
        end
    end
    7'd41: begin
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[1][i]<=compressed_data[11+i];
                lengths[1]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[2][i]<=compressed_data[21+i];
                lengths[2]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[3][i]<=compressed_data[31+i];
                lengths[3]<=5'd10;
            end
        end
    end
    7'd42: begin
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[1][i]<=compressed_data[11+i];
                lengths[1]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[2][i]<=compressed_data[22+i];
                lengths[2]<=5'd10;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[3][i]<=compressed_data[32+i];
                lengths[3]<=5'd10;
            end
        end
    end
    7'd43: begin
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[1][i]<=compressed_data[11+i];
                lengths[1]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[2][i]<=compressed_data[22+i];
                lengths[2]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<10) begin
                lifo_inputs[3][i]<=compressed_data[33+i];
                lengths[3]<=5'd10;
            end
        end
    end
    7'd44: begin
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[1][i]<=compressed_data[11+i];
                lengths[1]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[2][i]<=compressed_data[22+i];
                lengths[2]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[3][i]<=compressed_data[33+i];
                lengths[3]<=5'd11;
            end
        end
    end
    7'd45: begin
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[1][i]<=compressed_data[12+i];
                lengths[1]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[2][i]<=compressed_data[23+i];
                lengths[2]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[3][i]<=compressed_data[34+i];
                lengths[3]<=5'd11;
            end
        end
    end
    7'd46: begin
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[1][i]<=compressed_data[12+i];
                lengths[1]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[2][i]<=compressed_data[24+i];
                lengths[2]<=5'd11;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[3][i]<=compressed_data[35+i];
                lengths[3]<=5'd11;
            end
        end
    end
    7'd47: begin
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[1][i]<=compressed_data[12+i];
                lengths[1]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[2][i]<=compressed_data[24+i];
                lengths[2]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<11) begin
                lifo_inputs[3][i]<=compressed_data[36+i];
                lengths[3]<=5'd11;
            end
        end
    end
    7'd48: begin
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[1][i]<=compressed_data[12+i];
                lengths[1]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[2][i]<=compressed_data[24+i];
                lengths[2]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[3][i]<=compressed_data[36+i];
                lengths[3]<=5'd12;
            end
        end
    end
    7'd49: begin
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[1][i]<=compressed_data[13+i];
                lengths[1]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[2][i]<=compressed_data[25+i];
                lengths[2]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[3][i]<=compressed_data[37+i];
                lengths[3]<=5'd12;
            end
        end
    end
    7'd50: begin
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[1][i]<=compressed_data[13+i];
                lengths[1]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[2][i]<=compressed_data[26+i];
                lengths[2]<=5'd12;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[3][i]<=compressed_data[38+i];
                lengths[3]<=5'd12;
            end
        end
    end
    7'd51: begin
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[1][i]<=compressed_data[13+i];
                lengths[1]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[2][i]<=compressed_data[26+i];
                lengths[2]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<12) begin
                lifo_inputs[3][i]<=compressed_data[39+i];
                lengths[3]<=5'd12;
            end
        end
    end
    7'd52: begin
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[1][i]<=compressed_data[13+i];
                lengths[1]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[2][i]<=compressed_data[26+i];
                lengths[2]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[3][i]<=compressed_data[39+i];
                lengths[3]<=5'd13;
            end
        end
    end
    7'd53: begin
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[1][i]<=compressed_data[14+i];
                lengths[1]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[2][i]<=compressed_data[27+i];
                lengths[2]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[3][i]<=compressed_data[40+i];
                lengths[3]<=5'd13;
            end
        end
    end
    7'd54: begin
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[1][i]<=compressed_data[14+i];
                lengths[1]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[2][i]<=compressed_data[28+i];
                lengths[2]<=5'd13;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[3][i]<=compressed_data[41+i];
                lengths[3]<=5'd13;
            end
        end
    end
    7'd55: begin
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[1][i]<=compressed_data[14+i];
                lengths[1]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[2][i]<=compressed_data[28+i];
                lengths[2]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<13) begin
                lifo_inputs[3][i]<=compressed_data[42+i];
                lengths[3]<=5'd13;
            end
        end
    end
    7'd56: begin
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[1][i]<=compressed_data[14+i];
                lengths[1]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[2][i]<=compressed_data[28+i];
                lengths[2]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[3][i]<=compressed_data[42+i];
                lengths[3]<=5'd14;
            end
        end
    end
    7'd57: begin
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[1][i]<=compressed_data[15+i];
                lengths[1]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[2][i]<=compressed_data[29+i];
                lengths[2]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[3][i]<=compressed_data[43+i];
                lengths[3]<=5'd14;
            end
        end
    end
    7'd58: begin
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[1][i]<=compressed_data[15+i];
                lengths[1]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[2][i]<=compressed_data[30+i];
                lengths[2]<=5'd14;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[3][i]<=compressed_data[44+i];
                lengths[3]<=5'd14;
            end
        end
    end
    7'd59: begin
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[1][i]<=compressed_data[15+i];
                lengths[1]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[2][i]<=compressed_data[30+i];
                lengths[2]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<14) begin
                lifo_inputs[3][i]<=compressed_data[45+i];
                lengths[3]<=5'd14;
            end
        end
    end
    7'd60: begin
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[1][i]<=compressed_data[15+i];
                lengths[1]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[2][i]<=compressed_data[30+i];
                lengths[2]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[3][i]<=compressed_data[45+i];
                lengths[3]<=5'd15;
            end
        end
    end
    7'd61: begin
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd16;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[1][i]<=compressed_data[16+i];
                lengths[1]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[2][i]<=compressed_data[31+i];
                lengths[2]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[3][i]<=compressed_data[46+i];
                lengths[3]<=5'd15;
            end
        end
    end
    7'd62: begin
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd16;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[1][i]<=compressed_data[16+i];
                lengths[1]<=5'd16;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[2][i]<=compressed_data[32+i];
                lengths[2]<=5'd15;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[3][i]<=compressed_data[47+i];
                lengths[3]<=5'd15;
            end
        end
    end
    7'd63: begin
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd16;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[1][i]<=compressed_data[16+i];
                lengths[1]<=5'd16;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[2][i]<=compressed_data[32+i];
                lengths[2]<=5'd16;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<15) begin
                lifo_inputs[3][i]<=compressed_data[48+i];
                lengths[3]<=5'd15;
            end
        end
    end
    7'd64: begin
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[0][i]<=compressed_data[0+i];
                lengths[0]<=5'd16;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[1][i]<=compressed_data[16+i];
                lengths[1]<=5'd16;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[2][i]<=compressed_data[32+i];
                lengths[2]<=5'd16;
            end
        end
        for (int i=0; i<16; i++) begin
            if (i<16) begin
                lifo_inputs[3][i]<=compressed_data[48+i];
                lengths[3]<=5'd16;
            end
        end
    end
endcase
end
end
endmodule
