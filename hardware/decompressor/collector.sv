`timescale 1ps / 1ps
`default_nettype none
import parameter_pkg::*;
// gets bytes 0-2 per cycle from each LIFO.
// needs to assemble them as a contiguous output
// "staging area" is 64*# of LIFOs in bytes, so that doesn't scale super well but oh well.

// needs to be quite fast as well, since can only really start after the lifos are done?
// I think I can avoid a huge compation circuit since everything is grouped up

// just do it the simple way first and try to make timing
module Collector (
    input logic clk,
    input logic reset,
    input valid_byte lifo_output_byte1,
    input valid_byte lifo_output_byte2,
    input logic lifo_empty,
    output logic [7:0] collected_data [DATA_WIDTH],
    output logic [$clog2(DATA_WIDTH+1)-1:0] collected_length,
    output logic collection_done
);

    // Internal signals
    logic [$clog2(DATA_WIDTH+1)-1:0] write_index;
    logic collecting;
    logic lifo_empty_delay;

    // Initialization and reset
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            write_index <= 0;
            collected_length <= 0;
            collection_done <= 0;
            collecting <= 1;
        end else if (collecting) begin
            // Collect the first valid byte
            if (lifo_output_byte1.valid && lifo_output_byte2.valid) begin
                collected_data[write_index] <= lifo_output_byte1.byte_val;
                collected_data[write_index+1] <= lifo_output_byte2.byte_val;
                write_index <= write_index + 2;
            end else if (lifo_output_byte1.valid) begin
                collected_data[write_index] <= lifo_output_byte1.byte_val;
                write_index <= write_index + 1;
            end
            // Check if LIFO is empty 
            // need to wait one more cycle
            lifo_empty_delay <= lifo_empty;
            if (lifo_empty_delay) begin
                collected_length <= write_index;
                collection_done <= 1;
                collecting <= 0;
            end
        end
    end
endmodule
