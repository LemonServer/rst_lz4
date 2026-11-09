`timescale 1ps / 1ps
`default_nettype none

module PageCompressorTop
    import rst_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  symbol_t page_in [PAGE_WIDTH],
    output vsym_t compressed_out [PAGE_WIDTH],
    output seq_t dict_seqs [MAX_DICT_ENTRIES],
    output logic [2:0] dict_lens [MAX_DICT_ENTRIES],
    output dict_count_t dict_count,
    output dict_packed_t dict_packed,
    output dict_bit_count_t dict_packed_bits,
    output logic done
);
    localparam int PAGE_IDX_W = $clog2(PAGE_CHUNKS + 1);

    typedef enum logic [3:0] {
        IDLE,
        INIT_COUNT,
        WAIT_INIT_DRAIN,
        SELECT_TOP,
        WAIT_TOP_RESULT,
        WAIT_TOP_SCORE,
        CHECK_UTILITY,
        RECORD_DICT,
        START_SUBSTITUTE,
        WAIT_SUBSTITUTE,
        GEN_UPDATES,
        WAIT_UPDATE_DRAIN,
        PACK_DICT,
        DONE_STATE
    } state_t;

    state_t state_r;

    vsym_t page_reg_r [PAGE_WIDTH];
    vsym_t chunk_buf_r [2][CHUNK_WIDTH];
    logic active_buf_sel_r;
    logic [PAGE_IDX_W-1:0] current_chunk_idx_r;
    logic [PAGE_IDX_W-1:0] next_chunk_to_preload_r;

    seq_t dict_seqs_r [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens_r [MAX_DICT_ENTRIES];
    dict_count_t dict_count_r;
    dict_packed_t dict_packed_r;
    dict_bit_count_t dict_packed_bits_r;
    logic [$clog2(MEMORY_BLOCKS * 64 * 8 + 1)-1:0] dict_space_bits_r;

    seq_t selected_seq_r;
    logic [2:0] selected_seq_len_r;
    symbol_t selected_repl_sym_r;

    logic init_i_busy;
    logic init_o_valid;
    logic init_done;
    logic init_last_batch_accepted;
    logic init_start_fast;
    logic init_start;
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

    vsym_t active_chunk [CHUNK_WIDTH];
    vsym_t init_data [CHUNK_WIDTH];
    vsym_t update_pre_page [CHUNK_WIDTH];
    vsym_t update_post_page [CHUNK_WIDTH];
    logic mfr_i_valid;
    logic mfr_o_valid;
    vsym_t post_sub [CHUNK_WIDTH];
    logic [CHUNK_WIDTH-1:0] sub_sites;
    logic [CHUNK_WIDTH-1:0] update_pre_sites;
    logic [CHUNK_WIDTH-1:0] update_post_sites;
    logic [2:0] update_sel_seq_len;

    logic signed [COUNT_BITS+7:0] selected_utility_num;
    logic [7:0] selected_cost_bits;
    logic signed [COUNT_BITS+7:0] active_selected_utility_num;
    logic [7:0] active_selected_cost_bits;
    seq_t active_selected_seq;
    logic [2:0] active_selected_seq_len;
    logic can_substitute;
    logic force_free_prefix_substitution;
    seq_t forced_selected_seq;
    logic [2:0] forced_selected_seq_len;
    dict_packed_t dict_packed_comb;
    dict_bit_count_t dict_packed_bits_comb;
    localparam int EXP_FREE_DICT_ENTRIES = 2;
    localparam int REUSE_CODE_START = 63;
    localparam int REUSE_CODE_COUNT = 8;

    assign init_i_busy = pipe_busy_seq2 | pipe_busy_seq3 | pipe_busy_seq4 | pipe_busy_seq5;
    assign update_i_busy = init_i_busy;
    assign all_pipes_empty = pipe_empty_seq2 && pipe_empty_seq3 && pipe_empty_seq4 && pipe_empty_seq5;
    assign query_top =
        !force_free_prefix_substitution &&
        ((state_r == SELECT_TOP) ||
         ((state_r == WAIT_INIT_DRAIN) &&
          all_pipes_empty &&
          (current_chunk_idx_r == PAGE_CHUNKS - 1)) ||
         ((state_r == WAIT_UPDATE_DRAIN) &&
          all_pipes_empty &&
          (current_chunk_idx_r == PAGE_CHUNKS - 1)));
    assign selected_utility_num = utility_numerator(active_selected_seq_len, top_result.count);
    assign selected_cost_bits = dict_entry_cost_bits(active_selected_seq_len);
    assign init_start_fast =
        (state_r == INIT_COUNT) &&
        init_last_batch_accepted &&
        (current_chunk_idx_r != PAGE_CHUNKS - 1);
    assign init_start = init_start_pulse_r || init_start_fast;
    assign mfr_i_valid = (state_r == START_SUBSTITUTE);
    assign can_substitute = (dict_count_r < MAX_DICT_ENTRIES) &&
        (force_free_prefix_substitution ||
            (top_valid &&
             top_result.valid &&
             (active_selected_utility_num > 0) &&
             (dict_space_bits_r >= active_selected_cost_bits)));
    assign done = (state_r == DONE_STATE);

    function automatic symbol_t code_symbol_ext(input int unsigned code_idx);
        code_symbol_ext = {1'b1, code_idx[7:0]};
    endfunction

    function automatic symbol_t reuse_symbol(input int unsigned distance);
        reuse_symbol = code_symbol_ext(REUSE_CODE_START + distance - 1);
    endfunction

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

    function automatic int unsigned dict_code_length(input symbol_t sym);
        int unsigned code_idx;
        begin
            code_idx = sym[7:0];
            if (!sym[8]) begin
                dict_code_length = (code_idx == 0) ? 4 : 9;
            end else if (code_idx <= 5) begin
                dict_code_length = 5;
            end else if (code_idx <= 11) begin
                dict_code_length = 6;
            end else if (code_idx <= 18) begin
                dict_code_length = 7;
            end else if (code_idx <= 24) begin
                dict_code_length = 8;
            end else if (code_idx <= 31) begin
                dict_code_length = 9;
            end else if (code_idx <= 35) begin
                dict_code_length = 10;
            end else if (code_idx <= 40) begin
                dict_code_length = 11;
            end else if (code_idx <= 62) begin
                dict_code_length = 12;
            end else if (code_idx == 63) begin
                dict_code_length = 7;
            end else if (code_idx == 64) begin
                dict_code_length = 6;
            end else if (code_idx <= 66) begin
                dict_code_length = 7;
            end else if (code_idx <= 70) begin
                dict_code_length = 8;
            end else begin
                dict_code_length = 0;
            end
        end
    endfunction

    task automatic push_history(
        inout symbol_t history [REUSE_CODE_COUNT],
        inout int unsigned history_len,
        input symbol_t sym
    );
        begin
            if (history_len < REUSE_CODE_COUNT) begin
                history[history_len] = sym;
                history_len = history_len + 1;
            end else begin
                for (int idx = 0; idx < REUSE_CODE_COUNT - 1; idx++) begin
                    history[idx] = history[idx + 1];
                end
                history[REUSE_CODE_COUNT - 1] = sym;
            end
        end
    endtask

    function automatic symbol_t best_reuse_token(
        input symbol_t sym,
        input symbol_t history [REUSE_CODE_COUNT],
        input int unsigned history_len
    );
        symbol_t best_token;
        symbol_t candidate;
        int unsigned best_len;
        int unsigned candidate_len;
        begin
            best_token = sym;
            best_len = dict_code_length(sym);

            for (int distance = 1; distance <= REUSE_CODE_COUNT; distance++) begin
                if ((history_len >= distance) && (history[history_len - distance] == sym)) begin
                    candidate = reuse_symbol(distance);
                    candidate_len = dict_code_length(candidate);
                    if (candidate_len < best_len) begin
                        best_token = candidate;
                        best_len = candidate_len;
                    end
                end
            end

            best_reuse_token = best_token;
        end
    endfunction

    always_comb begin
        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
            active_chunk[lane] = chunk_buf_r[active_buf_sel_r][lane];
            init_data[lane] = active_chunk[lane];
        end
    end

    always_comb begin
        active_selected_seq = top_result.seq;
        active_selected_seq_len =
            should_truncate_aabaa(top_result.seq, top_result.seq_len) ?
            3'd4 : top_result.seq_len;
    end

    always_comb begin
        symbol_t dict_history [REUSE_CODE_COUNT];
        int unsigned dict_history_len;
        symbol_t token;

        for (int idx = 0; idx < REUSE_CODE_COUNT; idx++) begin
            dict_history[idx] = '0;
        end
        dict_history_len = 0;

        push_history(dict_history, dict_history_len, symbol_t'(9'h000));
        push_history(dict_history, dict_history_len, symbol_t'(9'h000));
        push_history(dict_history, dict_history_len, code_symbol_ext(0));
        push_history(dict_history, dict_history_len, code_symbol_ext(0));

        for (int dict_idx = EXP_FREE_DICT_ENTRIES; dict_idx < MAX_DICT_ENTRIES; dict_idx++) begin
            if (dict_idx < dict_count_r) begin
                for (int sym_idx = 0; sym_idx < MAX_SEQ_LEN; sym_idx++) begin
                    if (sym_idx < dict_lens_r[dict_idx]) begin
                        push_history(dict_history, dict_history_len, dict_seqs_r[dict_idx][sym_idx]);
                    end
                end
            end
        end

