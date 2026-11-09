`timescale 1ps / 1ps
`default_nettype none

module tb_SeqUtilHashTable;
    import rst_pkg::*;

    agg_update_t updates_seq2 [BANKS_SEQ2];
    logic update_valid_seq2 [BANKS_SEQ2];
    agg_update_t updates_seq3 [BANKS_SEQ3];
    logic update_valid_seq3 [BANKS_SEQ3];
    agg_update_t updates_seq4 [BANKS_SEQ4];
    logic update_valid_seq4 [BANKS_SEQ4];
    agg_update_t updates_seq5 [BANKS_SEQ5];
    logic update_valid_seq5 [BANKS_SEQ5];
    logic clk;
    logic rst;
    logic query_top;
    top_candidate_t top_result;
    logic top_valid;
    int unsigned seed;

    ht_entry_t model_seq2 [BANKS_SEQ2][SETS_PER_BANK][WAYS];
    ht_entry_t model_seq3 [BANKS_SEQ3][SETS_PER_BANK][WAYS];
    ht_entry_t model_seq4 [BANKS_SEQ4][SETS_PER_BANK][WAYS];
    ht_entry_t model_seq5 [BANKS_SEQ5][SETS_PER_BANK][WAYS];

    HashTableTop dut (
        .clk(clk),
        .rst(rst),
        .updates_seq2(updates_seq2),
        .update_valid_seq2(update_valid_seq2),
        .updates_seq3(updates_seq3),
        .update_valid_seq3(update_valid_seq3),
        .updates_seq4(updates_seq4),
        .update_valid_seq4(update_valid_seq4),
        .updates_seq5(updates_seq5),
        .update_valid_seq5(update_valid_seq5),
        .query_top(query_top),
        .top_result(top_result),
        .top_valid(top_valid)
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

    function automatic seq_t make_seq4(input int s0, input int s1, input int s2, input int s3);
        seq_t seq;
        begin
            seq = '0;
            seq[0] = symbol_t'(s0);
            seq[1] = symbol_t'(s1);
            seq[2] = symbol_t'(s2);
            seq[3] = symbol_t'(s3);
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

    function automatic logic better_candidate_ref(
        input top_candidate_t lhs,
        input top_candidate_t rhs
    );
        logic signed [COUNT_BITS+7:0] lhs_num;
        logic signed [COUNT_BITS+7:0] rhs_num;
        logic [7:0] lhs_den;
        logic [7:0] rhs_den;
        logic signed [COUNT_BITS+16:0] lhs_score;
        logic signed [COUNT_BITS+16:0] rhs_score;
        begin
            if (lhs.valid != rhs.valid) begin
                return lhs.valid && !rhs.valid;
            end
            if (!lhs.valid && !rhs.valid) begin
                return 1'b0;
            end
            lhs_num = utility_numerator(lhs.seq_len, lhs.count);
            rhs_num = utility_numerator(rhs.seq_len, rhs.count);
            lhs_den = utility_denominator(lhs.seq_len);
            rhs_den = utility_denominator(rhs.seq_len);
            lhs_score = $signed(lhs_num) * $signed({1'b0, rhs_den});
            rhs_score = $signed(rhs_num) * $signed({1'b0, lhs_den});
            return lhs_score > rhs_score;
        end
    endfunction

    task automatic clear_inputs;
        begin
            query_top = 1'b0;
            for (int i = 0; i < BANKS_SEQ2; i++) begin
                updates_seq2[i] = '0;
                update_valid_seq2[i] = 1'b0;
            end
            for (int i = 0; i < BANKS_SEQ3; i++) begin
                updates_seq3[i] = '0;
                update_valid_seq3[i] = 1'b0;
            end
            for (int i = 0; i < BANKS_SEQ4; i++) begin
                updates_seq4[i] = '0;
                update_valid_seq4[i] = 1'b0;
            end
            for (int i = 0; i < BANKS_SEQ5; i++) begin
                updates_seq5[i] = '0;
                update_valid_seq5[i] = 1'b0;
            end
        end
    endtask

    task automatic clear_model;
        begin
            for (int bank = 0; bank < BANKS_SEQ2; bank++) begin
                for (int set_idx = 0; set_idx < SETS_PER_BANK; set_idx++) begin
                    for (int way = 0; way < WAYS; way++) begin
                        model_seq2[bank][set_idx][way] = '0;
                    end
                end
            end
            for (int bank = 0; bank < BANKS_SEQ3; bank++) begin
                for (int set_idx = 0; set_idx < SETS_PER_BANK; set_idx++) begin
                    for (int way = 0; way < WAYS; way++) begin
                        model_seq3[bank][set_idx][way] = '0;
                    end
                end
            end
            for (int bank = 0; bank < BANKS_SEQ4; bank++) begin
                for (int set_idx = 0; set_idx < SETS_PER_BANK; set_idx++) begin
                    for (int way = 0; way < WAYS; way++) begin
                        model_seq4[bank][set_idx][way] = '0;
                    end
                end
            end
            for (int bank = 0; bank < BANKS_SEQ5; bank++) begin
                for (int set_idx = 0; set_idx < SETS_PER_BANK; set_idx++) begin
                    for (int way = 0; way < WAYS; way++) begin
                        model_seq5[bank][set_idx][way] = '0;
                    end
                end
            end
        end
    endtask

    task automatic seed_update(
        output agg_update_t update,
        input int bank_idx,
        input int set_idx,
        input seq_t seq,
        input int count
    );
        begin
            update = '0;
            update.valid = 1'b1;
            update.bank_idx = bank_idx[$bits(update.bank_idx)-1:0];
            update.set_idx = set_idx[$bits(update.set_idx)-1:0];
            update.seq = seq;
            update.count = count;
        end
    endtask

    task automatic random_seq(
        input int used_len,
        inout int unsigned state,
        output seq_t seq
    );
        begin
            seq = '0;
            for (int idx = 0; idx < used_len; idx++) begin
                state = next_rand(state);
                seq[idx] = symbol_t'(state[3:0]);
            end
        end
    endtask

    task automatic model_apply_update(
        ref ht_entry_t entries_ref [SETS_PER_BANK][WAYS],
        input logic fire,
        input agg_update_t update
    );
        int match_idx;
        int free_idx;
        int min_idx;
        logic signed [COUNT_BITS-1:0] min_count;
        logic signed [COUNT_BITS-1:0] next_count;

        begin
            if (!fire || !update.valid) begin
                return;
            end

            match_idx = -1;
            free_idx = -1;
            min_idx = 0;
            min_count = entries_ref[update.set_idx][0].count;

            for (int way = 0; way < WAYS; way++) begin
                if (entries_ref[update.set_idx][way].valid &&
                    entries_ref[update.set_idx][way].seq == update.seq) begin
                    match_idx = way;
                end
                if (!entries_ref[update.set_idx][way].valid && free_idx == -1) begin
                    free_idx = way;
                end
                if (!entries_ref[update.set_idx][way].valid) begin
                    min_idx = way;
                    min_count = '0;
                end else if (entries_ref[update.set_idx][way].count < min_count) begin
                    min_idx = way;
                    min_count = entries_ref[update.set_idx][way].count;
                end
            end

            if (match_idx != -1) begin
                next_count = entries_ref[update.set_idx][match_idx].count + update.count;
                entries_ref[update.set_idx][match_idx].count = next_count;
                entries_ref[update.set_idx][match_idx].valid = (next_count > 0);
            end else if (update.count > 0) begin
                int insert_idx;
                insert_idx = (free_idx != -1) ? free_idx : min_idx;
                entries_ref[update.set_idx][insert_idx].seq = update.seq;
                entries_ref[update.set_idx][insert_idx].count = update.count;
                entries_ref[update.set_idx][insert_idx].valid = 1'b1;
            end
        end
    endtask

    task automatic model_apply_all_updates;
        begin
            for (int bank = 0; bank < BANKS_SEQ2; bank++) begin
                model_apply_update(model_seq2[bank], update_valid_seq2[bank], updates_seq2[bank]);
            end
            for (int bank = 0; bank < BANKS_SEQ3; bank++) begin
                model_apply_update(model_seq3[bank], update_valid_seq3[bank], updates_seq3[bank]);
            end
            for (int bank = 0; bank < BANKS_SEQ4; bank++) begin
                model_apply_update(model_seq4[bank], update_valid_seq4[bank], updates_seq4[bank]);
            end
            for (int bank = 0; bank < BANKS_SEQ5; bank++) begin
                model_apply_update(model_seq5[bank], update_valid_seq5[bank], updates_seq5[bank]);
            end
        end
    endtask

    task automatic model_bank_top(
        input ht_entry_t entries_ref [SETS_PER_BANK][WAYS],
        output ht_entry_t top
    );
        begin
            top = '0;
            for (int set_idx = 0; set_idx < SETS_PER_BANK; set_idx++) begin
                for (int way = 0; way < WAYS; way++) begin
                    if (entries_ref[set_idx][way].valid &&
                        (!top.valid || entries_ref[set_idx][way].count > top.count)) begin
                        top = entries_ref[set_idx][way];
                    end
                end
            end
        end
    endtask

    task automatic model_subtable_top_seq2(output top_candidate_t candidate);
        ht_entry_t bank_top;
        begin
            candidate = '0;
            candidate.seq_len = 3'd2;
            for (int bank = 0; bank < BANKS_SEQ2; bank++) begin
                model_bank_top(model_seq2[bank], bank_top);
                if (bank_top.valid && (!candidate.valid || bank_top.count > candidate.count)) begin
                    candidate.seq = bank_top.seq;
                    candidate.seq_len = 3'd2;
                    candidate.count = bank_top.count;
                    candidate.valid = 1'b1;
                end
            end
        end
    endtask

    task automatic model_subtable_top_seq3(output top_candidate_t candidate);
        ht_entry_t bank_top;
        begin
            candidate = '0;
            candidate.seq_len = 3'd3;
            for (int bank = 0; bank < BANKS_SEQ3; bank++) begin
                model_bank_top(model_seq3[bank], bank_top);
                if (bank_top.valid && (!candidate.valid || bank_top.count > candidate.count)) begin
                    candidate.seq = bank_top.seq;
                    candidate.seq_len = 3'd3;
                    candidate.count = bank_top.count;
                    candidate.valid = 1'b1;
                end
            end
        end
    endtask

    task automatic model_subtable_top_seq4(output top_candidate_t candidate);
        ht_entry_t bank_top;
        begin
            candidate = '0;
            candidate.seq_len = 3'd4;
            for (int bank = 0; bank < BANKS_SEQ4; bank++) begin
                model_bank_top(model_seq4[bank], bank_top);
                if (bank_top.valid && (!candidate.valid || bank_top.count > candidate.count)) begin
                    candidate.seq = bank_top.seq;
                    candidate.seq_len = 3'd4;
                    candidate.count = bank_top.count;
                    candidate.valid = 1'b1;
                end
            end
        end
    endtask

    task automatic model_subtable_top_seq5(output top_candidate_t candidate);
        ht_entry_t bank_top;
        begin
            candidate = '0;
            candidate.seq_len = 3'd5;
            for (int bank = 0; bank < BANKS_SEQ5; bank++) begin
                model_bank_top(model_seq5[bank], bank_top);
                if (bank_top.valid && (!candidate.valid || bank_top.count > candidate.count)) begin
                    candidate.seq = bank_top.seq;
                    candidate.seq_len = 3'd5;
                    candidate.count = bank_top.count;
                    candidate.valid = 1'b1;
                end
            end
        end
    endtask

    task automatic compute_model_top(
        output top_candidate_t expected,
        output logic expected_valid
    );
        top_candidate_t candidates_ref [4];

        begin
            model_subtable_top_seq2(candidates_ref[0]);
            model_subtable_top_seq3(candidates_ref[1]);
            model_subtable_top_seq4(candidates_ref[2]);
            model_subtable_top_seq5(candidates_ref[3]);

            expected = '0;
            for (int idx = 0; idx < 4; idx++) begin
                if (better_candidate_ref(candidates_ref[idx], expected)) begin
                    expected = candidates_ref[idx];
                end
            end
            expected_valid = expected.valid;
        end
    endtask

    task automatic step_updates_and_check(input string label);
        begin
            @(posedge clk);
            #1;
            model_apply_all_updates();
            clear_inputs();
            @(posedge clk);
            #1;
            query_and_check({label, "-query"});
        end
    endtask

    task automatic query_and_check(input string label);
        top_candidate_t expected;
        logic expected_valid;

        begin
            compute_model_top(expected, expected_valid);
            query_top = 1'b1;
            @(posedge clk);
            #1;
            query_top = 1'b0;
            if (top_valid !== 1'b0) begin
                $fatal(1, "%s top_valid asserted too early", label);
            end
            @(posedge clk);
            #1;
            if (top_valid !== 1'b0) begin
                $fatal(1, "%s top_valid asserted too early during score stage", label);
            end
            @(posedge clk);
            #1;
            if ((top_valid !== expected_valid) || (top_result !== expected)) begin
                $fatal(1, "%s query mismatch: got valid=%0b len=%0d count=%0d expected valid=%0b len=%0d count=%0d",
                    label, top_valid, top_result.seq_len, top_result.count,
                    expected_valid, expected.seq_len, expected.count);
            end
        end
    endtask

    task automatic reset_dut;
        begin
            clear_inputs();
            clear_model();
            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
            #1;
            if (top_valid !== 1'b0) begin
                $fatal(1, "top_valid should reset low");
            end
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        seq_t seq3_a;
        seq_t seq4_a;
        seq_t seq4_b;
        seq_t seq4_c;
        seq_t seq5_top;
        seq_t seq2_top;
        int seq2_bank_a;
        int seq3_bank_a;
        int seq4_bank_a;
        int seq5_bank_a;
        int set_a;
        int set_b;

        clk = 1'b0;
        seed = 32'h6e75_1eed;
        reset_dut();

        seq2_bank_a = (BANKS_SEQ2 > 1) ? 1 : 0;
        seq3_bank_a = (BANKS_SEQ3 > 1) ? 1 : 0;
        seq4_bank_a = (BANKS_SEQ4 > 1) ? 1 : 0;
        seq5_bank_a = (BANKS_SEQ5 > 1) ? 1 : 0;
        set_a = 0;
        set_b = (SETS_PER_BANK > 1) ? 1 : 0;

        seq3_a = make_seq3(11, 12, 13);
        seq4_a = make_seq4(41, 42, 43, 44);
        seq4_b = make_seq4(51, 52, 53, 54);
        seq4_c = make_seq4(61, 62, 63, 64);
        seq5_top = make_seq5(91, 92, 93, 94, 95);
        seq2_top = make_seq2(101, 102);

        seed_update(updates_seq3[seq3_bank_a], seq3_bank_a, set_a, seq3_a, 4);
        update_valid_seq3[seq3_bank_a] = 1'b1;
        step_updates_and_check("seq3-add4");

        seed_update(updates_seq3[seq3_bank_a], seq3_bank_a, set_a, seq3_a, 3);
        update_valid_seq3[seq3_bank_a] = 1'b1;
        step_updates_and_check("seq3-add3");

        seed_update(updates_seq3[seq3_bank_a], seq3_bank_a, set_a, seq3_a, -7);
        update_valid_seq3[seq3_bank_a] = 1'b1;
        step_updates_and_check("seq3-back-to-zero");

        seed_update(updates_seq4[seq4_bank_a], seq4_bank_a, set_b, seq4_a, 2);
        update_valid_seq4[seq4_bank_a] = 1'b1;
        step_updates_and_check("seq4-fill-a");

        seed_update(updates_seq4[seq4_bank_a], seq4_bank_a, set_b, seq4_b, 2);
        update_valid_seq4[seq4_bank_a] = 1'b1;
        step_updates_and_check("seq4-fill-b");

        seed_update(updates_seq4[seq4_bank_a], seq4_bank_a, set_b, seq4_c, 1);
        update_valid_seq4[seq4_bank_a] = 1'b1;
        step_updates_and_check("seq4-evict-min");

        seed_update(updates_seq5[seq5_bank_a], seq5_bank_a, set_a, seq5_top, 3);
        update_valid_seq5[seq5_bank_a] = 1'b1;
        step_updates_and_check("seq5-seed");

        seed_update(updates_seq2[seq2_bank_a], seq2_bank_a, set_b, seq2_top, 5);
        update_valid_seq2[seq2_bank_a] = 1'b1;
        step_updates_and_check("seq2-seed");

        query_and_check("utility-prefers-seq5");
        if (!top_valid || top_result.seq_len !== 3'd5 || top_result.count !== 3 || top_result.seq !== seq5_top) begin
            $fatal(1, "expected seq5 candidate to win initial utility check");
        end

        seed_update(updates_seq2[seq2_bank_a], seq2_bank_a, set_b, seq2_top, 1);
        update_valid_seq2[seq2_bank_a] = 1'b1;
        step_updates_and_check("seq2-bump");

        query_and_check("utility-swings-to-seq2");
        if (!top_valid || top_result.seq_len !== 3'd2 || top_result.count !== 6 || top_result.seq !== seq2_top) begin
            $fatal(1, "expected seq2 candidate to win after bump");
        end

        for (int case_idx = 0; case_idx < 200; case_idx++) begin
            clear_inputs();

            for (int bank = 0; bank < BANKS_SEQ2; bank++) begin
                seq_t seq_rand;
                int signed count_rand;
                seed = next_rand(seed);
                if (seed[0]) begin
                    random_seq(2, seed, seq_rand);
                    count_rand = $signed({1'b0, seed[3:1]}) - 3;
                    if (count_rand >= 0) begin
                        count_rand = count_rand + 1;
                    end
                    seed_update(updates_seq2[bank], bank, seed % SETS_PER_BANK, seq_rand, count_rand);
                    update_valid_seq2[bank] = 1'b1;
                end
            end

            for (int bank = 0; bank < BANKS_SEQ3; bank++) begin
                seq_t seq_rand;
                int signed count_rand;
                seed = next_rand(seed);
                if (seed[0]) begin
                    random_seq(3, seed, seq_rand);
                    count_rand = $signed({1'b0, seed[3:1]}) - 3;
                    if (count_rand >= 0) begin
                        count_rand = count_rand + 1;
                    end
                    seed_update(updates_seq3[bank], bank, seed % SETS_PER_BANK, seq_rand, count_rand);
                    update_valid_seq3[bank] = 1'b1;
                end
            end

            for (int bank = 0; bank < BANKS_SEQ4; bank++) begin
                seq_t seq_rand;
                int signed count_rand;
                seed = next_rand(seed);
                if (seed[0]) begin
                    random_seq(4, seed, seq_rand);
                    count_rand = $signed({1'b0, seed[3:1]}) - 3;
                    if (count_rand >= 0) begin
                        count_rand = count_rand + 1;
                    end
                    seed_update(updates_seq4[bank], bank, seed % SETS_PER_BANK, seq_rand, count_rand);
                    update_valid_seq4[bank] = 1'b1;
                end
            end

            for (int bank = 0; bank < BANKS_SEQ5; bank++) begin
                seq_t seq_rand;
                int signed count_rand;
                seed = next_rand(seed);
                if (seed[0]) begin
                    random_seq(5, seed, seq_rand);
                    count_rand = $signed({1'b0, seed[3:1]}) - 3;
                    if (count_rand >= 0) begin
                        count_rand = count_rand + 1;
                    end
                    seed_update(updates_seq5[bank], bank, seed % SETS_PER_BANK, seq_rand, count_rand);
                    update_valid_seq5[bank] = 1'b1;
                end
            end

            step_updates_and_check($sformatf("random-update-%0d", case_idx));

            if ((case_idx % 4) == 0) begin
                query_and_check($sformatf("random-query-%0d", case_idx));
            end
        end

        query_and_check("final-query");
        $finish;
    end
endmodule
