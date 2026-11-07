`timescale 1ps / 1ps
`default_nettype none

module tb_Filter;
    import rst_pkg::*;

    localparam int INDEX_W = $clog2(CHUNK_WIDTH);

    logic [CHUNK_WIDTH-1:0] candidates;
    logic [2:0] seq_len;
    logic [CHUNK_WIDTH-1:0] filtered_matches;

    Filter dut (
        .candidates(candidates),
        .seq_len(seq_len),
        .filtered_matches(filtered_matches)
    );

    function automatic logic [2:0] mod_lut_ref(
        input int idx,
        input logic [3:0] mod
    );
        logic [3:0] rem;
        begin
            case (mod)
                4'd2: mod_lut_ref = {2'b00, idx[0]};
                4'd3: begin
                    rem = '0;
                    for (int step = INDEX_W - 1; step >= 0; step--) begin
                        rem = {rem[2:0], idx[step]};
                        if (rem >= 4'd3) begin
                            rem = rem - 4'd3;
                        end
                    end
                    mod_lut_ref = rem[2:0];
                end
                4'd4: mod_lut_ref = {1'b0, idx[1:0]};
                4'd5: begin
                    rem = '0;
                    for (int step = INDEX_W - 1; step >= 0; step--) begin
                        rem = {rem[2:0], idx[step]};
                        if (rem >= 4'd5) begin
                            rem = rem - 4'd5;
                        end
                    end
                    mod_lut_ref = rem[2:0];
                end
                4'd8: mod_lut_ref = idx[2:0];
                default: mod_lut_ref = '0;
            endcase
        end
    endfunction

    task automatic compute_expected_filtered(
        input logic [CHUNK_WIDTH-1:0] cand_in,
        input logic [2:0] len_in,
        output logic [CHUNK_WIDTH-1:0] expected
    );
        begin
            logic [CHUNK_WIDTH-1:0] rs1, rs2, rs3, rs4;
            logic [CHUNK_WIDTH+3-1:0] extended_candidates;
            logic [CHUNK_WIDTH-1:0] edges;
            logic [3:0] group_mod [CHUNK_WIDTH];
            logic [2:0] group_idx [CHUNK_WIDTH];
            int prefix_sum [CHUNK_WIDTH];
            int group_count;

            rs1 = cand_in << 1;
            rs2 = cand_in << 2;
            rs3 = cand_in << 3;
            rs4 = cand_in << 4;
            extended_candidates = '0;
            expected = '0;
            group_count = 0;

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                extended_candidates[i] = cand_in[i];
                case (len_in)
                    3'd2: edges[i] = (~rs1[i] & cand_in[i]);
                    3'd3: edges[i] = (~rs1[i] & ~rs2[i] & cand_in[i]);
                    3'd4: edges[i] = (~rs1[i] & ~rs2[i] & ~rs3[i] & cand_in[i]);
                    3'd5: edges[i] = (~rs1[i] & ~rs2[i] & ~rs3[i] & ~rs4[i] & cand_in[i]);
                    default: edges[i] = 1'b0;
                endcase
                group_mod[i] = '0;
                group_idx[i] = '0;
                prefix_sum[i] = 0;
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (edges[i]) begin
                    logic [3:0] new_group_mod;
                    new_group_mod = 4'd8;
                    if (extended_candidates[i + 1]) begin
                        new_group_mod = len_in;
                    end else if (extended_candidates[i + 2]) begin
                        new_group_mod = (len_in == 3'd5) ? 4'd3 : 4'd4;
                    end else if (extended_candidates[i + 3]) begin
                        new_group_mod = 4'd2;
                    end

                    group_mod[group_count] = new_group_mod;
                    group_idx[group_count] = mod_lut_ref(i, new_group_mod);
                    group_count++;
                end
                prefix_sum[i] = group_count;
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (cand_in[i] && prefix_sum[i] != 0) begin
                    int group_i;
                    group_i = prefix_sum[i] - 1;
                    expected[i] = (mod_lut_ref(i, group_mod[group_i]) == group_idx[group_i]);
                end
            end
        end
    endtask

    task automatic run_case(
        input string label,
        input logic [CHUNK_WIDTH-1:0] cand_in,
        input logic [2:0] len_in
    );
        logic [CHUNK_WIDTH-1:0] expected;
        begin
            candidates = cand_in;
            seq_len = len_in;
            compute_expected_filtered(cand_in, len_in, expected);

            #1;
            $write("%s filtered:", label);
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                if (filtered_matches[i]) begin
                    $write(" %0d", i);
                end
            end
            $display();
            if (filtered_matches !== expected) begin
                $fatal(1, "%s mismatch: got %b expected %b", label, filtered_matches, expected);
            end
        end
    endtask

    initial begin
        logic [CHUNK_WIDTH-1:0] dense;
        logic [CHUNK_WIDTH-1:0] step2;
        logic [CHUNK_WIDTH-1:0] step3;
        int unsigned seed;

        candidates = '0;
        seq_len = '0;
        dense = '0;
        step2 = '0;
        step3 = '0;

        for (int i = 0; i < 16; i++) begin
            dense[i] = 1'b1;
        end
        for (int i = 0; i < CHUNK_WIDTH; i += 2) begin
            step2[i] = 1'b1;
        end
        for (int i = 0; i < CHUNK_WIDTH; i += 3) begin
            step3[i] = 1'b1;
        end

        run_case("len2-dense", dense, 3'd2);
        run_case("len3-dense", dense, 3'd3);
        run_case("len5-dense", dense, 3'd5);

        candidates = '0;
        candidates[20] = 1'b1;
        candidates[21] = 1'b1;
        candidates[24] = 1'b1;
        candidates[25] = 1'b1;
        candidates[28] = 1'b1;
        candidates[29] = 1'b1;
        run_case("len2-clusters", candidates, 3'd2);

        run_case("len3-step2", step2, 3'd3);
        run_case("len4-step3", step3, 3'd4);
        run_case("len5-step2", step2, 3'd5);

        seed = 32'h1bad_c0de;
        for (int case_idx = 0; case_idx < 200; case_idx++) begin
            logic [CHUNK_WIDTH-1:0] random_candidates;
            logic [2:0] random_len;
            random_candidates = '0;

            seed = seed ^ (seed << 13);
            seed = seed ^ (seed >> 17);
            seed = seed ^ (seed << 5);
            random_len = 3'd2 + seed[1:0];

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                seed = seed ^ (seed << 13);
                seed = seed ^ (seed >> 17);
                seed = seed ^ (seed << 5);
                random_candidates[i] = seed[0];
            end

            run_case($sformatf("random-%0d-len%0d", case_idx, random_len), random_candidates, random_len);
        end

        $finish;
    end
endmodule