`ifdef RST_EXPERIMENTAL_FREE_PREFIX
        active_selected_cost_bits = force_free_prefix_substitution ? 8'd0 : 8'd2;
        if (!force_free_prefix_substitution) begin
            for (int sym_idx = 0; sym_idx < MAX_SEQ_LEN; sym_idx++) begin
                if (sym_idx < active_selected_seq_len) begin
                    token = best_reuse_token(active_selected_seq[sym_idx], dict_history, dict_history_len);
                    active_selected_cost_bits = active_selected_cost_bits + dict_code_length(token);
                    push_history(dict_history, dict_history_len, active_selected_seq[sym_idx]);
                end
            end
        end
        active_selected_utility_num =
            force_free_prefix_substitution ? {{(COUNT_BITS+7){1'b0}}, 1'b1} :
            ((top_result.count * (9 * (active_selected_seq_len - 1))) - active_selected_cost_bits);
`else
        active_selected_cost_bits = force_free_prefix_substitution ? 8'd0 : selected_cost_bits;
        active_selected_utility_num = selected_utility_num;
`endif
    end

    always_comb begin
        force_free_prefix_substitution = 1'b0;
        forced_selected_seq = '0;
        forced_selected_seq_len = '0;

`ifdef RST_EXPERIMENTAL_FREE_PREFIX
        if (dict_count_r < EXP_FREE_DICT_ENTRIES) begin
