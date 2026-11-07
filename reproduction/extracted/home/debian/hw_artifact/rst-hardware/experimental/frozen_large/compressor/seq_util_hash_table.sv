`timescale 1ps / 1ps
`default_nettype none

module HashTableBank
    import rst_pkg::*;
#(
    parameter int SEQ_LEN = 2
) (
    input  logic clk,
    input  logic rst,
    input  agg_update_t i_update,
    input  logic i_valid,
    output ht_entry_t top_entry
);
    ht_entry_t entries [SETS_PER_BANK][WAYS];
    ht_entry_t entries_next [SETS_PER_BANK][WAYS];
    ht_entry_t set_tops_r [SETS_PER_BANK];
    ht_entry_t set_tops_next [SETS_PER_BANK];
    ht_entry_t top_entry_next;
    ht_entry_t top_entry_r;

    always_comb begin
        for (int set_idx = 0; set_idx < SETS_PER_BANK; set_idx++) begin
            set_tops_next[set_idx] = set_tops_r[set_idx];
            for (int way = 0; way < WAYS; way++) begin
                entries_next[set_idx][way] = entries[set_idx][way];
            end
        end

        if (i_valid && i_update.valid) begin
            int match_idx;
            int free_idx;
            int min_idx;
            logic signed [COUNT_BITS-1:0] min_count;

            match_idx = -1;
            free_idx = -1;
            min_idx = 0;
            min_count = entries[i_update.set_idx][0].count;

            for (int way = 0; way < WAYS; way++) begin
                if (entries[i_update.set_idx][way].valid &&
                    entries[i_update.set_idx][way].seq == i_update.seq) begin
                    match_idx = way;
                end
                if (!entries[i_update.set_idx][way].valid && free_idx == -1) begin
                    free_idx = way;
                end
                if (!entries[i_update.set_idx][way].valid) begin
                    min_idx = way;
                    min_count = '0;
                end else if (entries[i_update.set_idx][way].count < min_count) begin
                    min_idx = way;
                    min_count = entries[i_update.set_idx][way].count;
                end
            end

            if (match_idx != -1) begin
                logic signed [COUNT_BITS-1:0] next_count;
                next_count = entries[i_update.set_idx][match_idx].count + i_update.count;
                entries_next[i_update.set_idx][match_idx].count = next_count;
                entries_next[i_update.set_idx][match_idx].valid = (next_count > 0);
            end else if (i_update.count > 0) begin
                int insert_idx;
                insert_idx = (free_idx != -1) ? free_idx : min_idx;
                entries_next[i_update.set_idx][insert_idx].seq = i_update.seq;
                entries_next[i_update.set_idx][insert_idx].count = i_update.count;
                entries_next[i_update.set_idx][insert_idx].valid = 1'b1;
            end

            set_tops_next[i_update.set_idx] = '0;
            for (int way = 0; way < WAYS; way++) begin
                if (entries_next[i_update.set_idx][way].valid &&
                    (!set_tops_next[i_update.set_idx].valid ||
                     entries_next[i_update.set_idx][way].count > set_tops_next[i_update.set_idx].count)) begin
                    set_tops_next[i_update.set_idx] = entries_next[i_update.set_idx][way];
                end
            end
        end
    end

    always_comb begin
        top_entry_next = '0;
        for (int set_idx = 0; set_idx < SETS_PER_BANK; set_idx++) begin
            if (set_tops_next[set_idx].valid &&
                (!top_entry_next.valid || set_tops_next[set_idx].count > top_entry_next.count)) begin
                top_entry_next = set_tops_next[set_idx];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int set_idx = 0; set_idx < SETS_PER_BANK; set_idx++) begin
                set_tops_r[set_idx] <= '0;
                for (int way = 0; way < WAYS; way++) begin
                    entries[set_idx][way] <= '0;
                end
            end
            top_entry_r <= '0;
        end else begin
            for (int set_idx = 0; set_idx < SETS_PER_BANK; set_idx++) begin
                set_tops_r[set_idx] <= set_tops_next[set_idx];
                for (int way = 0; way < WAYS; way++) begin
                    entries[set_idx][way] <= entries_next[set_idx][way];
                end
            end
            top_entry_r <= top_entry_next;
        end
    end

    assign top_entry = top_entry_r;
endmodule

module HashTableSubTable
    import rst_pkg::*;
