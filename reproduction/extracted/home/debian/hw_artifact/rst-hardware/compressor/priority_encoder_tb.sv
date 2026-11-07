`timescale 1ps / 1ps
`default_nettype none

module tb_ProgrammablePE;
    import rst_pkg::*;

    logic clk;
    logic start;
    logic next;
    logic rst;
    logic [CHUNK_WIDTH-1:0] in;
    logic valid;
    logic [$clog2(CHUNK_WIDTH)-1:0] pos;
    logic done;

    ProgrammablePE dut (
        .clk(clk),
        .start(start),
        .next(next),
        .rst(rst),
        .in(in),
        .valid(valid),
        .pos(pos),
        .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        start = 1'b0;
        next = 1'b0;
        rst = 1'b1;
        in = '0;
        in[3] = 1'b1;
        in[7] = 1'b1;
        in[11] = 1'b1;

        #12;
        rst = 1'b0;
        start = 1'b1;
        #10;
        start = 1'b0;

        #10;
        if (!valid || pos !== 3) begin
            $fatal(1, "first priority position mismatch");
        end

        next = 1'b1;
        #10;
        next = 1'b0;
        #10;
        if (!valid || pos !== 7) begin
            $fatal(1, "second priority position mismatch");
        end

        next = 1'b1;
        #10;
        next = 1'b0;
        #10;
        if (!valid || pos !== 11) begin
            $fatal(1, "third priority position mismatch");
        end

        next = 1'b1;
        #10;
        next = 1'b0;
        #10;
        if (!done) begin
            $fatal(1, "programmable priority encoder never reached done");
        end

        $finish;
    end
endmodule