`else
        if (1'b0) begin
`endif
            force_free_prefix_substitution = 1'b1;
            forced_selected_seq_len = 3'd2;

            if (dict_count_r == 0) begin
                forced_selected_seq[0] = 9'h000;
                forced_selected_seq[1] = 9'h000;
            end else begin
                forced_selected_seq[0] = dict_code_symbol(dict_count_t'(0));
                forced_selected_seq[1] = dict_code_symbol(dict_count_t'(0));
            end
        end
    end

    InitSeqCountGen init_gen (
        .clk(clk),
        .rst(rst),
        .start(init_start),
        .i_busy(init_i_busy),
        .data(init_data),
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
        .pre_sub(active_chunk),
        .sel_seq(selected_seq_r),
        .sel_seq_len(selected_seq_len_r),
        .repl_sym(selected_repl_sym_r),
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

        if (state_r == INIT_COUNT) begin
            // This shared launch fans out to every width-specific update pipe,
            // so keep it atomic across the full set of consumers.
            pipe_input_valid = init_o_valid;
            pipe_input_valid &= !init_i_busy;
            for (int i = 0; i < PIPE_WIDTH_SEQ2; i++) pipe_updates_len2[i] = init_updates_len2[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ3; i++) pipe_updates_len3[i] = init_updates_len3[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ4; i++) pipe_updates_len4[i] = init_updates_len4[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ5; i++) pipe_updates_len5[i] = init_updates_len5[i];
        end else if (state_r == GEN_UPDATES) begin
            pipe_input_valid = update_o_valid;
            pipe_input_valid &= !update_i_busy;
            for (int i = 0; i < PIPE_WIDTH_SEQ2; i++) pipe_updates_len2[i] = update_updates_len2[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ3; i++) pipe_updates_len3[i] = update_updates_len3[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ4; i++) pipe_updates_len4[i] = update_updates_len4[i];
            for (int i = 0; i < PIPE_WIDTH_SEQ5; i++) pipe_updates_len5[i] = update_updates_len5[i];
        end
    end

    always_comb begin
        for (int i = 0; i < PAGE_WIDTH; i++) begin
            compressed_out[i] = page_reg_r[i];
        end

        for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
            dict_seqs[idx] = dict_seqs_r[idx];
            dict_lens[idx] = dict_lens_r[idx];
        end

        dict_count = dict_count_r;
        dict_packed = dict_packed_r;
        dict_packed_bits = dict_packed_bits_r;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r <= IDLE;
            active_buf_sel_r <= 1'b0;
            current_chunk_idx_r <= '0;
            next_chunk_to_preload_r <= '0;
            dict_count_r <= '0;
            dict_packed_r <= '0;
            dict_packed_bits_r <= '0;
            dict_space_bits_r <= '0;
            init_start_pulse_r <= 1'b0;
            update_start_pulse_r <= 1'b0;
            selected_seq_r <= '0;
            selected_seq_len_r <= '0;
            selected_repl_sym_r <= '0;
            update_pre_sites <= '0;
            update_post_sites <= '0;
            update_sel_seq_len <= '0;

            for (int i = 0; i < PAGE_WIDTH; i++) begin
                page_reg_r[i] <= '0;
            end

            for (int buf_idx = 0; buf_idx < 2; buf_idx++) begin
                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                    chunk_buf_r[buf_idx][lane] <= '0;
                end
            end

            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                update_pre_page[lane] <= '0;
                update_post_page[lane] <= '0;
            end

            for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                dict_seqs_r[idx] <= '0;
                dict_lens_r[idx] <= '0;
            end
        end else begin
            init_start_pulse_r <= 1'b0;
            update_start_pulse_r <= 1'b0;

            case (state_r)
                IDLE,
                DONE_STATE: begin
                    if (start) begin
`ifdef RST_EXPERIMENTAL_FREE_PREFIX
                        state_r <= RECORD_DICT;
                        init_start_pulse_r <= 1'b0;
`else
                        state_r <= INIT_COUNT;
                        init_start_pulse_r <= 1'b1;
`endif
                        active_buf_sel_r <= 1'b0;
                        current_chunk_idx_r <= '0;
                        next_chunk_to_preload_r <= (PAGE_CHUNKS > 1) ? PAGE_IDX_W'(2) : PAGE_IDX_W'(1);
                        dict_count_r <= '0;
                        dict_packed_r <= '0;
                        dict_packed_bits_r <= '0;
                        dict_space_bits_r <= MEMORY_BLOCKS * 64 * 8 - 6;
                        selected_seq_r <= '0;
                        selected_seq_len_r <= '0;
                        selected_repl_sym_r <= '0;
                        update_pre_sites <= '0;
                        update_post_sites <= '0;
                        update_sel_seq_len <= '0;

                        for (int i = 0; i < PAGE_WIDTH; i++) begin
                            page_reg_r[i].sym <= page_in[i];
                            page_reg_r[i].valid <= 1'b1;
                        end

                        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                            chunk_buf_r[0][lane].sym <= page_in[lane];
                            chunk_buf_r[0][lane].valid <= 1'b1;

                            update_pre_page[lane] <= '0;
                            update_post_page[lane] <= '0;

                            if (PAGE_CHUNKS > 1) begin
                                chunk_buf_r[1][lane].sym <= page_in[CHUNK_WIDTH + lane];
                                chunk_buf_r[1][lane].valid <= 1'b1;
                            end else begin
                                chunk_buf_r[1][lane] <= '0;
                            end
                        end

                        for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                            dict_seqs_r[idx] <= '0;
                            dict_lens_r[idx] <= '0;
                        end
                    end
                end

                INIT_COUNT: begin
                    if (init_last_batch_accepted || init_done) begin
                        if (current_chunk_idx_r == PAGE_CHUNKS - 1) begin
                            state_r <= WAIT_INIT_DRAIN;
                        end else begin
                            int base_idx;

                            if (next_chunk_to_preload_r < PAGE_CHUNKS) begin
                                base_idx = next_chunk_to_preload_r * CHUNK_WIDTH;
                                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                    chunk_buf_r[active_buf_sel_r][lane] <= page_reg_r[base_idx + lane];
                                end
                                next_chunk_to_preload_r <= next_chunk_to_preload_r + 1'b1;
                            end

                            active_buf_sel_r <= ~active_buf_sel_r;
                            current_chunk_idx_r <= current_chunk_idx_r + 1'b1;
                            state_r <= INIT_COUNT;
                        end
                    end
                end

                WAIT_INIT_DRAIN: begin
                    if (all_pipes_empty) begin
                        if (current_chunk_idx_r == PAGE_CHUNKS - 1) begin
                            if (force_free_prefix_substitution) begin
                                state_r <= RECORD_DICT;
                            end else if (can_substitute) begin
                                selected_seq_r <= active_selected_seq;
                                selected_seq_len_r <= active_selected_seq_len;
                                selected_repl_sym_r <= dict_code_symbol(dict_count_r);
                                dict_seqs_r[dict_count_r] <= active_selected_seq;
                                dict_lens_r[dict_count_r] <= active_selected_seq_len;
                                dict_count_r <= dict_count_r + 1'b1;
                                dict_space_bits_r <= dict_space_bits_r - active_selected_cost_bits;
                                active_buf_sel_r <= 1'b0;
                                current_chunk_idx_r <= '0;
                                next_chunk_to_preload_r <= (PAGE_CHUNKS > 1) ? PAGE_IDX_W'(2) : PAGE_IDX_W'(1);

                                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                    chunk_buf_r[0][lane] <= page_reg_r[lane];
                                    if (PAGE_CHUNKS > 1) begin
                                        chunk_buf_r[1][lane] <= page_reg_r[CHUNK_WIDTH + lane];
                                    end else begin
                                        chunk_buf_r[1][lane] <= '0;
                                    end
                                end

                                state_r <= START_SUBSTITUTE;
                            end else begin
                                state_r <= PACK_DICT;
                            end
                        end
                    end
                end

                SELECT_TOP: begin
                    state_r <= CHECK_UTILITY;
                end

                WAIT_TOP_RESULT: begin
                    state_r <= CHECK_UTILITY;
                end

                WAIT_TOP_SCORE: begin
                    state_r <= CHECK_UTILITY;
                end

                CHECK_UTILITY: begin
                    if (can_substitute) begin
                        state_r <= RECORD_DICT;
                    end else begin
                        state_r <= PACK_DICT;
                    end
                end

                RECORD_DICT: begin
                    selected_seq_r <= force_free_prefix_substitution ? forced_selected_seq : active_selected_seq;
                    selected_seq_len_r <= force_free_prefix_substitution ? forced_selected_seq_len : active_selected_seq_len;
                    selected_repl_sym_r <= dict_code_symbol(dict_count_r);
                    dict_seqs_r[dict_count_r] <=
                        force_free_prefix_substitution ? forced_selected_seq : active_selected_seq;
                    dict_lens_r[dict_count_r] <=
                        force_free_prefix_substitution ? forced_selected_seq_len : active_selected_seq_len;
                    dict_count_r <= dict_count_r + 1'b1;
                    dict_space_bits_r <= dict_space_bits_r - active_selected_cost_bits;
                    active_buf_sel_r <= 1'b0;
                    current_chunk_idx_r <= '0;
                    next_chunk_to_preload_r <= (PAGE_CHUNKS > 1) ? PAGE_IDX_W'(2) : PAGE_IDX_W'(1);

                    for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                        chunk_buf_r[0][lane] <= page_reg_r[lane];
                        if (PAGE_CHUNKS > 1) begin
                            chunk_buf_r[1][lane] <= page_reg_r[CHUNK_WIDTH + lane];
                        end else begin
                            chunk_buf_r[1][lane] <= '0;
                        end
                    end

                    state_r <= START_SUBSTITUTE;
                end

                START_SUBSTITUTE: begin
                    int base_idx;
                    logic bootstrap_prefix_mode;

                    bootstrap_prefix_mode = 1'b0;
`ifdef RST_EXPERIMENTAL_FREE_PREFIX
                    bootstrap_prefix_mode = (dict_count_r <= EXP_FREE_DICT_ENTRIES);
`endif

                    if (mfr_o_valid) begin
                        base_idx = current_chunk_idx_r * CHUNK_WIDTH;

                        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                            chunk_buf_r[active_buf_sel_r][lane] <= post_sub[lane];
                            page_reg_r[base_idx + lane] <= post_sub[lane];
                        end

                        if (bootstrap_prefix_mode) begin
                            if (current_chunk_idx_r == PAGE_CHUNKS - 1) begin
                                active_buf_sel_r <= 1'b0;
                                current_chunk_idx_r <= '0;
                                next_chunk_to_preload_r <= (PAGE_CHUNKS > 1) ? PAGE_IDX_W'(2) : PAGE_IDX_W'(1);

                                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                    if (current_chunk_idx_r == '0) begin
                                        chunk_buf_r[0][lane] <= post_sub[lane];
                                    end else begin
                                        chunk_buf_r[0][lane] <= page_reg_r[lane];
                                    end
                                    if (PAGE_CHUNKS > 1) begin
                                        if (current_chunk_idx_r == PAGE_IDX_W'(1)) begin
                                            chunk_buf_r[1][lane] <= post_sub[lane];
                                        end else begin
                                            chunk_buf_r[1][lane] <= page_reg_r[CHUNK_WIDTH + lane];
                                        end
                                    end else begin
                                        chunk_buf_r[1][lane] <= '0;
                                    end
                                end

                                if (dict_count_r < EXP_FREE_DICT_ENTRIES) begin
                                    state_r <= RECORD_DICT;
                                end else begin
                                    init_start_pulse_r <= 1'b1;
                                    state_r <= INIT_COUNT;
                                end
                            end else begin
                                if (next_chunk_to_preload_r < PAGE_CHUNKS) begin
                                    base_idx = next_chunk_to_preload_r * CHUNK_WIDTH;
                                    for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                        chunk_buf_r[active_buf_sel_r][lane] <= page_reg_r[base_idx + lane];
                                    end
                                    next_chunk_to_preload_r <= next_chunk_to_preload_r + 1'b1;
                                end

                                active_buf_sel_r <= ~active_buf_sel_r;
                                current_chunk_idx_r <= current_chunk_idx_r + 1'b1;
                                state_r <= START_SUBSTITUTE;
                            end
                        end else begin
                            if (sub_sites == '0) begin
                                if (current_chunk_idx_r == PAGE_CHUNKS - 1) begin
                                    if (all_pipes_empty) begin
                                        if (can_substitute) begin
                                            selected_seq_r <= active_selected_seq;
                                            selected_seq_len_r <= active_selected_seq_len;
                                            selected_repl_sym_r <= dict_code_symbol(dict_count_r);
                                            dict_seqs_r[dict_count_r] <= active_selected_seq;
                                            dict_lens_r[dict_count_r] <= active_selected_seq_len;
                                            dict_count_r <= dict_count_r + 1'b1;
                                            dict_space_bits_r <= dict_space_bits_r - active_selected_cost_bits;
                                            active_buf_sel_r <= 1'b0;
                                            current_chunk_idx_r <= '0;
                                            next_chunk_to_preload_r <=
                                                (PAGE_CHUNKS > 1) ? PAGE_IDX_W'(2) : PAGE_IDX_W'(1);

                                            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                                chunk_buf_r[0][lane] <= page_reg_r[lane];
                                                if (PAGE_CHUNKS > 1) begin
                                                    chunk_buf_r[1][lane] <= page_reg_r[CHUNK_WIDTH + lane];
                                                end else begin
                                                    chunk_buf_r[1][lane] <= '0;
                                                end
                                            end

                                            state_r <= START_SUBSTITUTE;
                                        end else begin
                                            state_r <= PACK_DICT;
                                        end
                                    end else begin
                                        state_r <= WAIT_UPDATE_DRAIN;
                                    end
                                end else begin
                                    if (next_chunk_to_preload_r < PAGE_CHUNKS) begin
                                        base_idx = next_chunk_to_preload_r * CHUNK_WIDTH;
                                        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                            chunk_buf_r[active_buf_sel_r][lane] <= page_reg_r[base_idx + lane];
                                        end
                                        next_chunk_to_preload_r <= next_chunk_to_preload_r + 1'b1;
                                    end

                                    active_buf_sel_r <= ~active_buf_sel_r;
                                    current_chunk_idx_r <= current_chunk_idx_r + 1'b1;
                                    state_r <= START_SUBSTITUTE;
                                end
                            end else begin
                                update_pre_sites <= sub_sites;
                                update_sel_seq_len <= selected_seq_len_r;

                                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                    update_pre_page[lane] <= active_chunk[lane];
                                    update_post_page[lane] <= post_sub[lane];
                                    update_post_sites[lane] <= post_sub[lane].valid &&
                                        (post_sub[lane].sym == selected_repl_sym_r);
                                end

                                state_r <= GEN_UPDATES;
                                update_start_pulse_r <= 1'b1;
                            end
                        end
                    end
                end

                WAIT_SUBSTITUTE: begin
                    state_r <= START_SUBSTITUTE;
                end

                GEN_UPDATES: begin
                    if (update_last_batch_accepted || update_done) begin
                        if (current_chunk_idx_r == PAGE_CHUNKS - 1) begin
                            state_r <= WAIT_UPDATE_DRAIN;
                        end else begin
                            int base_idx;

                            if (next_chunk_to_preload_r < PAGE_CHUNKS) begin
                                base_idx = next_chunk_to_preload_r * CHUNK_WIDTH;
                                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                    chunk_buf_r[active_buf_sel_r][lane] <= page_reg_r[base_idx + lane];
                                end
                                next_chunk_to_preload_r <= next_chunk_to_preload_r + 1'b1;
                            end

                            active_buf_sel_r <= ~active_buf_sel_r;
                            current_chunk_idx_r <= current_chunk_idx_r + 1'b1;
                            state_r <= START_SUBSTITUTE;
                        end
                    end
                end

                WAIT_UPDATE_DRAIN: begin
                    if (all_pipes_empty) begin
                        if (current_chunk_idx_r == PAGE_CHUNKS - 1) begin
                            if (force_free_prefix_substitution) begin
                                state_r <= RECORD_DICT;
                            end else if (can_substitute) begin
                                selected_seq_r <= active_selected_seq;
                                selected_seq_len_r <= active_selected_seq_len;
                                selected_repl_sym_r <= dict_code_symbol(dict_count_r);
                                dict_seqs_r[dict_count_r] <= active_selected_seq;
                                dict_lens_r[dict_count_r] <= active_selected_seq_len;
                                dict_count_r <= dict_count_r + 1'b1;
                                dict_space_bits_r <= dict_space_bits_r - active_selected_cost_bits;
                                active_buf_sel_r <= 1'b0;
                                current_chunk_idx_r <= '0;
                                next_chunk_to_preload_r <= (PAGE_CHUNKS > 1) ? PAGE_IDX_W'(2) : PAGE_IDX_W'(1);

                                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                    chunk_buf_r[0][lane] <= page_reg_r[lane];
                                    if (PAGE_CHUNKS > 1) begin
                                        chunk_buf_r[1][lane] <= page_reg_r[CHUNK_WIDTH + lane];
                                    end else begin
                                        chunk_buf_r[1][lane] <= '0;
                                    end
                                end

                                state_r <= START_SUBSTITUTE;
                            end else begin
                                state_r <= PACK_DICT;
                            end
                        end else begin
                            int base_idx;

                            if (next_chunk_to_preload_r < PAGE_CHUNKS) begin
                                base_idx = next_chunk_to_preload_r * CHUNK_WIDTH;
                                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                    chunk_buf_r[active_buf_sel_r][lane] <= page_reg_r[base_idx + lane];
                                end
                                next_chunk_to_preload_r <= next_chunk_to_preload_r + 1'b1;
                            end

                            active_buf_sel_r <= ~active_buf_sel_r;
                            current_chunk_idx_r <= current_chunk_idx_r + 1'b1;
                            state_r <= START_SUBSTITUTE;
                        end
                    end
                end

                PACK_DICT: begin
                    dict_packed_r <= dict_packed_comb;
                    dict_packed_bits_r <= dict_packed_bits_comb;
                    state_r <= DONE_STATE;
                end

                default: begin
                    state_r <= IDLE;
                end
            endcase
        end
    end
endmodule
