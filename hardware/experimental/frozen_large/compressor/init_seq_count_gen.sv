`timescale 1ps / 1ps
`default_nettype none

module InitSeqCountGen
    import rst_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic i_busy,
    input  vsym_t data [CHUNK_WIDTH],
    output logic o_valid,
    output seq_update_t o_updates_len2 [PIPE_WIDTH_SEQ2],
    output seq_update_t o_updates_len3 [PIPE_WIDTH_SEQ3],
    output seq_update_t o_updates_len4 [PIPE_WIDTH_SEQ4],
    output seq_update_t o_updates_len5 [PIPE_WIDTH_SEQ5],
    output logic last_batch_accepted,
    output logic done
);
    logic active;
    logic [$clog2(CHUNK_WIDTH + 1)-1:0] cursor;

    function automatic seq_update_t make_update(
        input  logic [$clog2(CHUNK_WIDTH + 1)-1:0] base,
        input  logic [2:0] seq_len
    );
        seq_update_t update;
        begin
            update = '0;
            if (base + seq_len <= CHUNK_WIDTH) begin
                update.valid = 1'b1;
                update.inc = 1'b1;
                for (int j = 0; j < MAX_SEQ_LEN; j++) begin
                    if (j < seq_len) begin
                        update.seq[j] = data[base + j].sym;
                        update.valid &= data[base + j].valid;
                    end
                end
            end
            return update;
        end
    endfunction

    always_comb begin
        logic [$clog2(CHUNK_WIDTH + 1)-1:0] base;

        for (int i = 0; i < PIPE_WIDTH_SEQ2; i++) o_updates_len2[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ3; i++) o_updates_len3[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ4; i++) o_updates_len4[i] = '0;
        for (int i = 0; i < PIPE_WIDTH_SEQ5; i++) o_updates_len5[i] = '0;

        if (active) begin
            for (int i = 0; i < INIT_COUNT_POSITIONS_PER_CYCLE; i++) begin
                base = cursor + i;
                if (base < CHUNK_WIDTH) begin
                    o_updates_len2[i] = make_update(base, 3'd2);
                    o_updates_len3[i] = make_update(base, 3'd3);
                    o_updates_len4[i] = make_update(base, 3'd4);
                    o_updates_len5[i] = make_update(base, 3'd5);
                end
            end
        end
    end

    assign last_batch_accepted = active && !i_busy &&
        (cursor + INIT_COUNT_POSITIONS_PER_CYCLE >= CHUNK_WIDTH);

    always_ff @(posedge clk) begin
        if (rst) begin
            active <= 1'b0;
            cursor <= '0;
            o_valid <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !active) begin
                active <= 1'b1;
                cursor <= '0;
                o_valid <= 1'b1;
            end else if (active) begin
                o_valid <= 1'b1;
                if (!i_busy) begin
                    if (cursor + INIT_COUNT_POSITIONS_PER_CYCLE >= CHUNK_WIDTH) begin
                        if (start) begin
                            cursor <= '0;
                            o_valid <= 1'b1;
                        end else begin
                            active <= 1'b0;
                            o_valid <= 1'b0;
                            done <= 1'b1;
                        end
                    end else begin
                        cursor <= cursor + INIT_COUNT_POSITIONS_PER_CYCLE;
                    end
                end
            end else begin
                o_valid <= 1'b0;
            end
        end
    end
endmodule