#(
    parameter int SEQ_LEN = 2,
    parameter int NUM_BANKS = BANKS_SEQ2
) (
    input  logic clk,
    input  logic rst,
    input  agg_update_t updates [NUM_BANKS],
    input  logic update_valid [NUM_BANKS],
    output top_candidate_t top_candidate
);
    ht_entry_t bank_tops [NUM_BANKS];

    generate
        for (genvar bank = 0; bank < NUM_BANKS; bank++) begin : gen_banks
            HashTableBank #(
                .SEQ_LEN(SEQ_LEN)
            ) bank_inst (
                .clk(clk),
                .rst(rst),
                .i_update(updates[bank]),
                .i_valid(update_valid[bank]),
                .top_entry(bank_tops[bank])
            );
        end
    endgenerate

    always_comb begin
        top_candidate = '0;
        top_candidate.seq_len = SEQ_LEN[2:0];
        for (int bank = 0; bank < NUM_BANKS; bank++) begin
            if (bank_tops[bank].valid &&
                (!top_candidate.valid || bank_tops[bank].count > top_candidate.count)) begin
                top_candidate.seq = bank_tops[bank].seq;
                top_candidate.seq_len = SEQ_LEN[2:0];
                top_candidate.count = bank_tops[bank].count;
                top_candidate.valid = 1'b1;
            end
        end
    end
endmodule

module HashTableTop
    import rst_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  agg_update_t updates_seq2 [BANKS_SEQ2],
    input  logic update_valid_seq2 [BANKS_SEQ2],
    input  agg_update_t updates_seq3 [BANKS_SEQ3],
    input  logic update_valid_seq3 [BANKS_SEQ3],
    input  agg_update_t updates_seq4 [BANKS_SEQ4],
    input  logic update_valid_seq4 [BANKS_SEQ4],
    input  agg_update_t updates_seq5 [BANKS_SEQ5],
    input  logic update_valid_seq5 [BANKS_SEQ5],
    input  logic query_top,
    output top_candidate_t top_result,
    output logic top_valid
);
    localparam int SCORE_W = COUNT_BITS + 17;
    localparam int SCORE_SEQ2 = 29 * 38 * 47;
    localparam int SCORE_SEQ3 = 2 * 20 * 38 * 47;
    localparam int SCORE_SEQ4 = 3 * 20 * 29 * 47;
    localparam int SCORE_SEQ5 = 4 * 20 * 29 * 38;

    top_candidate_t candidates [4];
    top_candidate_t best_candidate;
    logic [SCORE_W-1:0] candidate_score [4];
    logic [SCORE_W-1:0] best_score;

    HashTableSubTable #(
        .SEQ_LEN(2),
        .NUM_BANKS(BANKS_SEQ2)
    ) seq2_table (
        .clk(clk),
        .rst(rst),
        .updates(updates_seq2),
        .update_valid(update_valid_seq2),
        .top_candidate(candidates[0])
    );

    HashTableSubTable #(
        .SEQ_LEN(3),
        .NUM_BANKS(BANKS_SEQ3)
    ) seq3_table (
        .clk(clk),
        .rst(rst),
        .updates(updates_seq3),
        .update_valid(update_valid_seq3),
        .top_candidate(candidates[1])
    );

    HashTableSubTable #(
        .SEQ_LEN(4),
        .NUM_BANKS(BANKS_SEQ4)
    ) seq4_table (
        .clk(clk),
        .rst(rst),
        .updates(updates_seq4),
        .update_valid(update_valid_seq4),
        .top_candidate(candidates[2])
    );

    HashTableSubTable #(
        .SEQ_LEN(5),
        .NUM_BANKS(BANKS_SEQ5)
    ) seq5_table (
        .clk(clk),
        .rst(rst),
        .updates(updates_seq5),
        .update_valid(update_valid_seq5),
        .top_candidate(candidates[3])
    );

    always_comb begin
        best_candidate = '0;
        best_score = '0;
        candidate_score[0] = $unsigned(candidates[0].count) * SCORE_SEQ2;
        candidate_score[1] = $unsigned(candidates[1].count) * SCORE_SEQ3;
        candidate_score[2] = $unsigned(candidates[2].count) * SCORE_SEQ4;
        candidate_score[3] = $unsigned(candidates[3].count) * SCORE_SEQ5;
        for (int idx = 0; idx < 4; idx++) begin
            if (candidates[idx].valid &&
                (!best_candidate.valid || candidate_score[idx] > best_score)) begin
                best_candidate = candidates[idx];
                best_score = candidate_score[idx];
            end
        end
    end

    always_comb begin
        top_result = best_candidate;
        top_valid = best_candidate.valid;
    end
endmodule
