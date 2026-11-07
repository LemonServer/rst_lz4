`timescale 1ps / 1ps
`default_nettype none

module tb_Matcher;
    import rst_pkg::*;

    vsym_t symbols [CHUNK_WIDTH];
    seq_t seq;
    logic [2:0] seq_len;
    logic [CHUNK_WIDTH-1:0] match_vec;

    Matcher dut (
        .symbols(symbols),
        .seq(seq),
        .seq_len(seq_len),
        .match_vec(match_vec)
    );

    task automatic clear_symbols;
        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            symbols[i] = '{sym: '0, valid: 1'b0};
        end
    endtask

    task automatic expect_matches(
        input string label,
        input logic [CHUNK_WIDTH-1:0] expected
    );
        begin
            #1;
            $write("%s matches:", label);
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (match_vec[i]) begin
                    $write(" %0d", i);
                end
            end
            $display();
            if (match_vec !== expected) begin
                $fatal(1, "%s mismatch: got %b expected %b", label, match_vec[31:0], expected[31:0]);
            end
        end
    endtask

    initial begin
        logic [CHUNK_WIDTH-1:0] expected;

        clear_symbols();
        seq = '0;

        seq[0] = 9'h0AA;
        seq[1] = 9'h0BB;
        seq_len = 3'd2;
        symbols[0] = '{sym: 9'h0AA, valid: 1'b1};
        symbols[1] = '{sym: 9'h0BB, valid: 1'b1};
        symbols[2] = '{sym: 9'h055, valid: 1'b1};
        symbols[6] = '{sym: 9'h0AA, valid: 1'b1};
        symbols[7] = '{sym: 9'h0BB, valid: 1'b1};
        symbols[8] = '{sym: 9'h0AA, valid: 1'b1};
        symbols[9] = '{sym: 9'h033, valid: 1'b1};
        expected = '0;
        expected[0] = 1'b1;
        expected[6] = 1'b1;
        expect_matches("len2", expected);

        clear_symbols();
        seq[0] = 9'h011;
        seq[1] = 9'h022;
        seq[2] = 9'h033;
        seq_len = 3'd3;
        symbols[4] = '{sym: 9'h011, valid: 1'b1};
        symbols[5] = '{sym: 9'h022, valid: 1'b1};
        symbols[6] = '{sym: 9'h033, valid: 1'b1};
        symbols[12] = '{sym: 9'h011, valid: 1'b1};
        symbols[13] = '{sym: 9'h022, valid: 1'b1};
        symbols[14] = '{sym: 9'h033, valid: 1'b1};
        symbols[18] = '{sym: 9'h011, valid: 1'b1};
        symbols[19] = '{sym: 9'h022, valid: 1'b1};
        symbols[20] = '{sym: 9'h033, valid: 1'b0};
        expected = '0;
        expected[4] = 1'b1;
        expected[12] = 1'b1;
        expect_matches("len3", expected);

        clear_symbols();
        seq[0] = 9'h041;
        seq[1] = 9'h042;
        seq[2] = 9'h043;
        seq[3] = 9'h044;
        seq[4] = 9'h045;
        seq_len = 3'd5;
        symbols[40] = '{sym: 9'h041, valid: 1'b1};
        symbols[41] = '{sym: 9'h042, valid: 1'b1};
        symbols[42] = '{sym: 9'h043, valid: 1'b1};
        symbols[43] = '{sym: 9'h044, valid: 1'b1};
        symbols[44] = '{sym: 9'h045, valid: 1'b1};
        symbols[80] = '{sym: 9'h041, valid: 1'b1};
        symbols[81] = '{sym: 9'h042, valid: 1'b1};
        symbols[82] = '{sym: 9'h043, valid: 1'b1};
        symbols[83] = '{sym: 9'h044, valid: 1'b1};
        symbols[84] = '{sym: 9'h045, valid: 1'b1};
        expected = '0;
        expected[40] = 1'b1;
        expected[80] = 1'b1;
        expect_matches("len5", expected);

        clear_symbols();
        seq_len = 3'd1;
        expected = '0;
        expect_matches("invalid-len", expected);

        $finish;
    end
endmodule
