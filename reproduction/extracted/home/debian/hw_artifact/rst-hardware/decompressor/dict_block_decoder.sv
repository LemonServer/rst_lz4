`timescale 1ps / 1ps
`default_nettype none

import parameter_pkg::*;
// maybe reverse the entries so lifo doesn't have to later
// still using an unsigned div. Probably unintended
module DictBlockDecoder (
    input logic clk, reset, enable,
    input logic [7:0] dict_blks_in [MEM_BLKS*64],
    output dict_entry expansion_table [256],
    output logic done
);
    // Internal signals
    logic [3:0][5:0] counts;
    logic [2:0][7:0] count_bytes;
    bit [$clog2(64*MEM_BLKS)-1:0] leader_indices [4]; // dictate what modulo in lut is correct
    bit [3:0] leader_mods [4]; // dictate what modulo in lut is the seq_len for that group

    // Pipeline registers
    logic [3:0][5:0] counts_reg;
    bit [$clog2(64*MEM_BLKS)-1:0] leader_indices_reg [4];
    bit [3:0] leader_mods_reg [4];

    // FSM state
    typedef enum logic [1:0] {IDLE, PIPELINE1, PIPELINE2, DONE} state_t;
    state_t state, next_state;

    // Function to convert bytes to sequence lengths
    function automatic logic [3:0][5:0] bytes_to_seq_lens(input logic [2:0][7:0] bytes);
        logic [3:0][5:0] result;
        logic [23:0] byte_bits;
        begin
            byte_bits = {bytes[0], bytes[1], bytes[2]}; 
            for (int i=0; i<4; i++) begin
                result[3-i] = byte_bits[i*6 +: 6]; 
            end
            return result;
        end 
    endfunction

    // Function to compute modulo using a LUT
    function automatic bit [2:0] mod_lut(input bit [$clog2(MEM_BLKS*64)-1:0] idx, input bit [3:0] mod);
        // potentially not working anymore. might have to make it explicit 
        case (mod)
            4'd3: mod_lut = idx % 3;
            4'd4: mod_lut = idx % 4;
            4'd5: mod_lut = idx % 5;
            4'd6: mod_lut = idx % 6;
            default: mod_lut = 0;
        endcase
    endfunction

    // State transition logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
        end else if (enable) begin
            state <= next_state;
        end
    end

    // Next state logic and output logic
    always_comb begin
        // Default assignments
        next_state = state;
        done = 1'b0;

        case (state)
            IDLE: begin
                next_state = PIPELINE1;
            end
            PIPELINE1: begin
                next_state = PIPELINE2;
            end
            PIPELINE2: begin
                next_state = DONE;
            end
            DONE: begin
                done = 1'b1;
            end
        endcase
    end

    always_comb begin
        for (int i=0; i<3; i++) begin
            count_bytes[i] = dict_blks_in[i];
        end
        counts = bytes_to_seq_lens(count_bytes);
        leader_indices[0] = 3 + counts[0]*3;
        leader_indices[1] = 3 + counts[0]*3 + counts[1]*4;
        leader_indices[2] = 3 + counts[0]*3 + counts[1]*4 + counts[2]*5;
        leader_indices[3] = 3 + counts[0]*3 + counts[1]*4 + counts[2]*5 + counts[3]*6; // first byte of actual compressed data

        leader_mods[0] = mod_lut(3, 3);
        leader_mods[1] = mod_lut(leader_indices[0], 4);
        leader_mods[2] = mod_lut(leader_indices[1], 5);
        leader_mods[3] = mod_lut(leader_indices[2], 6);
        for (int i=0; i<256; i++) begin
            expansion_table[i] = '0;
        end
        if (state == PIPELINE2 || state == DONE) begin
            for (int unsigned i=3; i<64*MEM_BLKS; i++) begin
                bit [3:0] mod_idx;
                bit [2:0] group;
                if (i < leader_indices_reg[0]) begin // 2 byte seq.
                    mod_idx = mod_lut(i, 3);
                    group = 0;
                end else if (i < leader_indices_reg[1]) begin // 3 byte seq.
                    mod_idx = mod_lut(i, 4);
                    group = 1;
                end else if (i < leader_indices_reg[2]) begin // 4 byte seq.
                    mod_idx = mod_lut(i, 5);
                    group = 2;
                end else if (i < leader_indices_reg[3]) begin // 5 byte seq.
                    mod_idx = mod_lut(i, 6);
                    group = 3;
                end else begin // not in. add to lifo
                    mod_idx = 0;
                    group = 4;
                end
                if (group != 4 && mod_idx == leader_mods_reg[group]) begin
                    expansion_table[dict_blks_in[i]].seq_len = group+2;
                    case (group)
                        0: begin
                            expansion_table[dict_blks_in[i]].seq[0] = dict_blks_in[i+2];
                            expansion_table[dict_blks_in[i]].seq[1] = dict_blks_in[i+1];
                        end
                        1: begin
                            expansion_table[dict_blks_in[i]].seq[0] = dict_blks_in[i+3];
                            expansion_table[dict_blks_in[i]].seq[1] = dict_blks_in[i+2];
                            expansion_table[dict_blks_in[i]].seq[2] = dict_blks_in[i+1];
                        end
                        2: begin
                            expansion_table[dict_blks_in[i]].seq[0] = dict_blks_in[i+4];
                            expansion_table[dict_blks_in[i]].seq[1] = dict_blks_in[i+3];
                            expansion_table[dict_blks_in[i]].seq[2] = dict_blks_in[i+2];
                            expansion_table[dict_blks_in[i]].seq[3] = dict_blks_in[i+1];
                        end
                        3: begin
                            expansion_table[dict_blks_in[i]].seq[0] = dict_blks_in[i+5];
                            expansion_table[dict_blks_in[i]].seq[1] = dict_blks_in[i+4];
                            expansion_table[dict_blks_in[i]].seq[2] = dict_blks_in[i+3];
                            expansion_table[dict_blks_in[i]].seq[3] = dict_blks_in[i+2];
                            expansion_table[dict_blks_in[i]].seq[4] = dict_blks_in[i+1];
                        end
                    endcase
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            counts_reg <= '0;
            for (int i=0; i<4; i++) begin
                leader_indices_reg[i] <= '0;
                leader_mods_reg[i] <= '0;
            end
        end else if (state == PIPELINE1) begin
            counts_reg <= counts;
            leader_indices_reg <= leader_indices;
            leader_mods_reg <= leader_mods;
        end 
    end

endmodule
