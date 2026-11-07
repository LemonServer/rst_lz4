`timescale 1ps / 1ps
`default_nettype none

import parameter_pkg::*;

module OutputMerger_tb;

    // Signals
    logic clk;
    logic enable;
    logic [7:0] collected_data [LIFO_COUNT][DATA_WIDTH];
    logic [$clog2(DATA_WIDTH+1)-1:0] collected_lengths [LIFO_COUNT];
    logic [7:0] merged_data [DATA_WIDTH];

    // Instantiate the output_merger module
    OutputMerger duv (
        .clk(clk),
        .enable(enable),
        .collected_data(collected_data),
        .collected_lengths(collected_lengths),
        .merged_data(merged_data)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Task to print the output
    task print_output;
        int i;
        begin
            $display("Merged Data:");
            for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                $write("%0d ", merged_data[i]);
            end
            $display("");
        end
    endtask

    // Test sequence
    initial begin
        // Initialize signals
        enable = 0;
        for (int i = 0; i < LIFO_COUNT; i = i + 1) begin
            collected_lengths[i] = 0;
            for (int j = 0; j < DATA_WIDTH; j = j + 1) begin
                collected_data[i][j] = 8'h0;
            end
        end
        #10;
        // Test case 1: Simple case
        enable = 1;
        collected_lengths[0] = 16;
        collected_lengths[1] = 16;
        collected_lengths[2] = 16;
        collected_lengths[3] = 16;

        for (int i = 0; i < 16; i = i + 1) begin
            collected_data[0][i] = i + 1;
            collected_data[1][i] = i + 17;
            collected_data[2][i] = i + 33;
            collected_data[3][i] = i + 49;
        end

        #10;
        print_output();

        // Test case 2: Different lengths
        enable = 1;
        collected_lengths[0] = 2;
        collected_lengths[1] = 6;
        collected_lengths[2] = 3;
        collected_lengths[3] = 53;

        for (int i = 0; i < 2; i = i + 1) begin
            collected_data[0][i] = i + 1;
        end
        for (int i = 0; i < 6; i = i + 1) begin
            collected_data[1][i] = i + 3;
        end
        for (int i = 0; i < 3; i = i + 1) begin
            collected_data[2][i] = i + 9;
        end
        for (int i = 0; i < 53; i = i + 1) begin
            collected_data[3][i] = i + 12;
        end

        #10;
        print_output();

        // Finish simulation
        $finish;
    end

endmodule
