`timescale 1ps / 1ps
`default_nettype none

module ExperimentalPageDecompressorTop
    import rst_pkg::*;
    import experimental_huffman_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic [EXPERIMENTAL_DICT_BITS_MAX-1:0] dict_bits,
    input  dict_bit_count_t dict_bit_count,
    input  logic [EXPERIMENTAL_CHUNK_BITS_MAX-1:0] compressed_chunk_bits [PAGE_CHUNKS],
    input  logic [EXPERIMENTAL_CHUNK_BIT_COUNT_W-1:0] compressed_chunk_bit_counts [PAGE_CHUNKS],
    output symbol_t decompressed_out [PAGE_WIDTH],
    output logic done,
    output logic error
);
    typedef enum logic [1:0] {
        IDLE,
        RUN,
        DONE_STATE,
        ERROR_STATE
    } state_t;

    localparam int CHUNK_IDX_W = (PAGE_CHUNKS > 1) ? $clog2(PAGE_CHUNKS) : 1;
    localparam int OUT_COUNT_W = $clog2(CHUNK_WIDTH + 1);
    localparam int SEG_DONE_COUNT_W = $clog2(DECOMP_LIFOS + 1);

    state_t state_r;

    seq_t dict_seqs_dec [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens_dec [MAX_DICT_ENTRIES];
    dict_count_t dict_count_dec;
    logic dict_parse_ok;

    vsym_t chunk_compressed_in [PAGE_CHUNKS][CHUNK_WIDTH];
    logic [OUT_COUNT_W-1:0] chunk_token_count_dbg [PAGE_CHUNKS];
    logic chunk_parse_ok [PAGE_CHUNKS];
    logic all_chunks_parse_ok;

    vsym_t chunk_segment_inputs [PAGE_CHUNKS][DECOMP_LIFOS][MAX_DECOMP_SEG_TOKENS];
    logic [OUT_COUNT_W-1:0] chunk_segment_token_counts_dbg [PAGE_CHUNKS][DECOMP_LIFOS];

    logic lane_launch_pending_r [DECOMP_LIFOS];
    logic lane_inflight_r [DECOMP_LIFOS];
    logic [CHUNK_IDX_W-1:0] lane_chunk_idx_r [DECOMP_LIFOS];
    vsym_t lane_inputs_r [DECOMP_LIFOS][MAX_DECOMP_SEG_TOKENS];
    symbol_t lane_outputs [DECOMP_LIFOS][CHUNK_WIDTH];
    logic [OUT_COUNT_W-1:0] lane_out_counts [DECOMP_LIFOS];
    logic lane_done [DECOMP_LIFOS];

    symbol_t segment_outputs_r [PAGE_CHUNKS][DECOMP_LIFOS][CHUNK_WIDTH];
    logic [OUT_COUNT_W-1:0] segment_out_counts_r [PAGE_CHUNKS][DECOMP_LIFOS];
    logic [SEG_DONE_COUNT_W-1:0] chunk_segment_done_counts_r [PAGE_CHUNKS];
    symbol_t decompressed_out_r [PAGE_WIDTH];

    logic all_lanes_idle;

    ExperimentalDictDecoder dict_decoder (
        .dict_bits(dict_bits),
        .dict_bit_count(dict_bit_count),
        .dict_seqs(dict_seqs_dec),
        .dict_lens(dict_lens_dec),
        .dict_count(dict_count_dec),
        .parse_ok(dict_parse_ok)
    );

    for (genvar chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin : gen_chunk_decoders
        ExperimentalChunkDecoder chunk_decoder (
            .chunk_bits(compressed_chunk_bits[chunk]),
            .chunk_bit_count(compressed_chunk_bit_counts[chunk]),
            .compressed_out(chunk_compressed_in[chunk]),
            .token_count(chunk_token_count_dbg[chunk]),
            .parse_ok(chunk_parse_ok[chunk])
        );
    end

    // Pre-slice every decoded chunk into the same fixed contiguous segments that the
    // chunk-local decompressor already uses, then let each lane walk its segment across
    // the full page without waiting for the slowest lane of each chunk.
    always_comb begin
        for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
            int valid_count_i;
            int base_seg_len;
            int remainder;
            int read_idx;

            valid_count_i = int'(chunk_token_count_dbg[chunk]);
            base_seg_len = valid_count_i / DECOMP_LIFOS;
            remainder = valid_count_i % DECOMP_LIFOS;
            read_idx = 0;

            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                int seg_len;

                seg_len = base_seg_len + ((seg < remainder) ? 1 : 0);
                chunk_segment_token_counts_dbg[chunk][seg] = seg_len[OUT_COUNT_W-1:0];

                for (int lane = 0; lane < MAX_DECOMP_SEG_TOKENS; lane++) begin
                    chunk_segment_inputs[chunk][seg][lane] = '0;
                    if ((lane < seg_len) && ((read_idx + lane) < CHUNK_WIDTH)) begin
                        chunk_segment_inputs[chunk][seg][lane] =
                            chunk_compressed_in[chunk][read_idx + lane];
                    end
                end

                read_idx += seg_len;
            end
        end
    end

    always_comb begin
        all_chunks_parse_ok = 1'b1;
        all_lanes_idle = 1'b1;

        for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
            all_chunks_parse_ok &= chunk_parse_ok[chunk];
        end

        for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
            all_lanes_idle &= !lane_launch_pending_r[seg] && !lane_inflight_r[seg];
        end
    end

    for (genvar seg = 0; seg < DECOMP_LIFOS; seg++) begin : gen_lifos
        LifoExpander lifo_expander (
            .clk(clk),
            .rst(rst),
            .start(lane_launch_pending_r[seg]),
            .compressed_in(lane_inputs_r[seg]),
            .dict_seqs(dict_seqs_dec),
            .dict_lens(dict_lens_dec),
            .dict_count(dict_count_dec),
            .decompressed_out(lane_outputs[seg]),
            .out_count(lane_out_counts[seg]),
            .done(lane_done[seg])
        );
    end

    assign done = (state_r == DONE_STATE) || (state_r == ERROR_STATE);
    assign error = (state_r == ERROR_STATE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r <= IDLE;

            for (int page_lane = 0; page_lane < PAGE_WIDTH; page_lane++) begin
                decompressed_out_r[page_lane] <= '0;
            end

            for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                chunk_segment_done_counts_r[chunk] <= '0;
                for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                    segment_out_counts_r[chunk][seg] <= '0;
                    for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                        segment_outputs_r[chunk][seg][lane] <= '0;
                    end
                end
            end

            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                lane_launch_pending_r[seg] <= 1'b0;
                lane_inflight_r[seg] <= 1'b0;
                lane_chunk_idx_r[seg] <= '0;
                for (int lane = 0; lane < MAX_DECOMP_SEG_TOKENS; lane++) begin
                    lane_inputs_r[seg][lane] <= '0;
                end
            end
        end else begin
            case (state_r)
                IDLE,
                DONE_STATE,
                ERROR_STATE: begin
                    if (start) begin
                        for (int page_lane = 0; page_lane < PAGE_WIDTH; page_lane++) begin
                            decompressed_out_r[page_lane] <= '0;
                        end

                        for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                            chunk_segment_done_counts_r[chunk] <= '0;
                            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                                segment_out_counts_r[chunk][seg] <= '0;
                                for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                    segment_outputs_r[chunk][seg][lane] <= '0;
                                end
                            end
                        end

                        for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                            lane_inflight_r[seg] <= 1'b0;
                            lane_chunk_idx_r[seg] <= '0;
                            for (int lane = 0; lane < MAX_DECOMP_SEG_TOKENS; lane++) begin
                                lane_inputs_r[seg][lane] <= chunk_segment_inputs[0][seg][lane];
                            end
                        end

                        if (!dict_parse_ok || !all_chunks_parse_ok) begin
                            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                                lane_launch_pending_r[seg] <= 1'b0;
                            end
                            state_r <= ERROR_STATE;
                        end else begin
                            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                                lane_launch_pending_r[seg] <= 1'b1;
                            end
                            state_r <= RUN;
                        end
                    end
                end

                RUN: begin
                    logic lane_completed_i [DECOMP_LIFOS];
                    int lane_completed_chunk_i [DECOMP_LIFOS];
                    int chunk_complete_add_i [PAGE_CHUNKS];

                    for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                        lane_completed_i[seg] = 1'b0;
                        lane_completed_chunk_i[seg] = 0;
                    end
                    for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                        chunk_complete_add_i[chunk] = 0;
                    end

                    for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                        if (lane_launch_pending_r[seg]) begin
                            lane_launch_pending_r[seg] <= 1'b0;
                            lane_inflight_r[seg] <= 1'b1;
                        end else if (lane_inflight_r[seg] && lane_done[seg]) begin
                            int chunk_idx_i;

                            chunk_idx_i = int'(lane_chunk_idx_r[seg]);
                            lane_completed_i[seg] = 1'b1;
                            lane_completed_chunk_i[seg] = chunk_idx_i;
                            chunk_complete_add_i[chunk_idx_i]++;

                            segment_out_counts_r[chunk_idx_i][seg] <= lane_out_counts[seg];
                            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                segment_outputs_r[chunk_idx_i][seg][lane] <= lane_outputs[seg][lane];
                            end
                            lane_inflight_r[seg] <= 1'b0;

                            if (chunk_idx_i == (PAGE_CHUNKS - 1)) begin
                                lane_launch_pending_r[seg] <= 1'b0;
                            end else begin
                                lane_chunk_idx_r[seg] <= CHUNK_IDX_W'(chunk_idx_i + 1);
                                for (int lane = 0; lane < MAX_DECOMP_SEG_TOKENS; lane++) begin
                                    lane_inputs_r[seg][lane]
                                        <= chunk_segment_inputs[chunk_idx_i + 1][seg][lane];
                                end
                                lane_launch_pending_r[seg] <= 1'b1;
                            end
                        end
                    end

                    for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                        if (chunk_complete_add_i[chunk] != 0) begin
                            if ((int'(chunk_segment_done_counts_r[chunk]) + chunk_complete_add_i[chunk])
                                >= DECOMP_LIFOS) begin
                                int page_base_idx_i;
                                int write_idx_i;

                                page_base_idx_i = chunk * CHUNK_WIDTH;
                                write_idx_i = 0;
                                for (int prior_seg = 0; prior_seg < DECOMP_LIFOS; prior_seg++) begin
                                    int seg_out_count_i;
                                    logic seg_completed_now_i;

                                    seg_completed_now_i =
                                        lane_completed_i[prior_seg] &&
                                        (lane_completed_chunk_i[prior_seg] == chunk);

                                    if (seg_completed_now_i) begin
                                        seg_out_count_i = int'(lane_out_counts[prior_seg]);
                                    end else begin
                                        seg_out_count_i =
                                            int'(segment_out_counts_r[chunk][prior_seg]);
                                    end

                                    for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                                        symbol_t sym_i;

                                        if (seg_completed_now_i) begin
                                            sym_i = lane_outputs[prior_seg][lane];
                                        end else begin
                                            sym_i = segment_outputs_r[chunk][prior_seg][lane];
                                        end

                                        if ((lane < seg_out_count_i) &&
                                            ((page_base_idx_i + write_idx_i + lane) < PAGE_WIDTH)) begin
                                            decompressed_out_r[page_base_idx_i + write_idx_i + lane]
                                                <= sym_i;
                                        end
                                    end

                                    write_idx_i += seg_out_count_i;
                                end
                            end

                            chunk_segment_done_counts_r[chunk]
                                <= chunk_segment_done_counts_r[chunk]
                                 + SEG_DONE_COUNT_W'(chunk_complete_add_i[chunk]);
                        end
                    end

                    if (all_lanes_idle) begin
                        state_r <= DONE_STATE;
                    end
                end

                default: begin
                    state_r <= IDLE;
                end
            endcase
        end
    end

    always_comb begin
        for (int lane = 0; lane < PAGE_WIDTH; lane++) begin
            decompressed_out[lane] = decompressed_out_r[lane];
        end
    end
endmodule
