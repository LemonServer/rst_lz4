`timescale 1ps / 1ps
`default_nettype none

module tb_MatchFilterReplace;
    import rst_pkg::*;

    localparam int CLK_HALF = 5;

    logic clk;
    logic rst;
    logic i_valid;
    vsym_t pre_sub [CHUNK_WIDTH];
    seq_t sel_seq;
    logic [2:0] sel_seq_len;
    symbol_t repl_sym;
    logic o_valid;
    vsym_t post_sub [CHUNK_WIDTH];
    logic [CHUNK_WIDTH-1:0] sub_sites;

    MatchFilterReplace dut (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .pre_sub(pre_sub),
        .sel_seq(sel_seq),
        .sel_seq_len(sel_seq_len),
        .repl_sym(repl_sym),
        .o_valid(o_valid),
        .post_sub(post_sub),
        .sub_sites(sub_sites)
    );

    always #(CLK_HALF) clk = ~clk;

    function automatic seq_t make_seq2(input int s0, input int s1);
        seq_t seq;
        begin
            seq = '0;
            seq[0] = symbol_t'(s0);
            seq[1] = symbol_t'(s1);
            return seq;
        end
    endfunction

    function automatic seq_t make_seq3(input int s0, input int s1, input int s2);
        seq_t seq;
        begin
            seq = '0;
            seq[0] = symbol_t'(s0);
            seq[1] = symbol_t'(s1);
            seq[2] = symbol_t'(s2);
            return seq;
        end
    endfunction

    function automatic seq_t make_seq5(
        input int s0,
        input int s1,
        input int s2,
        input int s3,
        input int s4
    );
        seq_t seq;
        begin
            seq = '0;
            seq[0] = symbol_t'(s0);
            seq[1] = symbol_t'(s1);
            seq[2] = symbol_t'(s2);
            seq[3] = symbol_t'(s3);
            seq[4] = symbol_t'(s4);
            return seq;
        end
    endfunction

    task automatic clear_case;
        begin
            i_valid = 1'b0;
            clear_payload();
        end
    endtask

    task automatic clear_payload;
        begin
            sel_seq = '0;
            sel_seq_len = '0;
            repl_sym = '0;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                pre_sub[i] = '0;
            end
        end
    endtask

    task automatic load_symbol(
        input int idx,
        input int sym,
        input logic valid
    );
        begin
            pre_sub[idx].sym = symbol_t'(sym);
            pre_sub[idx].valid = valid;
        end
    endtask

    task automatic init_expected(
        output symbol_t expected_syms [CHUNK_WIDTH],
        output logic expected_valid [CHUNK_WIDTH]
    );
        begin
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                expected_syms[i] = '0;
                expected_valid[i] = 1'b0;
            end
        end
    endtask

    task automatic check_case(
        input string label,
        input logic [CHUNK_WIDTH-1:0] expected_sites,
        input symbol_t expected_syms [CHUNK_WIDTH],
        input logic expected_valid [CHUNK_WIDTH]
    );
        begin
            #1;
            if (!o_valid) begin
                $fatal(1, "%s expected o_valid high", label);
            end
            if (sub_sites !== expected_sites) begin
                $fatal(1, "%s substitution sites mismatch: got %b expected %b",
                    label, sub_sites[31:0], expected_sites[31:0]);
            end
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if ((post_sub[i].valid !== expected_valid[i]) ||
                    (post_sub[i].sym !== expected_syms[i])) begin
                    $fatal(1, "%s post_sub mismatch at %0d: got {%0d,%0b} expected {%0d,%0b}",
                        label, i, post_sub[i].sym, post_sub[i].valid,
                        expected_syms[i], expected_valid[i]);
                end
            end
        end
    endtask

    task automatic launch_case;
        begin
            @(negedge clk);
            i_valid = 1'b1;
            @(negedge clk);
            i_valid = 1'b0;
        end
    endtask

    task automatic wait_valid_and_check(
        input string label,
        input logic [CHUNK_WIDTH-1:0] expected_sites,
        input symbol_t expected_syms [CHUNK_WIDTH],
        input logic expected_valid [CHUNK_WIDTH]
    );
        begin
            do begin
                @(posedge clk);
                #1;
            end while (!o_valid);
            check_case(label, expected_sites, expected_syms, expected_valid);
        end
    endtask

    task automatic reset_dut;
        begin
            clear_case();
            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
            if (o_valid !== 1'b0) begin
                $fatal(1, "o_valid should reset low");
            end
        end
    endtask

    initial begin
        symbol_t expected_syms [CHUNK_WIDTH];
        logic expected_valid [CHUNK_WIDTH];
        logic [CHUNK_WIDTH-1:0] expected_sites;
        symbol_t expected_syms_b [CHUNK_WIDTH];
        logic expected_valid_b [CHUNK_WIDTH];
        logic [CHUNK_WIDTH-1:0] expected_sites_b;

        clk = 1'b0;
        reset_dut();

        clear_case();
        init_expected(expected_syms, expected_valid);

        load_symbol(0, 10, 1'b1);
        load_symbol(1, 11, 1'b1);
        load_symbol(2, 10, 1'b1);
        load_symbol(3, 11, 1'b1);
        load_symbol(4, 10, 1'b1);
        load_symbol(5, 11, 1'b1);
        load_symbol(6, 12, 1'b1);
        load_symbol(7, 13, 1'b1);
        sel_seq = make_seq2(10, 11);
        sel_seq_len = 3'd2;
        repl_sym = 9'h180;

        expected_sites = '0;
        expected_sites[0] = 1'b1;
        expected_sites[2] = 1'b1;
        expected_sites[4] = 1'b1;
        expected_syms[0] = repl_sym;
        expected_syms[1] = repl_sym;
        expected_syms[2] = repl_sym;
        expected_syms[3] = symbol_t'(12);
        expected_syms[4] = symbol_t'(13);
        expected_valid[0] = 1'b1;
        expected_valid[1] = 1'b1;
        expected_valid[2] = 1'b1;
        expected_valid[3] = 1'b1;
        expected_valid[4] = 1'b1;

        launch_case();
        wait_valid_and_check("len2-nonoverlap-chain", expected_sites, expected_syms, expected_valid);
        @(posedge clk);
        #1;
        if (o_valid !== 1'b0) begin
            $fatal(1, "o_valid should pulse for one cycle on a single launch");
        end

        clear_case();
        init_expected(expected_syms, expected_valid);

        for (int i = 0; i < 8; i++) begin
            load_symbol(i, 7, 1'b1);
        end
        sel_seq = make_seq3(7, 7, 7);
        sel_seq_len = 3'd3;
        repl_sym = 9'h1A0;

        expected_sites = '0;
        expected_sites[0] = 1'b1;
        expected_sites[3] = 1'b1;
        expected_syms[0] = repl_sym;
        expected_syms[1] = repl_sym;
        expected_syms[2] = symbol_t'(7);
        expected_syms[3] = symbol_t'(7);
        expected_valid[0] = 1'b1;
        expected_valid[1] = 1'b1;
        expected_valid[2] = 1'b1;
        expected_valid[3] = 1'b1;

        launch_case();
        wait_valid_and_check("len3-overlap-filter", expected_sites, expected_syms, expected_valid);

        clear_case();
        init_expected(expected_syms, expected_valid);

        load_symbol(0, 1, 1'b1);
        load_symbol(1, 9'h101, 1'b1);
        load_symbol(2, 2, 1'b1);
        load_symbol(3, 3, 1'b1);
        load_symbol(4, 4, 1'b1);
        load_symbol(5, 1, 1'b1);
        load_symbol(6, 9'h101, 1'b1);
        load_symbol(7, 2, 1'b0);
        load_symbol(8, 3, 1'b1);
        load_symbol(9, 4, 1'b1);
        sel_seq = make_seq5(1, 9'h101, 2, 3, 4);
        sel_seq_len = 3'd5;
        repl_sym = 9'h1C3;

        expected_sites = '0;
        expected_sites[0] = 1'b1;
        expected_syms[0] = repl_sym;
        expected_syms[1] = symbol_t'(1);
        expected_syms[2] = symbol_t'(9'h101);
        expected_syms[3] = symbol_t'(3);
        expected_syms[4] = symbol_t'(4);
        expected_valid[0] = 1'b1;
        expected_valid[1] = 1'b1;
        expected_valid[2] = 1'b1;
        expected_valid[3] = 1'b1;
        expected_valid[4] = 1'b1;

        launch_case();
        wait_valid_and_check("len5-9bit-invalid-suppression", expected_sites, expected_syms, expected_valid);

        clear_case();
        init_expected(expected_syms, expected_valid);

        load_symbol(0, 3, 1'b1);
        load_symbol(1, 4, 1'b1);
        load_symbol(2, 3, 1'b1);
        load_symbol(3, 4, 1'b1);
        load_symbol(4, 8, 1'b1);
        sel_seq = make_seq2(3, 4);
        sel_seq_len = 3'd2;
        repl_sym = 9'h141;

        expected_sites = '0;
        expected_sites[0] = 1'b1;
        expected_sites[2] = 1'b1;
        expected_syms[0] = repl_sym;
        expected_syms[1] = repl_sym;
        expected_syms[2] = symbol_t'(8);
        expected_valid[0] = 1'b1;
        expected_valid[1] = 1'b1;
        expected_valid[2] = 1'b1;

        launch_case();
        wait_valid_and_check("repeat_case_a", expected_sites, expected_syms, expected_valid);

        clear_case();
        init_expected(expected_syms_b, expected_valid_b);

        for (int i = 0; i < 6; i++) begin
            load_symbol(i, 5, 1'b1);
        end
        sel_seq = make_seq3(5, 5, 5);
        sel_seq_len = 3'd3;
        repl_sym = 9'h142;

        expected_sites_b = '0;
        expected_sites_b[0] = 1'b1;
        expected_sites_b[3] = 1'b1;
        expected_syms_b[0] = repl_sym;
        expected_syms_b[1] = repl_sym;
        expected_valid_b[0] = 1'b1;
        expected_valid_b[1] = 1'b1;

        launch_case();
        wait_valid_and_check("repeat_case_b", expected_sites_b, expected_syms_b, expected_valid_b);

        $finish;
    end
endmodule
