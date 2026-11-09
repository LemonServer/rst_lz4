`timescale 1ps / 1ps
`default_nettype none

module tb_ExperimentalPageDecompressorTop;
    import rst_pkg::*;
    import experimental_huffman_pkg::*;

    localparam int CLK_HALF = 5;
    localparam int TIMEOUT_CYCLES = 200000;

    logic clk;
    logic rst;
    logic start;
    logic [EXPERIMENTAL_DICT_BITS_MAX-1:0] dict_bits;
    dict_bit_count_t dict_bit_count;
    logic [EXPERIMENTAL_CHUNK_BITS_MAX-1:0] compressed_chunk_bits [PAGE_CHUNKS];
    logic [EXPERIMENTAL_CHUNK_BIT_COUNT_W-1:0] compressed_chunk_bit_counts [PAGE_CHUNKS];
    logic [7:0] expected_page [0:PAGE_WIDTH-1];
    symbol_t decompressed_out [PAGE_WIDTH];
    logic done;
    logic error;

    ExperimentalPageDecompressorTop dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .dict_bits(dict_bits),
        .dict_bit_count(dict_bit_count),
        .compressed_chunk_bits(compressed_chunk_bits),
        .compressed_chunk_bit_counts(compressed_chunk_bit_counts),
        .decompressed_out(decompressed_out),
        .done(done),
        .error(error)
    );

    always #(CLK_HALF) clk = ~clk;

    task automatic clear_inputs;
        begin
            start = 1'b0;
            dict_bits = '0;
            dict_bit_count = '0;
            for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                compressed_chunk_bits[chunk] = '0;
                compressed_chunk_bit_counts[chunk] = '0;
            end
            for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
                expected_page[idx] = '0;
            end
        end
    endtask

    task automatic reset_dut;
        begin
            clear_inputs();
            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic pulse_start;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic load_stimulus(input string stim_path);
        integer fd;
        int rc;
        int dict_bits_i;
        int chunk_bits_i;
        begin
            fd = $fopen(stim_path, "r");
            if (fd == 0) begin
                $fatal(1, "failed to open stimulus file %s", stim_path);
            end

            rc = $fscanf(fd, "%d\n", dict_bits_i);
            if (rc != 1) begin
                $fatal(1, "failed to read dict_bit_count from %s", stim_path);
            end
            dict_bit_count = dict_bit_count_t'(dict_bits_i);

            rc = $fscanf(fd, "%h\n", dict_bits);
            if (rc != 1) begin
                $fatal(1, "failed to read dict_bits from %s", stim_path);
            end

            for (int chunk = 0; chunk < PAGE_CHUNKS; chunk++) begin
                rc = $fscanf(fd, "%d\n", chunk_bits_i);
                if (rc != 1) begin
                    $fatal(1, "failed to read chunk_bit_count[%0d] from %s", chunk, stim_path);
                end
                compressed_chunk_bit_counts[chunk] =
                    EXPERIMENTAL_CHUNK_BIT_COUNT_W'(chunk_bits_i);

                rc = $fscanf(fd, "%h\n", compressed_chunk_bits[chunk]);
                if (rc != 1) begin
                    $fatal(1, "failed to read chunk_bits[%0d] from %s", chunk, stim_path);
                end
            end

            $fclose(fd);
        end
    endtask

    task automatic wait_done;
        int cycles;
        begin
            cycles = 0;
            while (!done && cycles < TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycles++;
            end
            if (!done) begin
                $fatal(1, "timed out waiting for page decompressor");
            end
        end
    endtask

    initial begin
        string stim_path;
        string expected_path;

        clk = 1'b0;
        reset_dut();

        if (!$value$plusargs("STIM_FILE=%s", stim_path)) begin
            $fatal(1, "missing +STIM_FILE=... plusarg");
        end
        if (!$value$plusargs("EXPECTED_FILE=%s", expected_path)) begin
            $fatal(1, "missing +EXPECTED_FILE=... plusarg");
        end

        load_stimulus(stim_path);
        $readmemh(expected_path, expected_page);
        pulse_start();
        wait_done();

        if (error) begin
            $fatal(1, "page decompressor flagged a parse error");
        end

        for (int idx = 0; idx < PAGE_WIDTH; idx++) begin
            symbol_t want;

            want = symbol_t'(expected_page[idx]);
            if (decompressed_out[idx] !== want) begin
                $display("dict_count=%0d dict34=%0h,%0h dict35=%0h,%0h",
                    dut.dict_count_dec,
                    dut.dict_seqs_dec[34][0], dut.dict_seqs_dec[34][1],
                    dut.dict_seqs_dec[35][0], dut.dict_seqs_dec[35][1]);
                $fatal(1, "page symbol mismatch idx=%0d got=%0h expected=%0h",
                    idx, decompressed_out[idx], want);
            end
        end

        $display("[sv-decompressor] PASS dict_count=%0d dict_bits=%0d",
            dut.dict_count_dec, dict_bit_count);
        $finish;
    end
endmodule
