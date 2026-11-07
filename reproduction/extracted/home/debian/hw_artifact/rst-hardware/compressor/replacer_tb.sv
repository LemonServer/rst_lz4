`timescale 1ps / 1ps
`default_nettype none

module tb_Replacer;
    import rst_pkg::*;

    vsym_t pre_sub [CHUNK_WIDTH];
    logic [CHUNK_WIDTH-1:0] filtered_matches;
    symbol_t repl_sym;
    logic [2:0] seq_len;
    vsym_t post_sub [CHUNK_WIDTH];
    int unsigned seed;

    Replacer dut (
        .pre_sub(pre_sub),
        .filtered_matches(filtered_matches),
        .repl_sym(repl_sym),
        .seq_len(seq_len),
        .post_sub(post_sub)
    );

    function automatic int unsigned next_rand(input int unsigned state);
        int unsigned next_state;
        begin
            next_state = state;
            next_state = next_state ^ (next_state << 13);
            next_state = next_state ^ (next_state >> 17);
            next_state = next_state ^ (next_state << 5);
            return next_state;
        end
    endfunction

    task automatic init_case;
        begin
            filtered_matches = '0;
            repl_sym = '0;
            seq_len = 3'd2;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                pre_sub[i] = '{sym: symbol_t'(i), valid: 1'b1};
            end
        end
    endtask

    task automatic compute_expected_post(
        output symbol_t expected_syms [CHUNK_WIDTH],
        output logic expected_valid [CHUNK_WIDTH]
    );
        vsym_t uncompacted_ref [CHUNK_WIDTH];
        int prefix_sum [CHUNK_WIDTH];
        int running_count;

        begin
            running_count = 0;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                uncompacted_ref[i] = pre_sub[i];
                prefix_sum[i] = 0;
                expected_syms[i] = '0;
                expected_valid[i] = 1'b0;
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (filtered_matches[i]) begin
                    uncompacted_ref[i].sym = repl_sym;
                    for (int j = 1; j < MAX_SEQ_LEN; j++) begin
                        if (j < seq_len && (i + j) < CHUNK_WIDTH) begin
                            uncompacted_ref[i + j].valid = 1'b0;
                        end
                    end
                end
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (uncompacted_ref[i].valid) begin
                    running_count++;
                end
                prefix_sum[i] = running_count;
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (uncompacted_ref[i].valid) begin
                    expected_syms[prefix_sum[i] - 1] = uncompacted_ref[i].sym;
                    expected_valid[prefix_sum[i] - 1] = 1'b1;
                end
            end
        end
    endtask

    task automatic run_case(input string label);
        symbol_t expected_syms [CHUNK_WIDTH];
        logic expected_valid [CHUNK_WIDTH];

        begin
            compute_expected_post(expected_syms, expected_valid);
            #1;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if ((post_sub[i].sym !== expected_syms[i]) ||
                    (post_sub[i].valid !== expected_valid[i])) begin
                    $fatal(1, "%s mismatch at %0d: got {%0d,%0b} expected {%0d,%0b}",
                        label, i, post_sub[i].sym, post_sub[i].valid,
                        expected_syms[i], expected_valid[i]);
                end
            end
        end
    endtask

    initial begin
        init_case();
        repl_sym = 9'h1FF;
        seq_len = 3'd2;
        filtered_matches[0] = 1'b1;
        filtered_matches[5] = 1'b1;
        run_case("len2-basic");

        init_case();
        repl_sym = 9'h155;
        seq_len = 3'd4;
        filtered_matches[1] = 1'b1;
        filtered_matches[8] = 1'b1;
        pre_sub[4].valid = 1'b0;
        pre_sub[11].valid = 1'b0;
        run_case("len4-invalid-holes");

        init_case();
        repl_sym = 9'h123;
        seq_len = 3'd3;
        filtered_matches[0] = 1'b1;
        filtered_matches[1] = 1'b1;
        filtered_matches[4] = 1'b1;
        pre_sub[2].valid = 1'b0;
        pre_sub[7].valid = 1'b0;
        run_case("len3-overlapping-matches");

        seed = 32'h51c0_ffee;
        for (int case_idx = 0; case_idx < 300; case_idx++) begin
            init_case();

            seed = next_rand(seed);
            seq_len = 3'd2 + seed[1:0];

            seed = next_rand(seed);
            repl_sym = symbol_t'(seed[8:0]);

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                seed = next_rand(seed);
                pre_sub[i].sym = symbol_t'(seed[8:0]);
                pre_sub[i].valid = seed[9];
                seed = next_rand(seed);
                filtered_matches[i] = seed[0];
            end

            run_case($sformatf("random-%0d-len%0d", case_idx, seq_len));
        end

        $finish;
    end
endmodule
