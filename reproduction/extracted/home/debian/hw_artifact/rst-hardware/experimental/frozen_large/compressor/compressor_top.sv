`timescale 1ps / 1ps
`default_nettype none

module CompressorTop
    import rst_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  symbol_t page_in [CHUNK_WIDTH],
    output vsym_t compressed_out [CHUNK_WIDTH],
    output seq_t dict_seqs [MAX_DICT_ENTRIES],
    output logic [2:0] dict_lens [MAX_DICT_ENTRIES],
    output dict_count_t dict_count,
    output dict_packed_t dict_packed,
    output dict_bit_count_t dict_packed_bits,
    output logic done
);
    typedef enum logic [3:0] {
        IDLE,
        INIT_COUNT,
        WAIT_DRAIN,
        SELECT_TOP,
        WAIT_TOP_RESULT,
        WAIT_TOP_SCORE,
        CHECK_UTILITY,
        START_SUBSTITUTE,
        WAIT_SUBSTITUTE,
        GEN_UPDATES,
        PACK_DICT,
        DONE_STATE
    } state_t;

    state_t state;

    vsym_t page_reg [CHUNK_WIDTH];
    vsym_t update_pre_page [CHUNK_WIDTH];
    vsym_t update_post_page [CHUNK_WIDTH];
    logic [CHUNK_WIDTH-1:0] update_pre_sites;
    logic [CHUNK_WIDTH-1:0] update_post_sites;
    logic [2:0] update_sel_seq_len;

    seq_t dict_seqs_r [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens_r [MAX_DICT_ENTRIES];
    dict_count_t dict_count_r;
    dict_packed_t dict_packed_r;
    dict_bit_count_t dict_packed_bits_r;
    logic [$clog2(MEMORY_BLOCKS * 64 * 8 + 1)-1:0] dict_space_bits;

    logic init_i_busy;
    logic init_o_valid;
    logic init_done;
    logic init_last_batch_accepted;
    seq_update_t init_updates_len2 [PIPE_WIDTH_SEQ2];
    seq_update_t init_updates_len3 [PIPE_WIDTH_SEQ3];
    seq_update_t init_updates_len4 [PIPE_WIDTH_SEQ4];
    seq_update_t init_updates_len5 [PIPE_WIDTH_SEQ5];

    logic update_i_busy;
    logic update_o_valid;
    logic update_done;
    logic update_last_batch_accepted;
    logic init_start_pulse_r;
    logic update_start_pulse_r;
    seq_update_t update_updates_len2 [PIPE_WIDTH_SEQ2];
    seq_update_t update_updates_len3 [PIPE_WIDTH_SEQ3];
    seq_update_t update_updates_len4 [PIPE_WIDTH_SEQ4];
    seq_update_t update_updates_len5 [PIPE_WIDTH_SEQ5];

    seq_update_t pipe_updates_len2 [PIPE_WIDTH_SEQ2];
    seq_update_t pipe_updates_len3 [PIPE_WIDTH_SEQ3];
    seq_update_t pipe_updates_len4 [PIPE_WIDTH_SEQ4];
    seq_update_t pipe_updates_len5 [PIPE_WIDTH_SEQ5];
    logic pipe_input_valid;

    logic pipe_busy_seq2;
    logic pipe_busy_seq3;
    logic pipe_busy_seq4;
    logic pipe_busy_seq5;
    logic pipe_empty_seq2;
    logic pipe_empty_seq3;
    logic pipe_empty_seq4;
    logic pipe_empty_seq5;
    logic all_pipes_empty;

    agg_update_t ht_updates_seq2 [BANKS_SEQ2];
    logic ht_valid_seq2 [BANKS_SEQ2];
    agg_update_t ht_updates_seq3 [BANKS_SEQ3];
    logic ht_valid_seq3 [BANKS_SEQ3];
    agg_update_t ht_updates_seq4 [BANKS_SEQ4];
    logic ht_valid_seq4 [BANKS_SEQ4];
    agg_update_t ht_updates_seq5 [BANKS_SEQ5];
    logic ht_valid_seq5 [BANKS_SEQ5];

    top_candidate_t top_result;
    logic top_valid;
    logic query_top;

    seq_t pending_sel_seq;
    logic [2:0] pending_sel_seq_len;
    symbol_t pending_repl_sym;
    logic mfr_i_valid;
    logic mfr_o_valid;
    vsym_t post_sub [CHUNK_WIDTH];
    logic [CHUNK_WIDTH-1:0] sub_sites;
    logic [CHUNK_WIDTH-1:0] post_sub_sites;
    symbol_t repl_sym;

    logic signed [COUNT_BITS+7:0] selected_utility_num;
    logic [7:0] selected_cost_bits;
    seq_t active_selected_seq;
    logic [2:0] active_selected_seq_len;
    logic can_substitute;
    dict_packed_t dict_packed_comb;
    dict_bit_count_t dict_packed_bits_comb;

    assign init_i_busy = pipe_busy_seq2 | pipe_busy_seq3 | pipe_busy_seq4 | pipe_busy_seq5;
    assign update_i_busy = init_i_busy;
    assign all_pipes_empty = pipe_empty_seq2 && pipe_empty_seq3 && pipe_empty_seq4 && pipe_empty_seq5;
    assign query_top = (state == SELECT_TOP) || ((state == WAIT_DRAIN) && all_pipes_empty);
    assign repl_sym = dict_code_symbol(dict_count_r);
    assign selected_utility_num = utility_numerator(active_selected_seq_len, top_result.count);
    assign selected_cost_bits = dict_entry_cost_bits(active_selected_seq_len);
    assign mfr_i_valid = (state == START_SUBSTITUTE);
    assign can_substitute = top_valid &&
        top_result.valid &&
        (selected_utility_num > 0) &&
        (dict_space_bits >= selected_cost_bits) &&
        (dict_count_r < MAX_DICT_ENTRIES);

    function automatic logic should_truncate_aabaa(
        input seq_t seq,
        input logic [2:0] seq_len
    );
        begin
            should_truncate_aabaa =
                (seq_len == 3'd5) &&
                (seq[0] == seq[1]) &&
                (seq[0] == seq[3]) &&
                (seq[0] == seq[4]) &&
                (seq[2] != seq[0]);
        end
    endfunction

    always_comb begin
        active_selected_seq = top_result.seq;
        active_selected_seq_len =
            should_truncate_aabaa(top_result.seq, top_result.seq_len) ?
            3'd4 : top_result.seq_len;
    end

    InitSeqCountGen init_gen (
        .clk(clk),
        .rst(rst),
        .start(init_start_pulse_r),
        .i_busy(init_i_busy),
        .data(page_reg),
        .o_valid(init_o_valid),
        .o_updates_len2(init_updates_len2),
        .o_updates_len3(init_updates_len3),
        .o_updates_len4(init_updates_len4),
        .o_updates_len5(init_updates_len5),
        .last_batch_accepted(init_last_batch_accepted),
        .done(init_done)
    );

    SeqUpdateGen update_gen (
        .clk(clk),
        .rst(rst),
        .start(update_start_pulse_r),
        .i_busy(update_i_busy),
        .pre_sub(update_pre_page),
        .post_sub(update_post_page),
        .pre_sub_sites(update_pre_sites),
        .post_sub_sites(update_post_sites),
        .sel_seq_len(update_sel_seq_len),
        .o_valid(update_o_valid),
        .o_updates_len2(update_updates_len2),
        .o_updates_len3(update_updates_len3),
        .o_updates_len4(update_updates_len4),
        .o_updates_len5(update_updates_len5),
        .last_batch_accepted(update_last_batch_accepted),
        .done(update_done)
    );

    UpdatePipelineN #(
        .PIPE_WIDTH(PIPE_WIDTH_SEQ2),
        .NUM_BANKS(BANKS_SEQ2)
    ) pipe_seq2 (
        .clk(clk),
        .rst(rst),
        .i_updates(pipe_updates_len2),
        .i_valid(pipe_input_valid),
        .i_busy(pipe_busy_seq2),
        .all_fifos_empty(pipe_empty_seq2),
        .ht_updates(ht_updates_seq2),
        .ht_update_valid(ht_valid_seq2)
    );

    UpdatePipelineN #(
        .PIPE_WIDTH(PIPE_WIDTH_SEQ3),
        .NUM_BANKS(BANKS_SEQ3)
    ) pipe_seq3 (
        .clk(clk),
        .rst(rst),
        .i_updates(pipe_updates_len3),
        .i_valid(pipe_input_valid),
        .i_busy(pipe_busy_seq3),
        .all_fifos_empty(pipe_empty_seq3),
        .ht_updates(ht_updates_seq3),
        .ht_update_valid(ht_valid_seq3)
    );

    UpdatePipelineN #(
        .PIPE_WIDTH(PIPE_WIDTH_SEQ4),
        .NUM_BANKS(BANKS_SEQ4)
    ) pipe_seq4 (
        .clk(clk),
        .rst(rst),
        .i_updates(pipe_updates_len4),
        .i_valid(pipe_input_valid),
        .i_busy(pipe_busy_seq4),
        .all_fifos_empty(pipe_empty_seq4),
        .ht_updates(ht_updates_seq4),
        .ht_update_valid(ht_valid_seq4)
    );

    UpdatePipelineN #(
        .PIPE_WIDTH(PIPE_WIDTH_SEQ5),
        .NUM_BANKS(BANKS_SEQ5)
    ) pipe_seq5 (
        .clk(clk),
        .rst(rst),
        .i_updates(pipe_updates_len5),
        .i_valid(pipe_input_valid),
        .i_busy(pipe_busy_seq5),
        .all_fifos_empty(pipe_empty_seq5),
        .ht_updates(ht_updates_seq5),
        .ht_update_valid(ht_valid_seq5)
    );

    HashTableTop hash_table (
        .clk(clk),
        .rst(rst),
        .updates_seq2(ht_updates_seq2),
        .update_valid_seq2(ht_valid_seq2),
        .updates_seq3(ht_updates_seq3),
        .update_valid_seq3(ht_valid_seq3),
        .updates_seq4(ht_updates_seq4),
        .update_valid_seq4(ht_valid_seq4),
        .updates_seq5(ht_updates_seq5),
        .update_valid_seq5(ht_valid_seq5),
        .query_top(query_top),
        .top_result(top_result),
        .top_valid(top_valid)
    );

    MatchFilterReplace mfr (
        .clk(clk),
        .rst(rst),
        .i_valid(mfr_i_valid),
        .pre_sub(page_reg),
        .sel_seq(pending_sel_seq),
        .sel_seq_len(pending_sel_seq_len),
        .repl_sym(pending_repl_sym),
        .o_valid(mfr_o_valid),
        .post_sub(post_sub),
        .sub_sites(sub_sites)
    );

    DictSerializer dict_serializer (
        .dict_count(dict_count_r),
        .dict_seqs(dict_seqs_r),
        .dict_lens(dict_lens_r),
        .dict_packed(dict_packed_comb),
        .dict_packed_bits(dict_packed_bits_comb)
    );

    always_comb begin
        pipe_input_valid = 1'b0;

        for (int i = 0; i < PIPE_WIDTH_SEQ2; i++) pipe_updates_len2[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ3; i++) pipe_updates_len3[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ4; i++) pipe_updates_len4[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ5; i++) pipe_updates_len5[i] = '0;

        if (state == INIT_COUNT) begin
            // The generator batch fans out into all four width-specific update
            // pipes together, so only launch when every pipe can accept this
            // shared transaction.
            pipe_input_valid = init_o_valid;
            pipe_input_valid &= !init_i_busy;
            for (int i = 0; i < PIPE_WIDTH_SEQ2; i++) pipe_updates_len2[i] = init_updates_len2[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ3; i++) pipe_updates_len3[i] = init_updates_len3[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ4; i++) pipe_updates_len4[i] = init_updates_len4[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ5; i++) pipe_updates_len5[i] = init_updates_len5[i];
        end else if (state == GEN_UPDATES) begin
            pipe_input_valid = update_o_valid;
            pipe_input_valid &= !update_i_busy;
            for (int i = 0; i < PIPE_WIDTH_SEQ2; i++) pipe_updates_len2[i] = update_updates_len2[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ3; i++) pipe_updates_len3[i] = update_updates_len3[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ4; i++) pipe_updates_len4[i] = update_updates_len4[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ5; i++) pipe_updates_len5[i] = update_updates_len5[i];
        end
    end

    always_comb begin
        for (int i = 0; i < CHUNK_WIDTH; i++) begin
            compressed_out[i] = page_reg[i];
            post_sub_sites[i] = post_sub[i].valid && (post_sub[i].sym == pending_repl_sym);
        end

        for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
            dict_seqs[idx] = dict_seqs_r[idx];
            dict_lens[idx] = dict_lens_r[idx];
        end

        dict_count = dict_count_r;
        dict_packed = dict_packed_r;
        dict_packed_bits = dict_packed_bits_r;
        done = (state == DONE_STATE);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            dict_count_r <= '0;
            dict_packed_r <= '0;
            dict_packed_bits_r <= '0;
            dict_space_bits <= '0;
            init_start_pulse_r <= 1'b0;
            update_start_pulse_r <= 1'b0;
            update_pre_sites <= '0;
            update_post_sites <= '0;
            update_sel_seq_len <= '0;
            pending_sel_seq <= '0;
            pending_sel_seq_len <= '0;
            pending_repl_sym <= '0;

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                page_reg[i] <= '0;
                update_pre_page[i] <= '0;
                update_post_page[i] <= '0;
            end

            for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                dict_seqs_r[idx] <= '0;
                dict_lens_r[idx] <= '0;
            end
        end else begin
            init_start_pulse_r <= 1'b0;
            update_start_pulse_r <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        state <= INIT_COUNT;
                        dict_count_r <= '0;
                        dict_packed_r <= '0;
                        dict_packed_bits_r <= '0;
                        dict_space_bits <= MEMORY_BLOCKS * 64 * 8 - 6;
                        init_start_pulse_r <= 1'b1;
                        update_pre_sites <= '0;
                        update_post_sites <= '0;
                        update_sel_seq_len <= '0;
                        pending_sel_seq <= '0;
                        pending_sel_seq_len <= '0;
                        pending_repl_sym <= '0;

                        for (int i = 0; i < CHUNK_WIDTH; i++) begin
                            page_reg[i].sym <= page_in[i];
                            page_reg[i].valid <= 1'b1;
                            update_pre_page[i] <= '0;
                            update_post_page[i] <= '0;
                        end

                        for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                            dict_seqs_r[idx] <= '0;
                            dict_lens_r[idx] <= '0;
                        end
                    end
                end

                INIT_COUNT: begin
                    if (init_last_batch_accepted || init_done) begin
                        state <= WAIT_DRAIN;
                    end
                end

                WAIT_DRAIN: begin
                    if (all_pipes_empty) begin
                        if (can_substitute) begin
                            pending_sel_seq <= active_selected_seq;
                            pending_sel_seq_len <= active_selected_seq_len;
                            pending_repl_sym <= repl_sym;
                            state <= START_SUBSTITUTE;
                        end else begin
                            state <= PACK_DICT;
                        end
                    end
                end

                SELECT_TOP: begin
                    state <= CHECK_UTILITY;
                end

                WAIT_TOP_RESULT: begin
                    state <= CHECK_UTILITY;
                end

                WAIT_TOP_SCORE: begin
                    state <= CHECK_UTILITY;
                end

                CHECK_UTILITY: begin
                    if (can_substitute) begin
                        pending_sel_seq <= active_selected_seq;
                        pending_sel_seq_len <= active_selected_seq_len;
                        pending_repl_sym <= repl_sym;
                        state <= START_SUBSTITUTE;
                    end else begin
                        state <= PACK_DICT;
                    end
                end

                START_SUBSTITUTE: begin
                    if (mfr_o_valid) begin
                        if (sub_sites == '0) begin
                            state <= PACK_DICT;
                        end else begin
                            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                                update_pre_page[i] <= page_reg[i];
                                update_post_page[i] <= post_sub[i];
                                page_reg[i] <= post_sub[i];
                            end

                            update_pre_sites <= sub_sites;
                            update_post_sites <= post_sub_sites;
                            update_sel_seq_len <= pending_sel_seq_len;
                            dict_seqs_r[dict_count_r] <= pending_sel_seq;
                            dict_lens_r[dict_count_r] <= pending_sel_seq_len;
                            dict_count_r <= dict_count_r + 1'b1;
                            dict_space_bits <= dict_space_bits -
                                dict_entry_cost_bits(pending_sel_seq_len);
                            update_start_pulse_r <= 1'b1;
                            state <= GEN_UPDATES;
                        end
                    end
                end

                WAIT_SUBSTITUTE: begin
                    state <= START_SUBSTITUTE;
                end

                GEN_UPDATES: begin
                    if (update_last_batch_accepted || update_done) begin
                        state <= WAIT_DRAIN;
                    end
                end

                PACK_DICT: begin
                    dict_packed_r <= dict_packed_comb;
                    dict_packed_bits_r <= dict_packed_bits_comb;
                    state <= DONE_STATE;
                end

                DONE_STATE: begin
                    state <= DONE_STATE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
