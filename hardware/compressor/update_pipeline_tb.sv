`timescale 1ps / 1ps
`default_nettype none

module tb_UpdatePipelineN;
    import rst_pkg::*;

    localparam int W2 = PIPE_WIDTH_SEQ2;
    localparam int W5 = PIPE_WIDTH_SEQ5;
    localparam int B2 = BANKS_SEQ2;
    localparam int B5 = BANKS_SEQ5;
    localparam int MAX_EXPECTED_SEQ2 = W2 * 4;
    localparam int MAX_EXPECTED_SEQ5 = W5 * 2;

    logic clk;
    logic rst;

    seq_update_t i_updates_seq2 [W2];
    logic i_valid_seq2;
    logic i_busy_seq2;
    logic all_fifos_empty_seq2;
    agg_update_t ht_updates_seq2 [B2];
    logic ht_valid_seq2 [B2];

    seq_update_t i_updates_seq5 [W5];
    logic i_valid_seq5;
    logic i_busy_seq5;
    logic all_fifos_empty_seq5;
    agg_update_t ht_updates_seq5 [B5];
    logic ht_valid_seq5 [B5];

    agg_update_t expected_seq2 [B2][MAX_EXPECTED_SEQ2];
    int expected_seq2_counts [B2];
    int seen_seq2_counts [B2];

    agg_update_t expected_seq5 [B5][MAX_EXPECTED_SEQ5];
    int expected_seq5_counts [B5];
    int seen_seq5_counts [B5];

    UpdatePipelineN #(
        .PIPE_WIDTH(W2),
        .NUM_BANKS(B2),
        .FIFO_DEPTH_P(2)
    ) dut_seq2 (
        .clk(clk),
        .rst(rst),
        .i_updates(i_updates_seq2),
        .i_valid(i_valid_seq2),
        .i_busy(i_busy_seq2),
        .all_fifos_empty(all_fifos_empty_seq2),
        .ht_updates(ht_updates_seq2),
        .ht_update_valid(ht_valid_seq2)
    );

    UpdatePipelineN #(
        .PIPE_WIDTH(W5),
        .NUM_BANKS(B5),
        .FIFO_DEPTH_P(4)
    ) dut_seq5 (
        .clk(clk),
        .rst(rst),
        .i_updates(i_updates_seq5),
        .i_valid(i_valid_seq5),
        .i_busy(i_busy_seq5),
        .all_fifos_empty(all_fifos_empty_seq5),
        .ht_updates(ht_updates_seq5),
        .ht_update_valid(ht_valid_seq5)
    );

    function automatic seq_t make_seq2(input int s0, input int s1);
        seq_t seq;
        begin
            seq = '0;
            seq[0] = symbol_t'(s0);
            seq[1] = symbol_t'(s1);
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

    function automatic logic [15:0] crc(input logic [42:0] data);
        logic [15:0] hash_value;
        begin
            hash_value[0]  = data[0]  ^ data[4]  ^ data[8]  ^ data[11] ^ data[12] ^ data[19] ^ data[20] ^ data[22] ^ data[26] ^ data[27] ^ data[28] ^ data[32] ^ data[33] ^ data[35] ^ data[42];
            hash_value[1]  = data[1]  ^ data[5]  ^ data[9]  ^ data[12] ^ data[13] ^ data[20] ^ data[21] ^ data[23] ^ data[27] ^ data[28] ^ data[29] ^ data[33] ^ data[34] ^ data[36];
            hash_value[2]  = data[2]  ^ data[6]  ^ data[10] ^ data[13] ^ data[14] ^ data[21] ^ data[22] ^ data[24] ^ data[28] ^ data[29] ^ data[30] ^ data[34] ^ data[35] ^ data[37];
            hash_value[3]  = data[3]  ^ data[7]  ^ data[11] ^ data[14] ^ data[15] ^ data[22] ^ data[23] ^ data[25] ^ data[29] ^ data[30] ^ data[31] ^ data[35] ^ data[36] ^ data[38];
            hash_value[4]  = data[4]  ^ data[8]  ^ data[12] ^ data[15] ^ data[16] ^ data[23] ^ data[24] ^ data[26] ^ data[30] ^ data[31] ^ data[32] ^ data[36] ^ data[37] ^ data[39];
            hash_value[5]  = data[0]  ^ data[4]  ^ data[5]  ^ data[8]  ^ data[9]  ^ data[11] ^ data[12] ^ data[13] ^ data[16] ^ data[17] ^ data[19] ^ data[20] ^ data[22] ^ data[24] ^ data[25] ^ data[26] ^ data[28] ^ data[31] ^ data[35] ^ data[37] ^ data[38] ^ data[40] ^ data[42];
            hash_value[6]  = data[1]  ^ data[5]  ^ data[6]  ^ data[9]  ^ data[10] ^ data[12] ^ data[13] ^ data[14] ^ data[17] ^ data[18] ^ data[20] ^ data[21] ^ data[23] ^ data[25] ^ data[26] ^ data[27] ^ data[29] ^ data[32] ^ data[36] ^ data[38] ^ data[39] ^ data[41];
            hash_value[7]  = data[2]  ^ data[6]  ^ data[7]  ^ data[10] ^ data[11] ^ data[13] ^ data[14] ^ data[15] ^ data[18] ^ data[19] ^ data[21] ^ data[22] ^ data[24] ^ data[26] ^ data[27] ^ data[28] ^ data[30] ^ data[33] ^ data[37] ^ data[39] ^ data[40] ^ data[42];
            hash_value[8]  = data[3]  ^ data[7]  ^ data[8]  ^ data[11] ^ data[12] ^ data[14] ^ data[15] ^ data[16] ^ data[19] ^ data[20] ^ data[22] ^ data[23] ^ data[25] ^ data[27] ^ data[28] ^ data[29] ^ data[31] ^ data[34] ^ data[38] ^ data[40] ^ data[41];
            hash_value[9]  = data[4]  ^ data[8]  ^ data[9]  ^ data[12] ^ data[13] ^ data[15] ^ data[16] ^ data[17] ^ data[20] ^ data[21] ^ data[23] ^ data[24] ^ data[26] ^ data[28] ^ data[29] ^ data[30] ^ data[32] ^ data[35] ^ data[39] ^ data[41] ^ data[42];
            hash_value[10] = data[5]  ^ data[9]  ^ data[10] ^ data[13] ^ data[14] ^ data[16] ^ data[17] ^ data[18] ^ data[21] ^ data[22] ^ data[24] ^ data[25] ^ data[27] ^ data[29] ^ data[30] ^ data[31] ^ data[33] ^ data[36] ^ data[40] ^ data[42];
            hash_value[11] = data[6]  ^ data[10] ^ data[11] ^ data[14] ^ data[15] ^ data[17] ^ data[18] ^ data[19] ^ data[22] ^ data[23] ^ data[25] ^ data[26] ^ data[28] ^ data[30] ^ data[31] ^ data[32] ^ data[34] ^ data[37] ^ data[41];
            hash_value[12] = data[0]  ^ data[4]  ^ data[7]  ^ data[8]  ^ data[15] ^ data[16] ^ data[18] ^ data[22] ^ data[23] ^ data[24] ^ data[28] ^ data[29] ^ data[31] ^ data[38];
            hash_value[13] = data[1]  ^ data[5]  ^ data[8]  ^ data[9]  ^ data[16] ^ data[17] ^ data[19] ^ data[23] ^ data[24] ^ data[25] ^ data[29] ^ data[30] ^ data[32] ^ data[39];
            hash_value[14] = data[2]  ^ data[6]  ^ data[9]  ^ data[10] ^ data[17] ^ data[18] ^ data[20] ^ data[24] ^ data[25] ^ data[26] ^ data[30] ^ data[31] ^ data[33] ^ data[40];
            hash_value[15] = data[3]  ^ data[7]  ^ data[10] ^ data[11] ^ data[18] ^ data[19] ^ data[21] ^ data[25] ^ data[26] ^ data[27] ^ data[31] ^ data[32] ^ data[34] ^ data[41];
            return hash_value;
        end
    endfunction

    function automatic logic [42:0] seq_payload(
        input seq_t seq,
        input int pipe_width
    );
        logic [42:0] payload;
        begin
            payload = {
                seq[4][7:0],
                seq[3][7:0],
                seq[2][7:0],
                seq[1][7:0],
                seq[0][7:0],
                seq_len_from_pipe_width(pipe_width)
            };
            return payload;
        end
    endfunction

    function automatic hashed_update_t hash_update_ref(
        input seq_update_t update,
        input int pipe_width,
        input int num_banks
    );
        hashed_update_t hashed;
        logic [15:0] hash_value;
        begin
            hashed = '0;
            if (update.valid) begin
                hash_value = crc(seq_payload(update.seq, pipe_width));
                hashed.bank_idx = hash_value % num_banks;
                hashed.set_idx = (hash_value / num_banks) % SETS_PER_BANK;
                hashed.seq = update.seq;
                hashed.inc = update.inc;
                hashed.valid = 1'b1;
            end
            return hashed;
        end
    endfunction

    function automatic logic comes_before(
        input hashed_update_t lhs,
        input hashed_update_t rhs
    );
        begin
            if (lhs.valid != rhs.valid) begin
                return lhs.valid && !rhs.valid;
            end
            if (!lhs.valid && !rhs.valid) begin
                return 1'b0;
            end
            if (lhs.bank_idx != rhs.bank_idx) begin
                return lhs.bank_idx < rhs.bank_idx;
            end
            if (lhs.seq != rhs.seq) begin
                return lhs.seq < rhs.seq;
            end
            if (lhs.inc != rhs.inc) begin
                return lhs.inc < rhs.inc;
            end
            return 1'b0;
        end
    endfunction

    function automatic logic same_group_key(
        input hashed_update_t lhs,
        input hashed_update_t rhs
    );
        begin
            return lhs.valid && rhs.valid &&
                (lhs.bank_idx == rhs.bank_idx) &&
                (lhs.set_idx == rhs.set_idx) &&
                (lhs.seq == rhs.seq) &&
                (lhs.inc == rhs.inc);
        end
    endfunction

    task automatic clear_seq2_inputs;
        begin
            i_valid_seq2 = 1'b0;
            for (int i = 0; i < W2; i++) begin
                i_updates_seq2[i] = '0;
            end
        end
    endtask

    task automatic clear_seq5_inputs;
        begin
            i_valid_seq5 = 1'b0;
            for (int i = 0; i < W5; i++) begin
                i_updates_seq5[i] = '0;
            end
        end
    endtask

    task automatic clear_expected_seq2;
        begin
            for (int bank = 0; bank < B2; bank++) begin
                expected_seq2_counts[bank] = 0;
                seen_seq2_counts[bank] = 0;
                for (int idx = 0; idx < MAX_EXPECTED_SEQ2; idx++) begin
                    expected_seq2[bank][idx] = '0;
                end
            end
        end
    endtask

    task automatic clear_expected_seq5;
        begin
            for (int bank = 0; bank < B5; bank++) begin
                expected_seq5_counts[bank] = 0;
                seen_seq5_counts[bank] = 0;
                for (int idx = 0; idx < MAX_EXPECTED_SEQ5; idx++) begin
                    expected_seq5[bank][idx] = '0;
                end
            end
        end
    endtask

    task automatic seed_update(
        output seq_update_t update,
        input seq_t seq,
        input logic inc
    );
        begin
            update = '0;
            update.valid = 1'b1;
            update.inc = inc;
            update.seq = seq;
        end
    endtask

    task automatic build_same_bank_seq2_burst(
        output seq_update_t batch [W2],
        input int target_bank
    );
        hashed_update_t hashed;
        seq_update_t candidate;
        int found_count;
        bit duplicate;
        begin
            for (int i = 0; i < W2; i++) begin
                batch[i] = '0;
            end

            found_count = 0;
            for (int s0 = 0; (s0 < 256) && (found_count < W2); s0++) begin
                for (int s1 = 0; (s1 < 256) && (found_count < W2); s1++) begin
                    seed_update(candidate, make_seq2(s0, s1), 1'b1);
                    hashed = hash_update_ref(candidate, W2, B2);
                    duplicate = 1'b0;

                    if (hashed.valid && (hashed.bank_idx == target_bank)) begin
                        for (int prev = 0; prev < found_count; prev++) begin
                            if (batch[prev].seq == candidate.seq) begin
                                duplicate = 1'b1;
                            end
                        end

                        if (!duplicate) begin
                            batch[found_count] = candidate;
                            found_count++;
                        end
                    end
                end
            end

            if (found_count != W2) begin
                $fatal(1, "failed to build a %0d-entry same-bank seq2 burst for bank %0d", W2, target_bank);
            end
        end
    endtask

    task automatic append_expected_seq2_push(input seq_update_t batch [W2]);
        hashed_update_t sorted [W2];
        agg_update_t grouped [W2];
        hashed_update_t tmp;
        int grouped_count;
        int bank_idx;
        int j;
        begin
            for (int i = 0; i < W2; i++) begin
                sorted[i] = hash_update_ref(batch[i], W2, B2);
                grouped[i] = '0;
            end
            for (int i = 0; i < W2; i++) begin
                for (int k = i + 1; k < W2; k++) begin
                    if (comes_before(sorted[k], sorted[i])) begin
                        tmp = sorted[i];
                        sorted[i] = sorted[k];
                        sorted[k] = tmp;
                    end
                end
            end

            grouped_count = 0;
            for (int i = 0; i < W2; ) begin
                if (!sorted[i].valid) begin
                    i++;
                end else begin
                    grouped[grouped_count] = '0;
                    grouped[grouped_count].bank_idx = sorted[i].bank_idx;
                    grouped[grouped_count].set_idx = sorted[i].set_idx;
                    grouped[grouped_count].seq = sorted[i].seq;
                    grouped[grouped_count].count = sorted[i].inc ? 1 : -1;
                    grouped[grouped_count].valid = 1'b1;

                    j = i + 1;
                    while ((j < W2) && same_group_key(sorted[i], sorted[j])) begin
                        grouped[grouped_count].count += sorted[j].inc ? 1 : -1;
                        j++;
                    end

                    bank_idx = grouped[grouped_count].bank_idx;
                    expected_seq2[bank_idx][expected_seq2_counts[bank_idx]] = grouped[grouped_count];
                    expected_seq2_counts[bank_idx]++;
                    grouped_count++;
                    i = j;
                end
            end
        end
    endtask

    task automatic append_expected_seq5_push(input seq_update_t batch [W5]);
        hashed_update_t sorted [W5];
        agg_update_t grouped [W5];
        hashed_update_t tmp;
        int grouped_count;
        int bank_idx;
        int j;
        begin
            for (int i = 0; i < W5; i++) begin
                sorted[i] = hash_update_ref(batch[i], W5, B5);
                grouped[i] = '0;
            end
            for (int i = 0; i < W5; i++) begin
                for (int k = i + 1; k < W5; k++) begin
                    if (comes_before(sorted[k], sorted[i])) begin
                        tmp = sorted[i];
                        sorted[i] = sorted[k];
                        sorted[k] = tmp;
                    end
                end
            end

            grouped_count = 0;
            for (int i = 0; i < W5; ) begin
                if (!sorted[i].valid) begin
                    i++;
                end else begin
                    grouped[grouped_count] = '0;
                    grouped[grouped_count].bank_idx = sorted[i].bank_idx;
                    grouped[grouped_count].set_idx = sorted[i].set_idx;
                    grouped[grouped_count].seq = sorted[i].seq;
                    grouped[grouped_count].count = sorted[i].inc ? 1 : -1;
                    grouped[grouped_count].valid = 1'b1;

                    j = i + 1;
                    while ((j < W5) && same_group_key(sorted[i], sorted[j])) begin
                        grouped[grouped_count].count += sorted[j].inc ? 1 : -1;
                        j++;
                    end

                    bank_idx = grouped[grouped_count].bank_idx;
                    expected_seq5[bank_idx][expected_seq5_counts[bank_idx]] = grouped[grouped_count];
                    expected_seq5_counts[bank_idx]++;
                    grouped_count++;
                    i = j;
                end
            end
        end
    endtask

    task automatic observe_seq2_step;
        begin
            for (int bank = 0; bank < B2; bank++) begin
                if (ht_updates_seq2[bank].valid) begin
                    if (seen_seq2_counts[bank] >= expected_seq2_counts[bank]) begin
                        $fatal(1, "unexpected seq2 output on bank %0d", bank);
                    end
                    if (ht_updates_seq2[bank] !== expected_seq2[bank][seen_seq2_counts[bank]]) begin
                        $fatal(1, "seq2 output mismatch on bank %0d item %0d",
                            bank, seen_seq2_counts[bank]);
                    end
                    seen_seq2_counts[bank]++;
                end
            end
        end
    endtask

    task automatic observe_seq5_step;
        begin
            for (int bank = 0; bank < B5; bank++) begin
                if (ht_updates_seq5[bank].valid) begin
                    if (seen_seq5_counts[bank] >= expected_seq5_counts[bank]) begin
                        $fatal(1, "unexpected seq5 output on bank %0d", bank);
                    end
                    if (ht_updates_seq5[bank] !== expected_seq5[bank][seen_seq5_counts[bank]]) begin
                        $fatal(1, "seq5 output mismatch on bank %0d item %0d",
                            bank, seen_seq5_counts[bank]);
                    end
                    seen_seq5_counts[bank]++;
                end
            end
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        bit finished;
        bit saw_backpressure;

        clk = 1'b0;

        rst = 1'b1;
        clear_seq2_inputs();
        clear_seq5_inputs();
        clear_expected_seq2();
        clear_expected_seq5();
        @(posedge clk);
        #1;
        rst = 1'b0;

        seed_update(i_updates_seq2[0], make_seq2(1, 2), 1'b1);
        seed_update(i_updates_seq2[1], make_seq2(1, 2), 1'b1);
        seed_update(i_updates_seq2[2], make_seq2(5, 8), 1'b0);
        seed_update(i_updates_seq2[3], make_seq2(7, 9), 1'b1);
        seed_update(i_updates_seq2[4], make_seq2(11, 13), 1'b0);
        append_expected_seq2_push(i_updates_seq2);
        i_valid_seq2 = 1'b1;
        #1;
        if (i_busy_seq2) begin
            $fatal(1, "seq2 pipeline should accept the first grouped burst");
        end
        @(posedge clk);
        #1;
        observe_seq2_step();
        clear_seq2_inputs();
        finished = 1'b0;
        for (int cycle = 0; cycle < 16; cycle++) begin
            @(posedge clk);
            #1;
            observe_seq2_step();
            finished = all_fifos_empty_seq2;
            for (int bank = 0; bank < B2; bank++) begin
                finished &= (seen_seq2_counts[bank] == expected_seq2_counts[bank]);
            end
            if (finished) begin
                break;
            end
        end
        if (!finished) begin
            $fatal(1, "timed out draining seq2 pipeline");
        end

        rst = 1'b1;
        clear_seq2_inputs();
        clear_seq5_inputs();
        clear_expected_seq2();
        clear_expected_seq5();
        @(posedge clk);
        #1;
        rst = 1'b0;

        seed_update(i_updates_seq2[0], make_seq2(0, 12), 1'b1);
        seed_update(i_updates_seq2[1], make_seq2(0, 12), 1'b1);
        seed_update(i_updates_seq2[2], make_seq2(0, 15), 1'b0);
        seed_update(i_updates_seq2[3], make_seq2(0, 15), 1'b0);
        append_expected_seq2_push(i_updates_seq2);
        append_expected_seq2_push(i_updates_seq2);
        i_valid_seq2 = 1'b1;
        saw_backpressure = 1'b0;
        for (int cycle = 0; cycle < 4; cycle++) begin
            #1;
            saw_backpressure |= i_busy_seq2;
            @(posedge clk);
            #1;
            observe_seq2_step();
        end
        clear_seq2_inputs();
        if (!saw_backpressure) begin
            $fatal(1, "seq2 repeated burst should assert backpressure while draining staged work");
        end
        finished = 1'b0;
        for (int cycle = 0; cycle < 16; cycle++) begin
            @(posedge clk);
            #1;
            observe_seq2_step();
            finished = all_fifos_empty_seq2;
            for (int bank = 0; bank < B2; bank++) begin
                finished &= (seen_seq2_counts[bank] == expected_seq2_counts[bank]);
            end
            if (finished) begin
                break;
            end
        end
        if (!finished) begin
            $fatal(1, "timed out draining seq2 pipeline after backpressure");
        end

        rst = 1'b1;
        clear_seq2_inputs();
        clear_seq5_inputs();
        clear_expected_seq2();
        clear_expected_seq5();
        @(posedge clk);
        #1;
        rst = 1'b0;

        build_same_bank_seq2_burst(i_updates_seq2, 0);
        append_expected_seq2_push(i_updates_seq2);
        i_valid_seq2 = 1'b1;
        #1;
        if (i_busy_seq2) begin
            $fatal(1, "seq2 same-bank overflow burst should be staged on first acceptance");
        end
        @(posedge clk);
        #1;
        observe_seq2_step();
        clear_seq2_inputs();

        saw_backpressure = 1'b0;
        finished = 1'b0;
        for (int cycle = 0; cycle < 48; cycle++) begin
            saw_backpressure |= i_busy_seq2;
            @(posedge clk);
            #1;
            observe_seq2_step();
            finished = all_fifos_empty_seq2;
            for (int bank = 0; bank < B2; bank++) begin
                finished &= (seen_seq2_counts[bank] == expected_seq2_counts[bank]);
            end
            if (finished) begin
                break;
            end
        end
        if (!saw_backpressure) begin
            $fatal(1, "seq2 same-bank overflow burst should require staged draining");
        end
        if (!finished) begin
            $fatal(1, "timed out draining seq2 same-bank overflow burst");
        end

        rst = 1'b1;
        clear_seq2_inputs();
        clear_seq5_inputs();
        clear_expected_seq2();
        clear_expected_seq5();
        @(posedge clk);
        #1;
        rst = 1'b0;

        seed_update(i_updates_seq5[0], make_seq5(10, 11, 12, 13, 14), 1'b1);
        seed_update(i_updates_seq5[1], make_seq5(10, 11, 12, 13, 14), 1'b1);
        seed_update(i_updates_seq5[2], make_seq5(21, 22, 23, 24, 25), 1'b0);
        seed_update(i_updates_seq5[3], make_seq5(31, 32, 33, 34, 35), 1'b1);
        seed_update(i_updates_seq5[4], make_seq5(41, 42, 43, 44, 45), 1'b0);
        seed_update(i_updates_seq5[5], make_seq5(41, 42, 43, 44, 45), 1'b0);
        append_expected_seq5_push(i_updates_seq5);
        i_valid_seq5 = 1'b1;
        #1;
        if (i_busy_seq5) begin
            $fatal(1, "seq5 pipeline should accept the first burst");
        end
        @(posedge clk);
        #1;
        observe_seq5_step();
        clear_seq5_inputs();
        finished = 1'b0;
        for (int cycle = 0; cycle < 24; cycle++) begin
            @(posedge clk);
            #1;
            observe_seq5_step();
            finished = all_fifos_empty_seq5;
            for (int bank = 0; bank < B5; bank++) begin
                finished &= (seen_seq5_counts[bank] == expected_seq5_counts[bank]);
            end
            if (finished) begin
                break;
            end
        end
        if (!finished) begin
            $fatal(1, "timed out draining seq5 pipeline");
        end

        $finish;
    end
endmodule
