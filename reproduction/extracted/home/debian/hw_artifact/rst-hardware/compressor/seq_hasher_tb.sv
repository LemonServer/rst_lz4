`timescale 1ps / 1ps
`default_nettype none

module tb_SeqHasher;
    import rst_pkg::*;

    localparam int W8 = PIPE_WIDTH_SEQ2;
    localparam int W10 = PIPE_WIDTH_SEQ3;
    localparam int W12 = PIPE_WIDTH_SEQ4;
    localparam int W14 = PIPE_WIDTH_SEQ5;

    function automatic logic [15:0] crc(input logic [42:0] data);
        logic [15:0] hash_value;
        begin
            hash_value[0]  = data[0]  ^ data[4]  ^ data[8]  ^ data[11] ^ data[12] ^ data[19] ^ data[20] ^ data[22] ^ data[26] ^ data[27] ^ data[28] ^ data[32] ^ data[33] ^ data[35] ^ data[42];
            hash_value[1]  = data[1]  ^ data[5]  ^ data[9]  ^ data[12] ^ data[13] ^ data[20] ^ data[21] ^ data[23] ^ data[27] ^ data[28] ^ data[29] ^ data[33] ^ data[34] ^ data[36];
            hash_value[2]  = data[2]  ^ data[6]  ^ data[10] ^ data[13] ^ data[14] ^ data[21] ^ data[22] ^ data[24] ^ data[28] ^ data[29] ^ data[30] ^ data[34] ^ data[35] ^ data[37];
            hash_value[3]  = data[3]  ^ data[7]  ^ data[11] ^ data[14] ^ data[15] ^ data[22] ^ data[23] ^ data[25] ^ data[29] ^ data[30] ^ data[31] ^ data[35] ^ data[36] ^ data[38];
            hash_value[4]  = data[4]  ^ data[8]  ^ data[12] ^ data[15] ^ data[16] ^ data[23] ^ data[24] ^ data[26] ^ data[30] ^ data[31] ^ data[32] ^ data[36] ^ data[37] ^ data[39];
            hash_value[5]  = data[0]  ^ data[4]  ^ data[5]  ^ data[8]  ^ data[9]  ^ data[11] ^ data[12] ^ data[13] ^ data[16] ^ data[17] ^ data[19] ^ data[20] ^ data[22] ^ data[24] ^ data[25] ^ data[26] ^ data[28] ^ data[31] ^ data[35] ^ data[37] ^ data[38] ^ data[40] ^ data[42];
            hash_value[6]  = data[1]  ^ data[5]  ^ data[6]  ^ data[9]  ^ data[10] ^ data[12] ^ data[13] ^ data[14] ^ data[17] ^ data[18] ^ data[20] ^ data[21] ^ data[23] ^ data[25] ^ data[26] ^ data[27] ^ data[29] ^ data[32] ^ data[36] ^ data[38] ^ data[39] ^ data[41];
            hash_value[7]  = data[2]  ^ data[6]  ^ data[7]  ^ data[10] ^ data[11] ^ data[13] ^ data[14] ^ data[15] ^ data[18] ^ data[19] ^ data[21] ^ data[22] ^ data[24] ^ data[26] ^ data[27] ^ data[28] ^ data[30] ^ data[33] ^ data[37] ^ data[39] ^ data[40] ^ data[42];
            hash_value[8]  = data[3]  ^ data[7]  ^ data[8]  ^ data[11] ^ data[12] ^ data[14] ^ data[15] ^ data[16] ^ data[19] ^ data[20] ^ data[22] ^ data[23] ^ data[25] ^ data[27] ^ data[28] ^ data[29] ^ data[31] ^ data[34] ^ data[38] ^ data[40] ^ data[41];
            hash_value[9]  = data[4]  ^ data[8]  ^ data[9]  ^ data[12] ^ data[13] ^ data[15] ^ data[16] ^ data[17] ^ data[20] ^ data[21] ^ data[23] ^ data[24] ^ data[26] ^ data[28] ^ data[29] ^ data[30] ^ data[32] ^ data[35] ^ data[39] ^ data[41] ^ data[42];
            hash_value[10] = data[5]  ^ data[9]  ^ data[10] ^ data[13] ^ data[14] ^ data[16] ^ data[17] ^ data[18] ^ data[21] ^ data[22] ^ data[24] ^ data[25] ^ data[27] ^ data[29] ^ data[30] ^ data[31] ^ data[33] ^ data[36] ^ data[40] ^ data[42];
            hash_value[11] = data[6]  ^ data[10] ^ data[11] ^ data[14] ^ data[15] ^ data[17] ^ data[18] ^ data[19] ^ data[22] ^ data[23] ^ data[25] ^ data[26] ^ data[28] ^ data[30] ^ data[31] ^ data[32] ^ data[34] ^ data[37] ^ data[41];
            hash_value[12] = data[0]  ^ data[4]  ^ data[7]  ^ data[8]  ^ data[15] ^ data[16] ^ data[18] ^ data[22] ^ data[23] ^ data[24] ^ data[28] ^ data[29] ^ data[31] ^ data[38];
            hash_value[13] = data[1]  ^ data[5]  ^ data[8]  ^ data[9]  ^ data[16] ^ data[17] ^ data[19] ^ data[23] ^ data[24] ^ data[25] ^ data[29] ^ data[30] ^ data[32] ^ data[39];
            hash_value[14] = data[2]  ^ data[6]  ^ data[9]  ^ data[10] ^ data[17] ^ data[18] ^ data[20] ^ data[24] ^ data[25] ^ data[26] ^ data[30] ^ data[31] ^ data[33] ^ data[40];
            hash_value[15] = data[3]  ^ data[7]  ^ data[10] ^ data[11] ^ data[18] ^ data[19] ^ data[21] ^ data[25] ^ data[26] ^ data[27] ^ data[31] ^ data[32] ^ data[34] ^ data[41];
            return hash_value;
        end
    endfunction

    function automatic logic [42:0] seq_payload(
        input seq_t seq,
        input int pipe_width
    );
        logic [42:0] payload;
        begin
            payload = {
                seq[4][7:0],
                seq[3][7:0],
                seq[2][7:0],
                seq[1][7:0],
                seq[0][7:0],
                seq_len_from_pipe_width(pipe_width)
            };
            return payload;
        end
    endfunction

    task automatic seed_update(
        output seq_update_t update,
        input seq_t seq,
        input logic inc
    );
        begin
            update = '0;
            update.valid = 1'b1;
            update.inc = inc;
            update.seq = seq;
        end
    endtask

    task automatic check_case(
        input string label,
        input int pipe_width,
        input int num_banks,
        input int count,
        input seq_update_t input_updates[],
        input hashed_update_t output_updates[]
    );
        begin
            $display("%s:", label);
            for (int i = 0; i < count; i++) begin
                logic [15:0] hash_value;

                hash_value = crc(seq_payload(input_updates[i].seq, pipe_width));
                $display("  in[%0d] hash=%0h bank=%0d set=%0d inc=%0b", i,
                    hash_value, output_updates[i].bank_idx, output_updates[i].set_idx, output_updates[i].inc);
                if (!output_updates[i].valid) begin
                    $fatal(1, "%s[%0d] is invalid", label, i);
                end
                if (output_updates[i].bank_idx !== (hash_value % num_banks)) begin
                    $fatal(1, "%s[%0d] bank_idx mismatch", label, i);
                end
                if (output_updates[i].set_idx !== ((hash_value / num_banks) % SETS_PER_BANK)) begin
                    $fatal(1, "%s[%0d] set_idx mismatch", label, i);
                end
                if (output_updates[i].seq !== input_updates[i].seq || output_updates[i].inc !== input_updates[i].inc) begin
                    $fatal(1, "%s[%0d] payload mismatch", label, i);
                end
            end
            for (int i = count; i < pipe_width; i++) begin
                if (output_updates[i].valid) begin
                    $fatal(1, "%s[%0d] should be invalid", label, i);
                end
            end
        end
    endtask

    seq_update_t i_updates8 [W8];
    seq_update_t i_updates10 [W10];
    seq_update_t i_updates12 [W12];
    seq_update_t i_updates14 [W14];
    hashed_update_t o_updates8 [W8];
    hashed_update_t o_updates10 [W10];
    hashed_update_t o_updates12 [W12];
    hashed_update_t o_updates14 [W14];

    SeqHasher #(
        .PIPE_WIDTH(W8),
        .NUM_BANKS(BANKS_SEQ2)
    ) dut8 (
        .i_updates(i_updates8),
        .o_updates(o_updates8)
    );

    SeqHasher #(
        .PIPE_WIDTH(W10),
        .NUM_BANKS(BANKS_SEQ3)
    ) dut10 (
        .i_updates(i_updates10),
        .o_updates(o_updates10)
    );

    SeqHasher #(
        .PIPE_WIDTH(W12),
        .NUM_BANKS(BANKS_SEQ4)
    ) dut12 (
        .i_updates(i_updates12),
        .o_updates(o_updates12)
    );

    SeqHasher #(
        .PIPE_WIDTH(W14),
        .NUM_BANKS(BANKS_SEQ5)
    ) dut14 (
        .i_updates(i_updates14),
        .o_updates(o_updates14)
    );

    initial begin
        for (int i = 0; i < W8; i++) i_updates8[i] = '0;
        for (int i = 0; i < W10; i++) i_updates10[i] = '0;
        for (int i = 0; i < W12; i++) i_updates12[i] = '0;
        for (int i = 0; i < W14; i++) i_updates14[i] = '0;

        seed_update(i_updates8[0],  {9'h001, 9'h002, 9'h003, 9'h004, 9'h005}, 1'b1);
        seed_update(i_updates8[1],  {9'h005, 9'h004, 9'h003, 9'h002, 9'h001}, 1'b0);
        seed_update(i_updates10[0], {9'h011, 9'h012, 9'h013, 9'h014, 9'h015}, 1'b1);
        seed_update(i_updates10[1], {9'h015, 9'h014, 9'h013, 9'h012, 9'h011}, 1'b0);
        seed_update(i_updates12[0], {9'h021, 9'h022, 9'h023, 9'h024, 9'h025}, 1'b1);
        seed_update(i_updates12[1], {9'h025, 9'h024, 9'h023, 9'h022, 9'h021}, 1'b0);
        seed_update(i_updates14[0], {9'h031, 9'h032, 9'h033, 9'h034, 9'h035}, 1'b1);
        seed_update(i_updates14[1], {9'h035, 9'h034, 9'h033, 9'h032, 9'h031}, 1'b0);
    end

    initial begin
        #1;
        check_case("seq_len=2", W8, BANKS_SEQ2, 2, i_updates8, o_updates8);
        check_case("seq_len=3", W10, BANKS_SEQ3, 2, i_updates10, o_updates10);
        check_case("seq_len=4", W12, BANKS_SEQ4, 2, i_updates12, o_updates12);
        check_case("seq_len=5", W14, BANKS_SEQ5, 2, i_updates14, o_updates14);
        $finish;
    end
endmodule
