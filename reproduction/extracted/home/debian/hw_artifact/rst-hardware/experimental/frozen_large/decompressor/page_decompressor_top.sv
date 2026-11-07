`timescale 1ps / 1ps
`default_nettype none

module PageDecompressorTop
    import rst_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  vsym_t compressed_in [PAGE_WIDTH],
    input  dict_packed_t dict_packed,
    output symbol_t decompressed_out [PAGE_WIDTH],
    output logic done
);
    typedef enum logic [2:0] {
        IDLE,
        RESET_CHUNK,
        START_CHUNK,
        WAIT_CHUNK,
        DONE_STATE
    } state_t;

    state_t state_r;
    logic [$clog2(PAGE_CHUNKS)-1:0] chunk_idx_r;

    vsym_t chunk_compressed_in_r [CHUNK_WIDTH];
    symbol_t decompressed_out_r [PAGE_WIDTH];

    logic chunk_rst;
    logic chunk_start;
    symbol_t chunk_decompressed_out [CHUNK_WIDTH];
    logic chunk_done;

    assign chunk_rst = rst | (state_r == RESET_CHUNK);
    assign chunk_start = (state_r == START_CHUNK);
    assign done = (state_r == DONE_STATE);

    DecompressorTop chunk_decompressor (
        .clk(clk),
        .rst(chunk_rst),
        .start(chunk_start),
        .compressed_in(chunk_compressed_in_r),
        .dict_packed(dict_packed),
        .decompressed_out(chunk_decompressed_out),
        .done(chunk_done)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r <= IDLE;
            chunk_idx_r <= '0;

            for (int i = 0; i < PAGE_WIDTH; i++) begin
                decompressed_out_r[i] <= '0;
            end

            for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                chunk_compressed_in_r[lane] <= '0;
            end
        end else begin
            case (state_r)
                IDLE,
                DONE_STATE: begin
                    if (start) begin
                        state_r <= RESET_CHUNK;
                        chunk_idx_r <= '0;

                        for (int i = 0; i < PAGE_WIDTH; i++) begin
                            decompressed_out_r[i] <= '0;
                        end

                        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                            chunk_compressed_in_r[lane] <= '0;
                        end
                    end
                end

                RESET_CHUNK: begin
                    int base_idx;

                    base_idx = chunk_idx_r * CHUNK_WIDTH;
                    for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                        chunk_compressed_in_r[lane] <= compressed_in[base_idx + lane];
                    end

                    state_r <= START_CHUNK;
                end

                START_CHUNK: begin
                    state_r <= WAIT_CHUNK;
                end

                WAIT_CHUNK: begin
                    if (chunk_done) begin
                        int base_idx;

                        base_idx = chunk_idx_r * CHUNK_WIDTH;
                        for (int lane = 0; lane < CHUNK_WIDTH; lane++) begin
                            decompressed_out_r[base_idx + lane] <= chunk_decompressed_out[lane];
                        end

                        if (chunk_idx_r == PAGE_CHUNKS - 1) begin
                            state_r <= DONE_STATE;
                        end else begin
                            chunk_idx_r <= chunk_idx_r + 1'b1;
                            state_r <= RESET_CHUNK;
                        end
                    end
                end

                default: begin
                    state_r <= IDLE;
                    chunk_idx_r <= '0;
                end
            endcase
        end
    end

    always_comb begin
        for (int i = 0; i < PAGE_WIDTH; i++) begin
            decompressed_out[i] = decompressed_out_r[i];
        end
    end
endmodule
