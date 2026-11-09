`timescale 1ps / 1ps
`default_nettype none

import parameter_pkg::*;

module tb_DictBlockDecoder;
    logic [7:0] dict_blks_in [MEM_BLKS*64];
    dict_entry expansion_table [256];
    logic clk, reset, done, enable;

    task show_expansion_table;
        $display("expanded table:");
        for (int i = 0; i < 256; i++) begin
            if (expansion_table[i].seq_len != 0) begin
                $write("    %0d: ", i);
                for (int j=0; j<5; j++) begin
                    if (j < expansion_table[i].seq_len) begin
                        $write("%0d ", expansion_table[i].seq[j]);
                    end
                end
                $display();
            end
        end
        $display();
    endtask

    DictBlockDecoder duv (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .dict_blks_in(dict_blks_in),
        .expansion_table(expansion_table),
        .done(done)
    );

    always #5 clk = ~clk;
    
    // this was actually big endian whoops
    // works currently
    initial begin
        clk = 0;
        reset = 1;
        dict_blks_in = '{40, 80, 65, 24, 16, 16, 25, 24, 0, 27, 26, 231, 39, 217, 185, 56, 16, 0, 62, 1, 25, 72, 24, 24, 128, 110, 0, 130, 53, 39, 131, 52, 39, 16, 0, 0, 0, 37, 0, 101, 0, 51, 0, 97, 0, 63, 0, 111, 0, 125, 0, 47, 0, 127, 145, 164, 2, 248, 124, 62, 65, 0, 0, 248};
        enable = 1;
        #10; 
        reset = 0;
        while (!done) begin
            #10; 
            $display("time=%0t, state=%0s, next_state=%0s", $time, duv.state.name(), duv.next_state.name());
            $display("counts: [%0d, %0d, %0d, %0d]", duv.counts[0], duv.counts[1], duv.counts[2], duv.counts[3]);
            $display("leader_idxs: [%0d, %0d, %0d, %0d]", duv.leader_indices[0], duv.leader_indices[1], duv.leader_indices[2], duv.leader_indices[3]);
        end
        // should be [27, 10, 4, 8]
        show_expansion_table();
        $finish();
    end

// 3: 0 0 0
// 5: 3 0
// 6: 27 19 5
// 14: 2 5
// 15: 5 0
// 17: 171 14
// 18: 224 141 180 15 128
// 20: 32 11 5
// 21: 18 226 173 14 16
// 23: 48 65 17 96 229
// 35: 21 250 129 15
// 37: 144 30 15
// 38: 26 19 5
// 39: 23 17
// 41: 3 3 3
// 43: 246 20
// 44: 39 112 233 24 19
// 52: 50 176 14
// 54: 32 247 20
// 58: 3 5
// 59: 43 35
// 61: 80 52
// 62: 37 168 59 61 39
// 63: 37 61 35 208 43
// 67: 37 208 59 54 39
// 68: 44 5
// 69: 248 20
// 71: 173 14
// 73: 37 54 35 168 43
// 74: 48 65 171 2
// 76: 1 3 4 58
// 77: 26 6
// 79: 29 6
// 82: 27 6
// 83: 28 6
// 84: 30 6
// 86: 33 6
// 88: 146 38
// 89: 10 6
// 91: 32 6
// 92: 11 6
// 93: 64 230 71
// 94: 48 65 17
// 95: 63 39
// 97: 31 6
// 98: 34 6
// 99: 49 58 74 3
// 101: 7 6
// 103: 8 6

endmodule