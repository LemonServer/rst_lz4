`timescale 1ps / 1ps
`default_nettype none
import parameter_pkg::*;

module tb_Partitioner;
    logic clk;
    logic enable;
    logic [7:0] compressed_data [DATA_WIDTH];
    logic [$clog2(DATA_WIDTH+1)-1:0] length;
    logic [7:0] lifo_inputs [LIFO_COUNT][LIFO_INPUT_WIDTH];
    logic [$clog2(LIFO_INPUT_WIDTH+1)-1:0] lengths [LIFO_COUNT];

    Partitioner duv (
        .clk(clk),
        .enable(enable),
        .compressed_data(compressed_data),
        .length(length),
        .lifo_inputs(lifo_inputs),
        .lengths(lengths)
    );
    task print_output;
        int i, j;
        begin
            $display("Length: %0d", length);
            for (i = 0; i < LIFO_COUNT; i = i + 1) begin
                $display("Partition %0d (Length: %0d):", i, lengths[i]);
                for (j = 0; j < LIFO_INPUT_WIDTH; j = j + 1) begin
                    if (j < lengths[i])
                        $write("%0d ", lifo_inputs[i][j]);
                end
                $display();
            end
        end
    endtask
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        // Initialize signals
        enable = 0;
        length = 0;
        for (int i = 0; i < DATA_WIDTH; i++) begin
            compressed_data[i] = 8'h0;
        end

        // Wait for the reset
        #10;
        print_output();
        // Test case 1: Simple case with length = 8
        enable = 1;
        length = 8;
        for (int i = 0; i < 8; i = i + 1) begin
            compressed_data[i] = i + 1;
        end
        #10;
        print_output();
        // Test case 2: Length = 64
        enable = 1;
        length = 64;
        for (int i = 0; i < 64; i = i + 1) begin
            compressed_data[i] = i + 1;
        end
        #10;
        print_output();
        // Test case 3: Length = 13
        enable = 1;
        length = 13;
        for (int i = 0; i < 32; i = i + 1) begin
            compressed_data[i] = i + 1;
        end
        #10;
        print_output();
        // Test case 4: Length = 16
        enable = 1;
        length = 16;
        for (int i = 0; i < 16; i = i + 1) begin
            compressed_data[i] = i + 1;
        end
        #10;
        print_output();
        // Test case 5: Length = 0
        enable = 1;
        length = 0;
        #10;
        print_output();
        // Finish simulation
        $finish;
    end

endmodule
