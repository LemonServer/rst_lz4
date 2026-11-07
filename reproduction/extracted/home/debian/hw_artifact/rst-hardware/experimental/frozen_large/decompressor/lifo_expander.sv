`timescale 1ps / 1ps
`default_nettype none

module LifoExpander
    import rst_pkg::*;
#(
    parameter int COMPRESSED_INPUT_CAP = MAX_DECOMP_SEG_TOKENS
)
(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  vsym_t compressed_in [COMPRESSED_INPUT_CAP],
    input  seq_t dict_seqs [MAX_DICT_ENTRIES],
    input  logic [2:0] dict_lens [MAX_DICT_ENTRIES],
    input  dict_count_t dict_count,
    output symbol_t decompressed_out [CHUNK_WIDTH],
    output logic [$clog2(CHUNK_WIDTH + 1)-1:0] out_count,
    output logic done
);
    // The logical stack is interleaved across 10 compact per-bank stacks.
    // With this banking:
    //   - produced positions 0..9 map to distinct banks
    //   - consumed positions 0 and 1 map to distinct banks
    // so each bank only ever sees hold, pop, push, or head overwrite.
    localparam int STACK_DEPTH = MAX_LIFO_STACK_SYMBOLS;
    localparam int STACK_BANKS = 10;
    localparam int BANK_DEPTH = (STACK_DEPTH + STACK_BANKS - 1) / STACK_BANKS;
    localparam int STACK_PTR_W = $clog2(STACK_DEPTH + 1);
    localparam int OUT_PTR_W = $clog2(CHUNK_WIDTH + 1);
    localparam int BANK_COUNT_W = $clog2(BANK_DEPTH + 1);
    localparam int PHASE_W = (STACK_BANKS > 1) ? $clog2(STACK_BANKS) : 1;
    localparam logic [STACK_BANKS-1:0] PHASE0_OH = {{(STACK_BANKS - 1){1'b0}}, 1'b1};

    typedef enum logic [1:0] {
        IDLE,
        RUN,
        DONE_STATE
    } state_t;

    state_t state_r;
    state_t state_n;
    logic [STACK_PTR_W-1:0] sp_r;
    logic [STACK_PTR_W-1:0] sp_n;
    logic [OUT_PTR_W-1:0] out_count_r;
    logic [OUT_PTR_W-1:0] out_count_n;
    logic [STACK_BANKS-1:0] top_phase_oh_r;
    logic [STACK_BANKS-1:0] top_phase_oh_n;
    logic [PHASE_W-1:0] top_phase_r;
    logic [BANK_COUNT_W-1:0] bank_counts_r [0:STACK_BANKS-1];
    logic [BANK_COUNT_W-1:0] bank_counts_n [0:STACK_BANKS-1];
    symbol_t bank_mem_r [0:STACK_BANKS-1][0:BANK_DEPTH-1];
    symbol_t bank_mem_n [0:STACK_BANKS-1][0:BANK_DEPTH-1];
    logic [STACK_BANKS-1:0] bank_pop;
    logic [STACK_BANKS-1:0] bank_push;
    symbol_t bank_push_sym [0:STACK_BANKS-1];
    symbol_t out_mem_r [0:CHUNK_WIDTH-1];
    symbol_t out_mem_n [0:CHUNK_WIDTH-1];
    symbol_t ordered_syms [0:COMPRESSED_INPUT_CAP-1];

    function automatic logic sym_is_code(input symbol_t sym);
        sym_is_code = sym[8];
    endfunction

    function automatic logic [PHASE_W-1:0] wrap_inc_bank(input logic [PHASE_W-1:0] bank);
        if (bank == PHASE_W'(STACK_BANKS - 1)) begin
            wrap_inc_bank = '0;
        end else begin
            wrap_inc_bank = PHASE_W'(bank + 1'b1);
        end
    endfunction

    function automatic logic [PHASE_W-1:0] wrap_dec_bank(input logic [PHASE_W-1:0] bank);
        if (bank == '0) begin
            wrap_dec_bank = PHASE_W'(STACK_BANKS - 1);
        end else begin
            wrap_dec_bank = PHASE_W'(bank - 1'b1);
        end
    endfunction

    function automatic logic [STACK_BANKS-1:0] rotate_inc_phase_oh(
        input logic [STACK_BANKS-1:0] phase_oh
    );
        rotate_inc_phase_oh = {phase_oh[STACK_BANKS-2:0], phase_oh[STACK_BANKS-1]};
    endfunction

    function automatic logic [STACK_BANKS-1:0] rotate_dec_phase_oh(
        input logic [STACK_BANKS-1:0] phase_oh
    );
        rotate_dec_phase_oh = {phase_oh[0], phase_oh[STACK_BANKS-1:1]};
    endfunction

    function automatic logic [PHASE_W-1:0] phase_oh_to_bank(
        input logic [STACK_BANKS-1:0] phase_oh
    );
        phase_oh_to_bank = '0;
        for (int bank = 0; bank < STACK_BANKS; bank++) begin
            if (phase_oh[bank]) begin
                phase_oh_to_bank = PHASE_W'(bank);
            end
        end
    endfunction

    always_comb begin
        state_n = state_r;
        sp_n = sp_r;
        out_count_n = out_count_r;
        top_phase_oh_n = top_phase_oh_r;

        for (int bank = 0; bank < STACK_BANKS; bank++) begin
            bank_push_sym[bank] = '0;
            bank_counts_n[bank] = bank_counts_r[bank];
            for (int row = 0; row < BANK_DEPTH; row++) begin
                bank_mem_n[bank][row] = bank_mem_r[bank][row];
            end
        end
        bank_pop = '0;
        bank_push = '0;
        for (int bank = 0; bank < STACK_BANKS; bank++) begin
            bank_push_sym[bank] = '0;
        end

        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
            out_mem_n[lane] = out_mem_r[lane];
        end

        for (int idx = 0; idx < COMPRESSED_INPUT_CAP; idx++) begin
            ordered_syms[idx] = '0;
        end

        case (state_r)
            IDLE,
            DONE_STATE: begin
                if (start) begin
                    int valid_count;
                    logic [PHASE_W-1:0] load_bank_cursor;
                    int load_occurrence;

                    valid_count = 0;
                    state_n = DONE_STATE;
                    sp_n = '0;
                    out_count_n = '0;
                    top_phase_oh_n = PHASE0_OH;

                    for (int bank = 0; bank < STACK_BANKS; bank++) begin
                        bank_counts_n[bank] = '0;
                        for (int row = 0; row < BANK_DEPTH; row++) begin
                            bank_mem_n[bank][row] = '0;
                        end
                    end

                    for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                        out_mem_n[lane] = '0;
                    end

                    for (int idx = 0; idx < COMPRESSED_INPUT_CAP; idx++) begin
                        if (compressed_in[idx].valid) begin
                            ordered_syms[valid_count] = compressed_in[idx].sym;
                            valid_count++;
                        end
                    end

                    // synopsys translate_off
                    if (valid_count > COMPRESSED_INPUT_CAP) begin
                        $fatal(1, "LifoExpander input overflow: valid_count=%0d cap=%0d",
                            valid_count, COMPRESSED_INPUT_CAP);
                    end
                    // synopsys translate_on

                    load_bank_cursor = '0;
                    load_occurrence = 0;
                    for (int logical_pos = 0; logical_pos < COMPRESSED_INPUT_CAP; logical_pos++) begin
                        if (logical_pos < valid_count) begin
                            // synopsys translate_off
                            if (load_occurrence >= BANK_DEPTH) begin
                                $fatal(1, "LifoExpander bank load overflow: bank=%0d occurrence=%0d depth=%0d",
                                    load_bank_cursor, load_occurrence, BANK_DEPTH);
                            end
                            // synopsys translate_on

                            bank_mem_n[load_bank_cursor][load_occurrence] = ordered_syms[logical_pos];
                            bank_counts_n[load_bank_cursor] = BANK_COUNT_W'(load_occurrence + 1);

                            if (load_bank_cursor == PHASE_W'(STACK_BANKS - 1)) begin
                                load_bank_cursor = '0;
                                load_occurrence++;
                            end else begin
                                load_bank_cursor = wrap_inc_bank(load_bank_cursor);
                            end
                        end
                    end

                    sp_n = STACK_PTR_W'(valid_count);
                    if (valid_count != 0) begin
                        state_n = RUN;
                    end
                end
            end

            RUN: begin
                if (sp_r == '0) begin
                    state_n = DONE_STATE;
                    sp_n = '0;
                end else begin
                    int consumed;
                    int prod_len;
                    int next_sp_i;
                    int temp_out_count;
                    int top_count;
                    int below_count;
                    int top_code_idx;
                    int below_code_idx;
                    int top_seq_len;
                    int below_seq_len;
                    logic [STACK_BANKS-1:0] below_phase_oh;
                    logic [STACK_BANKS-1:0] prod_phase_cursor_oh;
                    logic [STACK_BANKS-1:0] top_phase_i_next_oh;
                    symbol_t top_sym;
                    symbol_t below_sym;
                    symbol_t prod_syms [0:(2 * MAX_SEQ_LEN) - 1];
                    logic top_is_code;
                    logic below_is_code;
                    logic dual_issue;

                    for (int idx = 0; idx < (2 * MAX_SEQ_LEN); idx++) begin
                        prod_syms[idx] = '0;
                    end

                    top_count = 0;
                    top_sym = '0;
                    for (int bank = 0; bank < STACK_BANKS; bank++) begin
                        if (top_phase_oh_r[bank]) begin
                            top_count = bank_counts_r[bank];
                            top_sym = bank_mem_r[bank][0];
                        end
                    end
                    // synopsys translate_off
                    if (top_count == 0) begin
                        $fatal(1, "LifoExpander top bank underflow: bank=%0d sp=%0d phase=%0d",
                            top_phase_r, sp_r, top_phase_r);
                    end
                    // synopsys translate_on

                    top_is_code = sym_is_code(top_sym);

                    below_sym = '0;
                    below_is_code = 1'b0;
                    dual_issue = 1'b0;
                    below_phase_oh = rotate_inc_phase_oh(top_phase_oh_r);
                    below_count = 0;
                    top_code_idx = 0;
                    below_code_idx = 0;
                    top_seq_len = 0;
                    below_seq_len = 0;
                    temp_out_count = out_count_r;
                    prod_len = 0;

                    if (sp_r > 1) begin
                        for (int bank = 0; bank < STACK_BANKS; bank++) begin
                            if (below_phase_oh[bank]) begin
                                below_count = bank_counts_r[bank];
                                below_sym = bank_mem_r[bank][0];
                            end
                        end
                        // synopsys translate_off
                        if (below_count == 0) begin
                            $fatal(1, "LifoExpander below bank underflow: bank=%0d sp=%0d phase=%0d",
                                phase_oh_to_bank(below_phase_oh), sp_r, top_phase_r);
                        end
                        // synopsys translate_on

                        below_is_code = sym_is_code(below_sym);
                        dual_issue = !(top_is_code && !below_is_code);
                    end

                    consumed = (sp_r > 1) ? (dual_issue ? 2 : 1) : 1;

                    if (!top_is_code && temp_out_count < CHUNK_WIDTH) begin
                        out_mem_n[temp_out_count] = top_sym;
                        temp_out_count++;
                    end

                    if (dual_issue && !below_is_code && temp_out_count < CHUNK_WIDTH) begin
                        out_mem_n[temp_out_count] = below_sym;
                        temp_out_count++;
                    end

                    if (top_is_code) begin
                        top_code_idx = top_sym[7:0];
                        if (top_code_idx < MAX_DICT_ENTRIES && top_code_idx < dict_count) begin
                            top_seq_len = dict_lens[top_code_idx];
                        end
                        for (int j = 0; j < MAX_SEQ_LEN; j++) begin
                            if (j < top_seq_len) begin
                                prod_syms[prod_len + j] = dict_seqs[top_code_idx][j];
                            end
                        end
                        prod_len += top_seq_len;
                    end

                    if (dual_issue && below_is_code) begin
                        below_code_idx = below_sym[7:0];
                        if (below_code_idx < MAX_DICT_ENTRIES && below_code_idx < dict_count) begin
                            below_seq_len = dict_lens[below_code_idx];
                        end
                        for (int j = 0; j < MAX_SEQ_LEN; j++) begin
                            if (j < below_seq_len) begin
                                prod_syms[prod_len + j] = dict_seqs[below_code_idx][j];
                            end
                        end
                        prod_len += below_seq_len;
                    end

                    top_phase_i_next_oh = top_phase_oh_r;
                    for (int step = 0; step < 2; step++) begin
                        if (step < consumed) begin
                            top_phase_i_next_oh = rotate_inc_phase_oh(top_phase_i_next_oh);
                        end
                    end
                    for (int step = 0; step < (2 * MAX_SEQ_LEN); step++) begin
                        if (step < prod_len) begin
                            top_phase_i_next_oh = rotate_dec_phase_oh(top_phase_i_next_oh);
                        end
                    end

                    bank_pop = top_phase_oh_r;
                    if (consumed == 2) begin
                        bank_pop |= below_phase_oh;
                    end

                    prod_phase_cursor_oh = top_phase_i_next_oh;
                    for (int idx = 0; idx < (2 * MAX_SEQ_LEN); idx++) begin
                        if (idx < prod_len) begin
                            for (int bank = 0; bank < STACK_BANKS; bank++) begin
                                if (prod_phase_cursor_oh[bank]) begin
                                    bank_push[bank] = 1'b1;
                                    bank_push_sym[bank] = prod_syms[idx];
                                end
                            end
                            prod_phase_cursor_oh = rotate_inc_phase_oh(prod_phase_cursor_oh);
                        end
                    end

                    for (int bank = 0; bank < STACK_BANKS; bank++) begin
                        int count_i;
                        int next_count_i;

                        count_i = bank_counts_r[bank];
                        next_count_i = count_i + (bank_push[bank] ? 1 : 0) - (bank_pop[bank] ? 1 : 0);

                        // synopsys translate_off
                        if (bank_pop[bank] && (count_i == 0)) begin
                            $fatal(1, "LifoExpander bank pop underflow: bank=%0d count=%0d",
                                bank, count_i);
                        end
                        if ((next_count_i < 0) || (next_count_i > BANK_DEPTH)) begin
                            $fatal(1, "LifoExpander bank count out of range: bank=%0d next_count=%0d depth=%0d",
                                bank, next_count_i, BANK_DEPTH);
                        end
                        // synopsys translate_on

                        bank_counts_n[bank] = BANK_COUNT_W'(next_count_i);
                        for (int row = 0; row < BANK_DEPTH; row++) begin
                            bank_mem_n[bank][row] = '0;

                            if (bank_pop[bank] && bank_push[bank]) begin
                                if (row == 0) begin
                                    bank_mem_n[bank][row] = bank_push_sym[bank];
                                end else if (row < count_i) begin
                                    bank_mem_n[bank][row] = bank_mem_r[bank][row];
                                end
                            end else if (bank_pop[bank]) begin
                                if ((row + 1) < count_i) begin
                                    bank_mem_n[bank][row] = bank_mem_r[bank][row + 1];
                                end
                            end else if (bank_push[bank]) begin
                                if (row == 0) begin
                                    bank_mem_n[bank][row] = bank_push_sym[bank];
                                end else if (row <= count_i) begin
                                    bank_mem_n[bank][row] = bank_mem_r[bank][row - 1];
                                end
                            end else if (row < count_i) begin
                                bank_mem_n[bank][row] = bank_mem_r[bank][row];
                            end
                        end
                    end

                    next_sp_i = int'(sp_r) - consumed + prod_len;

                    // synopsys translate_off
                    if (next_sp_i > STACK_DEPTH) begin
                        $fatal(1, "LifoExpander logical stack overflow: next_sp=%0d depth=%0d",
                            next_sp_i, STACK_DEPTH);
                    end
                    // synopsys translate_on

                    sp_n = STACK_PTR_W'(next_sp_i);
                    out_count_n = OUT_PTR_W'(temp_out_count);
                    top_phase_oh_n = top_phase_i_next_oh;
                    if (next_sp_i == 0) begin
                        state_n = DONE_STATE;
                    end
                end
            end

            default: begin
                state_n = IDLE;
                sp_n = '0;
                out_count_n = '0;
                top_phase_oh_n = PHASE0_OH;
                for (int bank = 0; bank < STACK_BANKS; bank++) begin
                    bank_counts_n[bank] = '0;
                    for (int row = 0; row < BANK_DEPTH; row++) begin
                        bank_mem_n[bank][row] = '0;
                    end
                end
                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                    out_mem_n[lane] = '0;
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r <= IDLE;
            sp_r <= '0;
            out_count_r <= '0;
            top_phase_oh_r <= PHASE0_OH;

            for (int bank = 0; bank < STACK_BANKS; bank++) begin
                bank_counts_r[bank] <= '0;
                for (int row = 0; row < BANK_DEPTH; row++) begin
                    bank_mem_r[bank][row] <= '0;
                end
            end

            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                out_mem_r[lane] <= '0;
            end
        end else begin
            state_r <= state_n;
            sp_r <= sp_n;
            out_count_r <= out_count_n;
            top_phase_oh_r <= top_phase_oh_n;

            for (int bank = 0; bank < STACK_BANKS; bank++) begin
                bank_counts_r[bank] <= bank_counts_n[bank];
                for (int row = 0; row < BANK_DEPTH; row++) begin
                    bank_mem_r[bank][row] <= bank_mem_n[bank][row];
                end
            end

            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                out_mem_r[lane] <= out_mem_n[lane];
            end
        end
    end

    always_comb begin
        top_phase_r = '0;
        for (int bank = 0; bank < STACK_BANKS; bank++) begin
            if (top_phase_oh_r[bank]) begin
                top_phase_r = PHASE_W'(bank);
            end
        end

        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
            decompressed_out[lane] = out_mem_r[lane];
        end
        out_count = out_count_r;
        done = (state_r == DONE_STATE);
    end

    // synopsys translate_off
    symbol_t stack_mem_r [0:STACK_DEPTH-1];
    always_comb begin
        for (int idx = 0; idx < STACK_DEPTH; idx++) begin
            stack_mem_r[idx] = '0;
        end

        for (int logical_pos = 0; logical_pos < sp_r; logical_pos++) begin
            int dbg_bank;
            int dbg_occurrence;
            int dbg_count;

            dbg_bank = (top_phase_r + logical_pos) % STACK_BANKS;
            dbg_occurrence = logical_pos / STACK_BANKS;
            dbg_count = bank_counts_r[dbg_bank];

            if (dbg_occurrence < dbg_count) begin
                stack_mem_r[sp_r - 1 - logical_pos] =
                    bank_mem_r[dbg_bank][dbg_occurrence];
            end
        end
    end
    // synopsys translate_on
endmodule
