`timescale 1ps / 1ps
`default_nettype none

module FIFO
    import rst_pkg::*;
#(
    parameter int PIPE_WIDTH = PIPE_WIDTH_SEQ2,
    parameter int DEPTH = FIFO_DEPTH
) (
    input  logic clk,
    input  logic rst,
    input  agg_update_t i_batch [PIPE_WIDTH],
    input  logic [$clog2(PIPE_WIDTH + 1)-1:0] i_count,
    input  logic i_valid,
    output logic i_busy,
    output logic [$clog2(DEPTH + 1)-1:0] free_slots,
    output agg_update_t o_data,
    output logic o_valid,
    input  logic o_busy,
    output logic empty
);
    localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    agg_update_t storage [DEPTH];
    logic [PTR_W-1:0] rptr;
    logic [PTR_W-1:0] wptr;
    logic [$clog2(DEPTH + 1)-1:0] occupancy;

    function automatic logic [PTR_W-1:0] wrap_ptr_add(
        input logic [PTR_W-1:0] base,
        input int unsigned offset
    );
        int unsigned sum;
        begin
            if (DEPTH <= 1) begin
                wrap_ptr_add = '0;
            end else begin
                sum = base + offset;
                if (sum >= DEPTH) begin
                    sum -= DEPTH;
                end
                wrap_ptr_add = PTR_W'(sum);
            end
        end
    endfunction

    assign empty = (occupancy == 0);
    assign o_valid = !empty;
    assign i_busy = (i_count != 0) && ((occupancy + i_count) > DEPTH);
    assign free_slots = $clog2(DEPTH + 1)'(DEPTH - occupancy);

    always_comb begin
        if (empty) begin
            o_data = '0;
        end else begin
            o_data = storage[rptr];
        end
    end

    always_ff @(posedge clk) begin
        logic do_push;
        logic do_pop;

        do_push = i_valid && !i_busy && (i_count != 0);
        do_pop = o_valid && !o_busy;

        if (rst) begin
            rptr <= '0;
            wptr <= '0;
            occupancy <= '0;
        end else begin
            if (do_push) begin
                for (int i = 0; i < PIPE_WIDTH; i++) begin
                    if (i < i_count) begin
                        storage[wrap_ptr_add(wptr, i)] <= i_batch[i];
                    end
                end
                wptr <= wrap_ptr_add(wptr, i_count);
            end

            if (do_pop) begin
                rptr <= wrap_ptr_add(rptr, 1);
            end

            case ({do_push, do_pop})
                2'b10: occupancy <= occupancy + i_count;
                2'b01: occupancy <= occupancy - 1'b1;
                2'b11: occupancy <= occupancy + i_count - 1'b1;
                default: occupancy <= occupancy;
            endcase
        end
    end
endmodule
