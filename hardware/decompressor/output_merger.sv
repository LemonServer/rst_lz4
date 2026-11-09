`timescale 1ps / 1ps
`default_nettype none

import parameter_pkg::*;

module OutputMerger (
    input logic clk, enable,
    input logic [7:0] collected_data [LIFO_COUNT][DATA_WIDTH],
    input logic [$clog2(DATA_WIDTH+1)-1:0] collected_lengths [LIFO_COUNT],
    output logic [7:0] merged_data [DATA_WIDTH]
);
    // Internal signals
    logic [$clog2(DATA_WIDTH)-1:0] merge_idx;

    // eventually make this more area efficient.
    // Reset and initialization
    always_ff @(posedge clk) begin
        if (enable) begin
            merge_idx = 0;
            for (int lifo_idx = 0; lifo_idx < LIFO_COUNT; lifo_idx++) begin
                for (int data_idx = 0; data_idx < collected_lengths[lifo_idx]; data_idx++) begin
                    merged_data[merge_idx] <= collected_data[lifo_idx][data_idx];
                    merge_idx++;
                end
            end
        end
    end
endmodule
