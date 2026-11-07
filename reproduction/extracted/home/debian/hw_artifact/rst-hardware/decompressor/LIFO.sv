`timescale 1ps / 1ps
`default_nettype none

import parameter_pkg::*;
module LIFO (
    input logic clk, reset,
    input logic [7:0] compressed_data [LIFO_INPUT_WIDTH],
    input logic [$clog2(LIFO_INPUT_WIDTH+1)-1:0] compressed_length,
    input dict_entry expansion_table [256],
    output valid_byte output_byte1,
    output valid_byte output_byte2,
    output logic empty
);
    logic [7:0] stack_mem [MAX_LIFO_SIZE];
    logic [$clog2(MAX_LIFO_SIZE)-1:0] sp;
    logic one_left;

    assign one_left = (sp == 1);
    assign empty = (sp == 0);

    bit [7:0] popped_byte_top, popped_byte_bottom;

    assign popped_byte_top = (empty) ? '0 : stack_mem[sp-1];
    assign popped_byte_bottom = (empty || one_left) ? '0 : stack_mem[sp-2];

    bit [2:0] seq_len_top, seq_len_bottom;
    assign seq_len_top = expansion_table[popped_byte_top].seq_len;
    assign seq_len_bottom = expansion_table[popped_byte_bottom].seq_len;

    always_ff @(posedge clk) begin
        if (reset) begin
            sp <= compressed_length;
            for (int i=0; i<LIFO_INPUT_WIDTH; i++) begin
                if (i < compressed_length)
                    stack_mem[compressed_length-i-1] <= compressed_data[i];
                else
                    stack_mem[i] <= '0;
            end
        end else begin
            output_byte1 <= '0;
            output_byte2 <= '0;
            // popped byte top can become output_byte1
            // popped byte bottom can become output_byte2

            // might not be that large though if I'm splitting 64 bytes 4 or 8 ways even.
            // probably worth it for latency

            // tedious but let's do it
            if (!empty && !one_left) begin // can process both
                case (seq_len_bottom)
                    3'd0: begin
                        case (seq_len_top)
                            3'd0: begin // both zero, just output both
                                output_byte1 <= '{popped_byte_top, 1'b1};
                                output_byte2 <= '{popped_byte_bottom, 1'b1};
                                sp <= sp-2;
                            end
                            3'd2: begin // top expands, bottom stays put
                                stack_mem[sp-1] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp] <= expansion_table[popped_byte_top].seq[1];
                                sp <= sp+1;
                            end
                            3'd3: begin // top expands, bottom stays put
                                stack_mem[sp-1] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[2];
                                sp <= sp+2;
                            end
                            3'd4: begin // top expands, bottom stays put
                                stack_mem[sp-1] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[3];
                                sp <= sp+3;
                            end
                            3'd5: begin // top expands, bottom stays put
                                stack_mem[sp-1] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[3];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[4];
                                sp <= sp+4;
                            end
                        endcase
                    end 
                    3'd2: begin
                        stack_mem[sp-2] <= expansion_table[popped_byte_bottom].seq[0];
                        stack_mem[sp-1] <= expansion_table[popped_byte_bottom].seq[1];
                        case (seq_len_top)
                            3'd0: begin // top outputs, bottom expands
                                output_byte1 <= '{popped_byte_top, 1'b1};
                                sp <= sp; // no change
                            end
                            3'd2: begin // both expand
                                stack_mem[sp] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[1];
                                sp <= sp+2;
                            end
                            3'd3: begin // both expand
                                stack_mem[sp] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[2];
                                sp <= sp+3;
                            end
                            3'd4: begin // both expand
                                stack_mem[sp] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[3];
                                sp <= sp+4;
                            end
                            3'd5: begin // both expand
                                stack_mem[sp] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[3];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[4];
                                sp <= sp+5;
                            end
                        endcase
                    end
                    3'd3: begin
                        stack_mem[sp-2] <= expansion_table[popped_byte_bottom].seq[0];
                        stack_mem[sp-1] <= expansion_table[popped_byte_bottom].seq[1];
                        stack_mem[sp] <= expansion_table[popped_byte_bottom].seq[2];
                        case (seq_len_top)
                            3'd0: begin // top outputs, bottom expands
                                output_byte1 <= '{popped_byte_top, 1'b1};
                                sp <= sp+1;
                            end
                            3'd2: begin // both expand
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[1];
                                sp <= sp+3;
                            end
                            3'd3: begin // both expand
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[2];
                                sp <= sp+4;
                            end
                            3'd4: begin // both expand
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[3];
                                sp <= sp+5;
                            end
                            3'd5: begin // both expand
                                stack_mem[sp+1] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[3];
                                stack_mem[sp+5] <= expansion_table[popped_byte_top].seq[4];
                                sp <= sp+6;
                            end
                        endcase
                    end
                    3'd4: begin
                        stack_mem[sp-2] <= expansion_table[popped_byte_bottom].seq[0];
                        stack_mem[sp-1] <= expansion_table[popped_byte_bottom].seq[1];
                        stack_mem[sp] <= expansion_table[popped_byte_bottom].seq[2];
                        stack_mem[sp+1] <= expansion_table[popped_byte_bottom].seq[3];
                        case (seq_len_top)
                            3'd0: begin // top outputs, bottom expands
                                output_byte1 <= '{popped_byte_top, 1'b1};
                                sp <= sp+2;
                            end
                            3'd2: begin // both expand
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[1];
                                sp <= sp+4;
                            end
                            3'd3: begin // both expand
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[2];
                                sp <= sp+5;
                            end
                            3'd4: begin // both expand
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+5] <= expansion_table[popped_byte_top].seq[3];
                                sp <= sp+6;
                            end
                            3'd5: begin // both expand
                                stack_mem[sp+2] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+5] <= expansion_table[popped_byte_top].seq[3];
                                stack_mem[sp+6] <= expansion_table[popped_byte_top].seq[4];
                                sp <= sp+7;
                            end
                        endcase
                    end
                    3'd5: begin
                        stack_mem[sp-2] <= expansion_table[popped_byte_bottom].seq[0];
                        stack_mem[sp-1] <= expansion_table[popped_byte_bottom].seq[1];
                        stack_mem[sp] <= expansion_table[popped_byte_bottom].seq[2];
                        stack_mem[sp+1] <= expansion_table[popped_byte_bottom].seq[3];
                        stack_mem[sp+2] <= expansion_table[popped_byte_bottom].seq[4];
                        case (seq_len_top)
                            3'd0: begin // top outputs, bottom expands
                                output_byte1 <= '{popped_byte_top, 1'b1};
                                sp <= sp+3;
                            end
                            3'd2: begin // both expand
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[1];
                                sp <= sp+5;
                            end
                            3'd3: begin // both expand
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+5] <= expansion_table[popped_byte_top].seq[2];
                                sp <= sp+6;
                            end
                            3'd4: begin // both expand
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+5] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+6] <= expansion_table[popped_byte_top].seq[3];
                                sp <= sp+7;
                            end
                            3'd5: begin // both expand
                                stack_mem[sp+3] <= expansion_table[popped_byte_top].seq[0];
                                stack_mem[sp+4] <= expansion_table[popped_byte_top].seq[1];
                                stack_mem[sp+5] <= expansion_table[popped_byte_top].seq[2];
                                stack_mem[sp+6] <= expansion_table[popped_byte_top].seq[3];
                                stack_mem[sp+7] <= expansion_table[popped_byte_top].seq[4];
                                sp <= sp+8;
                            end
                        endcase
                    end
                endcase
            end else if (!empty) begin // just process top (one left)
                if (expansion_table[popped_byte_top].seq_len != 0) begin
                    for (int i=0; i<5; i++) begin // gross but probably works?
                        if (i < expansion_table[popped_byte_top].seq_len) begin
                            stack_mem[sp-1+i] <= expansion_table[popped_byte_top].seq[i];
                        end
                    end
                    sp <= sp+expansion_table[popped_byte_top].seq_len-1;
                end else begin
                    output_byte1 <= '{popped_byte_top, 1'b1};
                    sp <= sp-1;
                end

            end
        end
    end
endmodule