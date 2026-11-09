`timescale 1ps / 1ps
`default_nettype none

module SeqUpdateGen
    import rst_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic i_busy,
    input  vsym_t pre_sub [CHUNK_WIDTH],
    input  vsym_t post_sub [CHUNK_WIDTH],
    input  logic [CHUNK_WIDTH-1:0] pre_sub_sites,
    input  logic [CHUNK_WIDTH-1:0] post_sub_sites,
    input  logic [2:0] sel_seq_len,
    output logic o_valid,
    output seq_update_t o_updates_len2 [PIPE_WIDTH_SEQ2],
    output seq_update_t o_updates_len3 [PIPE_WIDTH_SEQ3],
    output seq_update_t o_updates_len4 [PIPE_WIDTH_SEQ4],
    output seq_update_t o_updates_len5 [PIPE_WIDTH_SEQ5],
    output logic last_batch_accepted,
    output logic done
);
    localparam int SITES_PER_CYCLE = 2;
    localparam int SITE_WIDTH_SEQ2 = PIPE_WIDTH_SEQ2 / SITES_PER_CYCLE;
    localparam int SITE_WIDTH_SEQ3 = PIPE_WIDTH_SEQ3 / SITES_PER_CYCLE;
    localparam int SITE_WIDTH_SEQ4 = PIPE_WIDTH_SEQ4 / SITES_PER_CYCLE;
    localparam int SITE_WIDTH_SEQ5 = PIPE_WIDTH_SEQ5 / SITES_PER_CYCLE;

    logic active;
    logic [CHUNK_WIDTH-1:0] pending_pre_sites;
    logic [CHUNK_WIDTH-1:0] pending_post_sites;
    vsym_t pre_sub_r [CHUNK_WIDTH];
    vsym_t post_sub_r [CHUNK_WIDTH];
    logic [2:0] sel_seq_len_r;

    logic pre_site_valid0;
    logic pre_site_valid1;
    logic post_site_valid0;
    logic post_site_valid1;
    logic [$clog2(CHUNK_WIDTH)-1:0] pre_site_pos0;
    logic [$clog2(CHUNK_WIDTH)-1:0] pre_site_pos1;
    logic [$clog2(CHUNK_WIDTH)-1:0] post_site_pos0;
    logic [$clog2(CHUNK_WIDTH)-1:0] post_site_pos1;
    logic [CHUNK_WIDTH-1:0] pre_site_mask0;
    logic [CHUNK_WIDTH-1:0] pre_site_mask1;
    logic [CHUNK_WIDTH-1:0] post_site_mask0;
    logic [CHUNK_WIDTH-1:0] post_site_mask1;
    logic [CHUNK_WIDTH-1:0] remaining_pre_sites1;
    logic [CHUNK_WIDTH-1:0] remaining_post_sites1;
    logic [CHUNK_WIDTH-1:0] accepted_pre_mask_comb;
    logic [CHUNK_WIDTH-1:0] accepted_post_mask_comb;
    logic [CHUNK_WIDTH-1:0] remaining_pre_sites_comb;
    logic [CHUNK_WIDTH-1:0] remaining_post_sites_comb;

    function automatic logic [CHUNK_WIDTH-1:0] onehot_mask(
        input logic valid,
        input logic [$clog2(CHUNK_WIDTH)-1:0] pos
    );
        logic [CHUNK_WIDTH-1:0] mask;
        begin
            mask = '0;
            if (valid) begin
                mask[pos] = 1'b1;
            end
            return mask;
        end
    endfunction

    function automatic seq_update_t make_update(
        input logic [2:0] seq_len,
        input logic inc,
        input vsym_t s0,
        input vsym_t s1,
        input vsym_t s2,
        input vsym_t s3,
        input vsym_t s4
    );
        seq_update_t update;
        begin
            update = '0;
            update.inc = inc;
            case (seq_len)
                3'd2: begin
                    update.seq = {27'b0, s1.sym, s0.sym};
                    update.valid = s0.valid && s1.valid;
                end
                3'd3: begin
                    update.seq = {18'b0, s2.sym, s1.sym, s0.sym};
                    update.valid = s0.valid && s1.valid && s2.valid;
                end
                3'd4: begin
                    update.seq = {9'b0, s3.sym, s2.sym, s1.sym, s0.sym};
                    update.valid = s0.valid && s1.valid && s2.valid && s3.valid;
                end
                3'd5: begin
                    update.seq = {s4.sym, s3.sym, s2.sym, s1.sym, s0.sym};
                    update.valid = s0.valid && s1.valid && s2.valid && s3.valid && s4.valid;
                end
                default: begin
                    update = '0;
                end
            endcase
            return update;
        end
    endfunction

    PriorityEncoder #(
        .WIDTH(CHUNK_WIDTH)
    ) pre_site_pe0 (
        .in(pending_pre_sites),
        .valid(pre_site_valid0),
        .pos(pre_site_pos0)
    );

    PriorityEncoder #(
        .WIDTH(CHUNK_WIDTH)
    ) post_site_pe0 (
        .in(pending_post_sites),
        .valid(post_site_valid0),
        .pos(post_site_pos0)
    );

    assign pre_site_mask0 = onehot_mask(pre_site_valid0, pre_site_pos0);
    assign post_site_mask0 = onehot_mask(post_site_valid0, post_site_pos0);
    assign remaining_pre_sites1 = pending_pre_sites & ~pre_site_mask0;
    assign remaining_post_sites1 = pending_post_sites & ~post_site_mask0;

    PriorityEncoder #(
        .WIDTH(CHUNK_WIDTH)
    ) pre_site_pe1 (
        .in(remaining_pre_sites1),
        .valid(pre_site_valid1),
        .pos(pre_site_pos1)
    );

    PriorityEncoder #(
        .WIDTH(CHUNK_WIDTH)
    ) post_site_pe1 (
        .in(remaining_post_sites1),
        .valid(post_site_valid1),
        .pos(post_site_pos1)
    );

    assign pre_site_mask1 = onehot_mask(pre_site_valid1, pre_site_pos1);
    assign post_site_mask1 = onehot_mask(post_site_valid1, post_site_pos1);
    assign accepted_pre_mask_comb = pre_site_mask0 |
        ((pre_site_valid1 && post_site_valid1) ? pre_site_mask1 : '0);
    assign accepted_post_mask_comb = post_site_mask0 |
        ((pre_site_valid1 && post_site_valid1) ? post_site_mask1 : '0);
    assign remaining_pre_sites_comb = pending_pre_sites & ~accepted_pre_mask_comb;
    assign remaining_post_sites_comb = pending_post_sites & ~accepted_post_mask_comb;
    assign last_batch_accepted = o_valid && !i_busy &&
        ((remaining_pre_sites_comb == '0) || (remaining_post_sites_comb == '0));

    always_comb begin
        int seq_len_i;

        o_valid = active && pre_site_valid0 && post_site_valid0;

        for (int i = 0; i < PIPE_WIDTH_SEQ2; i++) o_updates_len2[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ3; i++) o_updates_len3[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ4; i++) o_updates_len4[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ5; i++) o_updates_len5[i] = '0;

        seq_len_i = sel_seq_len_r;

        for (int site_slot = 0; site_slot < SITES_PER_CYCLE; site_slot++) begin
            logic site_valid;
            int pre_idx;
            int post_idx;
            int seq2_base;
            int seq3_base;
            int seq4_base;
            int seq5_base;
            vsym_t before_seq [4];
            vsym_t after_seq [4];
            vsym_t inc_window [9];
            vsym_t dec_window [13];

            site_valid = 1'b0;
            pre_idx = 0;
            post_idx = 0;
            seq2_base = site_slot * SITE_WIDTH_SEQ2;
            seq3_base = site_slot * SITE_WIDTH_SEQ3;
            seq4_base = site_slot * SITE_WIDTH_SEQ4;
            seq5_base = site_slot * SITE_WIDTH_SEQ5;

            if (site_slot == 0) begin
                site_valid = pre_site_valid0 && post_site_valid0;
                pre_idx = pre_site_pos0;
                post_idx = post_site_pos0;
            end else begin
                site_valid = pre_site_valid1 && post_site_valid1;
                pre_idx = pre_site_pos1;
                post_idx = post_site_pos1;
            end

            if (site_valid) begin
                for (int i = 0; i < 4; i++) begin
                    before_seq[i] = '0;
                    after_seq[i] = '0;

                    if ((post_idx - 4 + i) >= 0 && (post_idx - 4 + i) < CHUNK_WIDTH) begin
                        before_seq[i] = post_sub_r[post_idx - 4 + i];
                    end
                    if ((pre_idx + seq_len_i + i) >= 0 && (pre_idx + seq_len_i + i) < CHUNK_WIDTH) begin
                        after_seq[i] = pre_sub_r[pre_idx + seq_len_i + i];
                    end
                end

                for (int i = 0; i < 9; i++) begin
                    if (i < 4) begin
                        inc_window[i] = before_seq[i];
                    end else if (i == 4) begin
                        inc_window[i] = post_sub_r[post_idx];
                    end else begin
                        inc_window[i] = after_seq[i - 5];
                    end
                end

                for (int i = 0; i < 13; i++) begin
                    if (i < 4) begin
                        dec_window[i] = before_seq[i];
                    end else if (i < 9) begin
                        if (i < seq_len_i + 4) begin
                            dec_window[i] = pre_sub_r[pre_idx + i - 4];
                        end else begin
                            dec_window[i] = after_seq[i - seq_len_i - 4];
                        end
                    end else begin
                        if (i - seq_len_i < 8) begin
                            dec_window[i] = after_seq[i - seq_len_i - 4];
                        end else begin
                            dec_window[i] = '0;
                        end
                    end
                end

                for (int idx = 0; idx < 2; idx++) begin
                    o_updates_len2[seq2_base + idx] = make_update(3'd2, 1'b1,
                        inc_window[idx + 3], inc_window[idx + 4], '0, '0, '0);
                end
                for (int idx = 0; idx < 3; idx++) begin
                    o_updates_len3[seq3_base + idx] = make_update(3'd3, 1'b1,
                        inc_window[idx + 2], inc_window[idx + 3], inc_window[idx + 4], '0, '0);
                end
                for (int idx = 0; idx < 4; idx++) begin
                    o_updates_len4[seq4_base + idx] = make_update(3'd4, 1'b1,
                        inc_window[idx + 1], inc_window[idx + 2], inc_window[idx + 3], inc_window[idx + 4], '0);
                end
                for (int idx = 0; idx < 5; idx++) begin
                    o_updates_len5[seq5_base + idx] = make_update(3'd5, 1'b1,
                        inc_window[idx + 0], inc_window[idx + 1], inc_window[idx + 2], inc_window[idx + 3], inc_window[idx + 4]);
                end

                for (int idx = 0; idx < 6; idx++) begin
                    if (idx < seq_len_i + 1) begin
                        o_updates_len2[seq2_base + 2 + idx] = make_update(3'd2, 1'b0,
                            dec_window[idx + 3], dec_window[idx + 4], '0, '0, '0);
                    end
                end
                for (int idx = 0; idx < 7; idx++) begin
                    if (idx < seq_len_i + 2) begin
                        o_updates_len3[seq3_base + 3 + idx] = make_update(3'd3, 1'b0,
                            dec_window[idx + 2], dec_window[idx + 3], dec_window[idx + 4], '0, '0);
                    end
                end
                for (int idx = 0; idx < 8; idx++) begin
                    if (idx < seq_len_i + 3) begin
                        o_updates_len4[seq4_base + 4 + idx] = make_update(3'd4, 1'b0,
                            dec_window[idx + 1], dec_window[idx + 2], dec_window[idx + 3], dec_window[idx + 4], '0);
                    end
                end
                for (int idx = 0; idx < 9; idx++) begin
                    if (idx < seq_len_i + 4) begin
                        o_updates_len5[seq5_base + 5 + idx] = make_update(3'd5, 1'b0,
                            dec_window[idx + 0], dec_window[idx + 1], dec_window[idx + 2], dec_window[idx + 3], dec_window[idx + 4]);
                    end
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        logic [CHUNK_WIDTH-1:0] accepted_pre_mask;
        logic [CHUNK_WIDTH-1:0] accepted_post_mask;
        logic [CHUNK_WIDTH-1:0] remaining_pre_sites;
        logic [CHUNK_WIDTH-1:0] remaining_post_sites;

        if (rst) begin
            active <= 1'b0;
            pending_pre_sites <= '0;
            pending_post_sites <= '0;
            sel_seq_len_r <= '0;
            done <= 1'b0;
            for (int idx = 0; idx < CHUNK_WIDTH; idx++) begin
                pre_sub_r[idx] <= '0;
                post_sub_r[idx] <= '0;
            end
        end else begin
            done <= 1'b0;

            if (start && !active) begin
                sel_seq_len_r <= sel_seq_len;
                for (int idx = 0; idx < CHUNK_WIDTH; idx++) begin
                    pre_sub_r[idx] <= pre_sub[idx];
                    post_sub_r[idx] <= post_sub[idx];
                end

                if ((pre_sub_sites == '0) || (post_sub_sites == '0)) begin
                    active <= 1'b0;
                    pending_pre_sites <= '0;
                    pending_post_sites <= '0;
                    done <= 1'b1;
                end else begin
                    active <= 1'b1;
                    pending_pre_sites <= pre_sub_sites;
                    pending_post_sites <= post_sub_sites;
                end
            end else if (o_valid && !i_busy) begin
                accepted_pre_mask = accepted_pre_mask_comb;
                accepted_post_mask = accepted_post_mask_comb;
                remaining_pre_sites = remaining_pre_sites_comb;
                remaining_post_sites = remaining_post_sites_comb;

                pending_pre_sites <= remaining_pre_sites;
                pending_post_sites <= remaining_post_sites;

                if ((remaining_pre_sites == '0) || (remaining_post_sites == '0)) begin
                    active <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
endmodule
