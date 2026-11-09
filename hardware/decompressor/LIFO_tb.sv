`timescale 1ps / 1ps
`default_nettype none

import parameter_pkg::*;

module tb_LIFO;

    logic clk, lifo_reset, empty;
    logic table_reset, table_done, table_enable;

    logic [7:0] compressed_data [LIFO_INPUT_WIDTH];
    logic [$clog2(LIFO_INPUT_WIDTH+1)-1:0] compressed_length;
    dict_entry expansion_table [256];
    valid_byte output_byte1;
    valid_byte output_byte2;
    logic [7:0] dict_blks_in [MEM_BLKS*64];
    int total_outs;

    DictBlockDecoder blk_decoder (
        .clk(clk),
        .reset(table_reset),
        .enable(table_enable),
        .dict_blks_in(dict_blks_in),
        .expansion_table(expansion_table),
        .done(table_done)
    );

    LIFO duv (
        .clk(clk), .reset(lifo_reset),
        .compressed_data(compressed_data),
        .compressed_length(compressed_length),
        .expansion_table(expansion_table),
        .output_byte1(output_byte1),
        .output_byte2(output_byte2),
        .empty(empty)
    );    

    always #5 clk = ~clk;
    initial begin
        clk = 0;
        dict_blks_in = '{40, 80, 65, 24, 16, 16, 25, 24, 0, 27, 26, 231, 39, 217, 185, 56, 16, 0, 62, 1, 25, 72, 24, 24, 128, 110, 0, 130, 53, 39, 131, 52, 39, 16, 0, 0, 0, 37, 0, 101, 0, 51, 0, 97, 0, 63, 0, 111, 0, 125, 0, 47, 0, 127, 145, 164, 2, 248, 124, 62, 65, 0, 0, 248};
        compressed_data = '{25, 0, 203, 0, 27, 252, 2, 27, 72, 45, 83, 216, 185, 23, 131, 150, 0, 27, 72, 72, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
        compressed_length = 20;
        table_reset = 1;
        table_enable = 1;
        lifo_reset = 1;
        #10;
        table_reset = 0;
        while (!table_done) begin
            #10; 
            $display("time=%0t, state=%0s, next_state=%0s", $time, blk_decoder.state.name(), blk_decoder.next_state.name());
            $display("counts: [%0d, %0d, %0d, %0d]", blk_decoder.counts[0], blk_decoder.counts[1], blk_decoder.counts[2], blk_decoder.counts[3]);
            $display("leader_idxs: [%0d, %0d, %0d, %0d]", blk_decoder.leader_indices[0], blk_decoder.leader_indices[1], blk_decoder.leader_indices[2], blk_decoder.leader_indices[3]);
        end
        lifo_reset = 0;
        total_outs = 0;
        while (!empty) begin
        // for (int i=0; i<100; i++) begin
            #10;
            if (output_byte1.valid) begin
                total_outs++;
                if (output_byte2.valid) begin
                    total_outs++;
                    $write("%0d, %0d, ", output_byte1.byte_val, output_byte2.byte_val);
                    // $display("time=%0t out_byte1=%0h out_byte2=%0h sp=%0d byte#=%0d", $time, output_byte1.byte_val, output_byte2.byte_val, duv.sp, total_outs);
                end else
                    $write("%0d, ", output_byte1.byte_val);
                    // $display("time=%0t out_byte1=%0h sp=%0d byte#=%0d", $time, output_byte1.byte_val, duv.sp, total_outs);
            end
        end
        //perfect match
        $display();
        $finish;
    end

endmodule