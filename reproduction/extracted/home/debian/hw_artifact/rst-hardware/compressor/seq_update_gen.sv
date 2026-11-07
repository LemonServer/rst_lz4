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
    output logic done
);
    logic active;
    logic [CHUNK_WIDTH-1:0] pending_pre_sites;
    logic [CHUNK_WIDTH-1:0] pending_post_sites;
    vsym_t pre_sub_r [CHUNK_WIDTH];
    vsym_t post_sub_r [CHUNK_WIDTH];
    logic [2:0] sel_seq_len_r;

    logic pre_site_valid;
    logic post_site_valid;
    logic [$clog2(CHUNK_WIDTH)-1:0] pre_site_pos;
    logic [$clog2(CHUNK_WIDTH)-1:0] post_site_pos;

    PriorityEncoder #(
        .WIDTH(CHUNK_WIDTH)
    ) pre_site_pe (
        .in(pending_pre_sites),
        .valid(pre_site_valid),
        .pos(pre_site_pos)
    );

    PriorityEncoder #(
        .WIDTH(CHUNK_WIDTH)
    ) post_site_pe (
        .in(pending_post_sites),
        .valid(post_site_valid),
        .pos(post_site_pos)
    );

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

    always_comb begin
        int pre_idx;
        int post_idx;
        int seq_len_i;
        vsym_t before_seq [4];
        vsym_t after_seq [4];
        vsym_t inc_window [9];
        vsym_t dec_window [13];

        o_valid = active && pre_site_valid && post_site_valid;

        for (int i = 0; i < PIPE_WIDTH_SEQ2; i++) o_updates_len2[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ3; i++) o_updates_len3[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ4; i++) o_updates_len4[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ5; i++) o_updates_len5[i] = '0;

        pre_idx = pre_site_pos;
        post_idx = post_site_pos;
        seq_len_i = sel_seq_len_r;

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
            o_updates_len2[idx] = make_update(3'd2, 1'b1,
                inc_window[idx + 3], inc_window[idx + 4], '0, '0, '0);
        end
        for (int idx = 0; idx < 3; idx++) begin
            o_updates_len3[idx] = make_update(3'd3, 1'b1,
                inc_window[idx + 2], inc_window[idx + 3], inc_window[idx + 4], '0, '0);
        end
        for (int idx = 0; idx < 4; idx++) begin
            o_updates_len4[idx] = make_update(3'd4, 1'b1,
                inc_window[idx + 1], inc_window[idx + 2], inc_window[idx + 3], inc_window[idx + 4], '0);
        end
        for (int idx = 0; idx < 5; idx++) begin
            o_updates_len5[idx] = make_update(3'd5, 1'b1,
                inc_window[idx + 0], inc_window[idx + 1], inc_window[idx + 2], inc_window[idx + 3], inc_window[idx + 4]);
        end

        for (int idx = 0; idx < 6; idx++) begin
            if (idx < seq_len_i + 1) begin
                o_updates_len2[idx + 2] = make_update(3'd2, 1'b0,
                    dec_window[idx + 3], dec_window[idx + 4], '0, '0, '0);
            end
        end
        for (int idx = 0; idx < 7; idx++) begin
            if (idx < seq_len_i + 2) begin
                o_updates_len3[idx + 3] = make_update(3'd3, 1'b0,
                    dec_window[idx + 2], dec_window[idx + 3], dec_window[idx + 4], '0, '0);
            end
        end
        for (int idx = 0; idx < 8; idx++) begin
            if (idx < seq_len_i + 3) begin
                o_updates_len4[idx + 4] = make_update(3'd4, 1'b0,
                    dec_window[idx + 1], dec_window[idx + 2], dec_window[idx + 3], dec_window[idx + 4], '0);
            end
        end
        for (int idx = 0; idx < 9; idx++) begin
            if (idx < seq_len_i + 4) begin
                o_updates_len5[idx + 5] = make_update(3'd5, 1'b0,
                    dec_window[idx + 0], dec_window[idx + 1], dec_window[idx + 2], dec_window[idx + 3], dec_window[idx + 4]);
            end
        end
    end

    always_ff @(posedge clk) begin
        logic [CHUNK_WIDTH-1:0] pre_clear_mask;
        logic [CHUNK_WIDTH-1:0] post_clear_mask;

        if (rst) begin
            active <= 1'b0;
            pending_pre_sites <= '0;
            pending_post_sites <= '0;
            sel_seq_len_r <= '0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !active) begin
                pre_sub_r = pre_sub;
                post_sub_r = post_sub;
                sel_seq_len_r <= sel_seq_len;

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
                pre_clear_mask = '0;
                post_clear_mask = '0;
                pre_clear_mask[pre_site_pos] = 1'b1;
                post_clear_mask[post_site_pos] = 1'b1;

                pending_pre_sites <= pending_pre_sites & ~pre_clear_mask;
                pending_post_sites <= pending_post_sites & ~post_clear_mask;

                if (((pending_pre_sites & ~pre_clear_mask) == '0) ||
                    ((pending_post_sites & ~post_clear_mask) == '0)) begin
                    active <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
endmodule
