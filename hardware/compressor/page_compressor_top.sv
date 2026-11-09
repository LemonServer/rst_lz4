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
    seq_update_t init_updates_len2 [PIPE_WIDTH_SEQ2];
    seq_update_t init_updates_len3 [PIPE_WIDTH_SEQ3];
    seq_update_t init_updates_len4 [PIPE_WIDTH_SEQ4];
    seq_update_t init_updates_len5 [PIPE_WIDTH_SEQ5];

    logic update_i_busy;
    logic update_o_valid;
    logic update_done;
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
    logic can_substitute;
    dict_packed_t dict_packed_comb;
    dict_bit_count_t dict_packed_bits_comb;

    assign init_i_busy = pipe_busy_seq2 | pipe_busy_seq3 | pipe_busy_seq4 | pipe_busy_seq5;
    assign update_i_busy = init_i_busy;
    assign all_pipes_empty = pipe_empty_seq2 && pipe_empty_seq3 && pipe_empty_seq4 && pipe_empty_seq5;
    assign query_top = (state_r == SELECT_TOP);
    assign selected_utility_num = utility_numerator(top_result.seq_len, top_result.count);
    assign selected_cost_bits = dict_entry_cost_bits(top_result.seq_len);
    assign mfr_i_valid = (state_r == START_SUBSTITUTE);
    assign can_substitute = top_valid &&
        top_result.valid &&
        (selected_utility_num > 0) &&
        (dict_space_bits_r >= selected_cost_bits) &&
        (dict_count_r < MAX_DICT_ENTRIES);
    assign done = (state_r == DONE_STATE);

    always_comb begin
        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
            active_chunk[lane] = chunk_buf_r[active_buf_sel_r][lane];
        end
    end

    InitSeqCountGen init_gen (
        .clk(clk),
        .rst(rst),
        .start(init_start_pulse_r),
        .i_busy(init_i_busy),
        .data(active_chunk),
        .o_valid(init_o_valid),
        .o_updates_len2(init_updates_len2),
        .o_updates_len3(init_updates_len3),
        .o_updates_len4(init_updates_len4),
        .o_updates_len5(init_updates_len5),
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
                        state_r <= INIT_COUNT;
                        active_buf_sel_r <= 1'b0;
                        current_chunk_idx_r <= '0;
                        next_chunk_to_preload_r <= (PAGE_CHUNKS > 1) ? PAGE_IDX_W'(2) : PAGE_IDX_W'(1);
                        dict_count_r <= '0;
                        dict_packed_r <= '0;
                        dict_packed_bits_r <= '0;
                        dict_space_bits_r <= MEMORY_BLOCKS * 64 * 8 - 6;
                        init_start_pulse_r <= 1'b1;
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
                    if (init_done) begin
                        state_r <= WAIT_INIT_DRAIN;
                    end
                end

                WAIT_INIT_DRAIN: begin
                    if (all_pipes_empty) begin
                        if (current_chunk_idx_r == PAGE_CHUNKS - 1) begin
                            state_r <= SELECT_TOP;
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
                            init_start_pulse_r <= 1'b1;
                            state_r <= INIT_COUNT;
                        end
                    end
                end

                SELECT_TOP: begin
                    state_r <= WAIT_TOP_RESULT;
                end

                WAIT_TOP_RESULT: begin
                    state_r <= WAIT_TOP_SCORE;
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
                    selected_seq_r <= top_result.seq;
                    selected_seq_len_r <= top_result.seq_len;
                    selected_repl_sym_r <= dict_code_symbol(dict_count_r);
                    dict_seqs_r[dict_count_r] <= top_result.seq;
                    dict_lens_r[dict_count_r] <= top_result.seq_len;
                    dict_count_r <= dict_count_r + 1'b1;
                    dict_space_bits_r <= dict_space_bits_r - selected_cost_bits;
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
                    state_r <= WAIT_SUBSTITUTE;
                end

                WAIT_SUBSTITUTE: begin
                    int base_idx;

                    if (mfr_o_valid) begin
                        base_idx = current_chunk_idx_r * CHUNK_WIDTH;
                        update_pre_sites <= sub_sites;
                        update_sel_seq_len <= selected_seq_len_r;

                        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                            update_pre_page[lane] <= active_chunk[lane];
                            update_post_page[lane] <= post_sub[lane];
                            chunk_buf_r[active_buf_sel_r][lane] <= post_sub[lane];
                            page_reg_r[base_idx + lane] <= post_sub[lane];
                            update_post_sites[lane] <= post_sub[lane].valid &&
                                (post_sub[lane].sym == selected_repl_sym_r);
                        end

                        state_r <= GEN_UPDATES;
                        update_start_pulse_r <= 1'b1;
                    end
                end

                GEN_UPDATES: begin
                    if (update_done) begin
                        state_r <= WAIT_UPDATE_DRAIN;
                    end
                end

                WAIT_UPDATE_DRAIN: begin
                    if (all_pipes_empty) begin
                        if (current_chunk_idx_r == PAGE_CHUNKS - 1) begin
                            state_r <= SELECT_TOP;
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
