`timescale 1ps / 1ps
`default_nettype none

module DecompressorTop
    import rst_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  vsym_t compressed_in [CHUNK_WIDTH],
    input  dict_packed_t dict_packed,
    output symbol_t decompressed_out [CHUNK_WIDTH],
    output logic done
);
    typedef enum logic [2:0] {
        IDLE,
        COMPACT_TOKENS,
        PREP_SEGMENTS,
        LAUNCH,
        WAIT_DONE,
        DONE_STATE
    } state_t;

    localparam int OUT_COUNT_W = $clog2(CHUNK_WIDTH + 1);
    localparam int SEG_INPUT_CAP = MAX_DECOMP_SEG_TOKENS;
    localparam int COMPACT_BLOCK_SIZE = 8;
    localparam int COMPACT_BLOCKS = (CHUNK_WIDTH + COMPACT_BLOCK_SIZE - 1) / COMPACT_BLOCK_SIZE;
    localparam int COMPACT_BLOCK_COUNT_W = $clog2(COMPACT_BLOCK_SIZE + 1);

    state_t state_r;
    vsym_t ordered_tokens_r [CHUNK_WIDTH];
    vsym_t compact_block_tokens [COMPACT_BLOCKS][COMPACT_BLOCK_SIZE];
    logic [COMPACT_BLOCK_COUNT_W-1:0] compact_block_counts [COMPACT_BLOCKS];
    vsym_t compact_block_tokens_r [COMPACT_BLOCKS][COMPACT_BLOCK_SIZE];
    logic [COMPACT_BLOCK_COUNT_W-1:0] compact_block_counts_r [COMPACT_BLOCKS];
    vsym_t ordered_tokens_merge [CHUNK_WIDTH];
    vsym_t segmented_inputs_launch [DECOMP_LIFOS][SEG_INPUT_CAP];
    vsym_t segmented_inputs_r [DECOMP_LIFOS][SEG_INPUT_CAP];
    symbol_t segmented_outputs [DECOMP_LIFOS][CHUNK_WIDTH];
    logic [OUT_COUNT_W-1:0] segmented_out_counts [DECOMP_LIFOS];
    logic segmented_done [DECOMP_LIFOS];
    seq_t dict_seqs_dec [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens_dec [MAX_DICT_ENTRIES];
    dict_count_t dict_count_dec;
    seq_t dict_seqs_r [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens_r [MAX_DICT_ENTRIES];
    dict_count_t dict_count_r;
    logic [OUT_COUNT_W-1:0] valid_count_r;
    dict_bit_count_t dict_packed_bits_dbg;
    logic lifo_start;

    logic [OUT_COUNT_W-1:0] valid_count_dbg;
    logic [OUT_COUNT_W-1:0] segment_comp_offsets_dbg [DECOMP_LIFOS];
    logic [OUT_COUNT_W-1:0] segment_comp_counts_dbg [DECOMP_LIFOS];
    logic [OUT_COUNT_W-1:0] total_out_count_dbg;
    logic [OUT_COUNT_W-1:0] valid_count_merge;
    logic all_segmented_done;

    DictDeserializer dict_deserializer (
        .dict_packed(dict_packed),
        .dict_seqs(dict_seqs_dec),
        .dict_lens(dict_lens_dec),
        .dict_count(dict_count_dec),
        .dict_packed_bits(dict_packed_bits_dbg)
    );

    assign lifo_start = (state_r == LAUNCH);

    always_comb begin
        all_segmented_done = 1'b1;
        for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
            all_segmented_done &= segmented_done[seg];
        end
    end

    always_comb begin
        int valid_count_i;
        int base_seg_len;
        int remainder;
        int read_idx;

        valid_count_i = 0;
        base_seg_len = 0;
        remainder = 0;
        read_idx = 0;

        for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
            segment_comp_offsets_dbg[seg] = '0;
            segment_comp_counts_dbg[seg] = '0;
        end

        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
            if (compressed_in[lane].valid) begin
                valid_count_i++;
            end
        end

        valid_count_dbg = valid_count_i[OUT_COUNT_W-1:0];
        base_seg_len = valid_count_i / DECOMP_LIFOS;
        remainder = valid_count_i % DECOMP_LIFOS;

        for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
            int seg_len;

            seg_len = base_seg_len + ((seg < remainder) ? 1 : 0);
            segment_comp_offsets_dbg[seg] = read_idx[OUT_COUNT_W-1:0];
            segment_comp_counts_dbg[seg] = seg_len[OUT_COUNT_W-1:0];

            read_idx += seg_len;
        end
    end

    // Compact valid input tokens in small fixed blocks first, then merge those
    // pre-compacted blocks on the next cycle. This cuts the long ripple path
    // from compressed_in valid bits into ordered_tokens_r.
    always_comb begin
        for (int block = 0; block < COMPACT_BLOCKS; block++) begin
            int block_count_i;
            int block_base;

            block_count_i = 0;
            block_base = block * COMPACT_BLOCK_SIZE;

            for (int lane = 0; lane < COMPACT_BLOCK_SIZE; lane++) begin
                compact_block_tokens[block][lane] = '0;
            end

            for (int lane = 0; lane < COMPACT_BLOCK_SIZE; lane++) begin
                if (((block_base + lane) < CHUNK_WIDTH) && compressed_in[block_base + lane].valid) begin
                    compact_block_tokens[block][block_count_i] = compressed_in[block_base + lane];
                    block_count_i++;
                end
            end

            compact_block_counts[block] = COMPACT_BLOCK_COUNT_W'(block_count_i);
        end
    end

    always_comb begin
        int write_idx;

        write_idx = 0;
        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
            ordered_tokens_merge[lane] = '0;
        end

        for (int block = 0; block < COMPACT_BLOCKS; block++) begin
            int block_count_i;

            block_count_i = compact_block_counts_r[block];
            for (int lane = 0; lane < COMPACT_BLOCK_SIZE; lane++) begin
                if ((lane < block_count_i) && ((write_idx + lane) < CHUNK_WIDTH)) begin
                    ordered_tokens_merge[write_idx + lane] = compact_block_tokens_r[block][lane];
                end
            end

            write_idx += block_count_i;
        end

        valid_count_merge = write_idx[OUT_COUNT_W-1:0];
    end

    always_comb begin
        int valid_count_i;
        int base_seg_len;
        int remainder;
        int read_idx;

        valid_count_i = valid_count_r;
        base_seg_len = 0;
        remainder = 0;
        read_idx = 0;

        for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
            for (int lane = 0; lane < SEG_INPUT_CAP; lane++) begin
                segmented_inputs_launch[seg][lane] = '0;
            end
        end

        base_seg_len = valid_count_i / DECOMP_LIFOS;
        remainder = valid_count_i % DECOMP_LIFOS;

        for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
            int seg_len;

            seg_len = base_seg_len + ((seg < remainder) ? 1 : 0);

            // synopsys translate_off
            if (seg_len > SEG_INPUT_CAP) begin
                $fatal(1, "DecompressorTop segment input overflow: seg=%0d len=%0d cap=%0d",
                    seg, seg_len, SEG_INPUT_CAP);
            end
            // synopsys translate_on

            for (int lane = 0; lane < SEG_INPUT_CAP; lane++) begin
                if ((lane < seg_len) && ((read_idx + lane) < CHUNK_WIDTH)) begin
                    segmented_inputs_launch[seg][lane] = ordered_tokens_r[read_idx + lane];
                end
            end

            read_idx += seg_len;
        end
    end

    for (genvar seg = 0; seg < DECOMP_LIFOS; seg++) begin : gen_lifos
        LifoExpander lifo_expander (
            .clk(clk),
            .rst(rst),
            .start(lifo_start),
            .compressed_in(segmented_inputs_r[seg]),
            .dict_seqs(dict_seqs_r),
            .dict_lens(dict_lens_r),
            .dict_count(dict_count_r),
            .decompressed_out(segmented_outputs[seg]),
            .out_count(segmented_out_counts[seg]),
            .done(segmented_done[seg])
        );
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r <= IDLE;
            dict_count_r <= '0;
            valid_count_r <= '0;
            for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                dict_seqs_r[idx] <= '0;
                dict_lens_r[idx] <= '0;
            end
            for (int block = 0; block < COMPACT_BLOCKS; block++) begin
                compact_block_counts_r[block] <= '0;
                for (int lane = 0; lane < COMPACT_BLOCK_SIZE; lane++) begin
                    compact_block_tokens_r[block][lane] <= '0;
                end
            end
            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                ordered_tokens_r[lane] <= '0;
            end
            for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                for (int lane = 0; lane < SEG_INPUT_CAP; lane++) begin
                    segmented_inputs_r[seg][lane] <= '0;
                end
            end
        end else begin
            case (state_r)
                IDLE,
                DONE_STATE: begin
                    if (start) begin
                        state_r <= COMPACT_TOKENS;
                        dict_count_r <= dict_count_dec;
                        for (int idx = 0; idx < MAX_DICT_ENTRIES; idx++) begin
                            dict_seqs_r[idx] <= dict_seqs_dec[idx];
                            dict_lens_r[idx] <= dict_lens_dec[idx];
                        end
                        valid_count_r <= '0;
                        for (int block = 0; block < COMPACT_BLOCKS; block++) begin
                            compact_block_counts_r[block] <= compact_block_counts[block];
                            for (int lane = 0; lane < COMPACT_BLOCK_SIZE; lane++) begin
                                compact_block_tokens_r[block][lane] <= compact_block_tokens[block][lane];
                            end
                        end
                    end
                end

                COMPACT_TOKENS: begin
                    state_r <= PREP_SEGMENTS;
                    valid_count_r <= valid_count_merge;
                    for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                        ordered_tokens_r[lane] <= ordered_tokens_merge[lane];
                    end
                end

                PREP_SEGMENTS: begin
                    state_r <= LAUNCH;
                    for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
                        for (int lane = 0; lane < SEG_INPUT_CAP; lane++) begin
                            segmented_inputs_r[seg][lane] <= segmented_inputs_launch[seg][lane];
                        end
                    end
                end

                LAUNCH: begin
                    state_r <= WAIT_DONE;
                end

                WAIT_DONE: begin
                    if (all_segmented_done) begin
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
        int write_idx;

        write_idx = 0;
        done = (state_r == DONE_STATE);

        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
            decompressed_out[lane] = '0;
        end

        for (int seg = 0; seg < DECOMP_LIFOS; seg++) begin
            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                if ((lane < segmented_out_counts[seg]) && ((write_idx + lane) < CHUNK_WIDTH)) begin
                    decompressed_out[write_idx + lane] = segmented_outputs[seg][lane];
                end
            end

            write_idx += segmented_out_counts[seg];
        end

        total_out_count_dbg = write_idx[OUT_COUNT_W-1:0];
    end
endmodule
