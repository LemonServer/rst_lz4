`timescale 1ps / 1ps
`default_nettype none

module SeqHasher
    import rst_pkg::*;
#(
    parameter int PIPE_WIDTH = PIPE_WIDTH_SEQ2,
    parameter int NUM_BANKS = BANKS_SEQ2
) (
    input  seq_update_t   i_updates [PIPE_WIDTH],
    output hashed_update_t o_updates [PIPE_WIDTH]
);
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

    function automatic logic [42:0] seq_payload(input seq_update_t update);
        logic [42:0] payload;
        begin
            payload = {
                update.seq[4][7:0],
                update.seq[3][7:0],
                update.seq[2][7:0],
                update.seq[1][7:0],
                update.seq[0][7:0],
                seq_len_from_pipe_width(PIPE_WIDTH)
            };
            return payload;
        end
    endfunction

    always_comb begin
        for (int i = 0; i < PIPE_WIDTH; i++) begin
            logic [15:0] hash_value;

            hash_value = '0;
            o_updates[i] = '0;
            if (i_updates[i].valid) begin
                hash_value = crc(seq_payload(i_updates[i]));
                o_updates[i].bank_idx = hash_value % NUM_BANKS;
                o_updates[i].set_idx = (hash_value / NUM_BANKS) % SETS_PER_BANK;
                o_updates[i].seq = i_updates[i].seq;
                o_updates[i].inc = i_updates[i].inc;
                o_updates[i].valid = 1'b1;
            end
        end
    end
endmodule
