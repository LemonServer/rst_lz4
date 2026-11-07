`timescale 1ps / 1ps
`default_nettype none

package rst_pkg;
`ifdef RST_TIER_TINY
    parameter int CHUNK_WIDTH = 32;
    parameter int PAGE_CHUNKS = 2;
    parameter int MAX_DICT_ENTRIES = 8;
    parameter int MEMORY_BLOCKS = 1;
    parameter int DECOMP_LIFOS = 2;
    parameter int BANKS_SEQ2 = 2;
    parameter int BANKS_SEQ3 = 2;
    parameter int BANKS_SEQ4 = 2;
    parameter int BANKS_SEQ5 = 2;
    parameter int SETS_PER_BANK = 2;
    parameter int WAYS = 2;
    parameter int COUNT_BITS = 6;
    parameter int FIFO_DEPTH = 16;
`elsif RST_TIER_SMALL
    parameter int CHUNK_WIDTH = 64;
    parameter int PAGE_CHUNKS = 4;
    parameter int MAX_DICT_ENTRIES = 16;
    parameter int MEMORY_BLOCKS = 1;
    parameter int DECOMP_LIFOS = 4;
    parameter int BANKS_SEQ2 = 2;
    parameter int BANKS_SEQ3 = 3;
    parameter int BANKS_SEQ4 = 3;
    parameter int BANKS_SEQ5 = 4;
    parameter int SETS_PER_BANK = 4;
    parameter int WAYS = 2;
    parameter int COUNT_BITS = 8;
    parameter int FIFO_DEPTH = 8;
`elsif RST_TIER_MEDIUM
    parameter int CHUNK_WIDTH = 128;
    parameter int PAGE_CHUNKS = 8;
    parameter int MAX_DICT_ENTRIES = 32;
    parameter int MEMORY_BLOCKS = 2;
    parameter int DECOMP_LIFOS = 4;
    parameter int BANKS_SEQ2 = 4;
    parameter int BANKS_SEQ3 = 5;
    parameter int BANKS_SEQ4 = 6;
    parameter int BANKS_SEQ5 = 7;
    parameter int SETS_PER_BANK = 8;
    parameter int WAYS = 4;
    parameter int COUNT_BITS = 10;
    parameter int FIFO_DEPTH = 8;
`elsif RST_TIER_LARGE
    parameter int CHUNK_WIDTH = 256;
    parameter int PAGE_CHUNKS = 16;
    parameter int MAX_DICT_ENTRIES = 63;
    parameter int MEMORY_BLOCKS = 2;
    parameter int DECOMP_LIFOS = 8;
    parameter int BANKS_SEQ2 = 6;
    parameter int BANKS_SEQ3 = 7;
    parameter int BANKS_SEQ4 = 9;
    parameter int BANKS_SEQ5 = 10;
    parameter int SETS_PER_BANK = 16;
    parameter int WAYS = 4;
    parameter int COUNT_BITS = 12;
    parameter int FIFO_DEPTH = 64;
`else
    parameter int CHUNK_WIDTH = 256;
    parameter int PAGE_CHUNKS = 16;
    parameter int MAX_DICT_ENTRIES = 63;
    parameter int MEMORY_BLOCKS = 2;
    parameter int DECOMP_LIFOS = 8;
    parameter int BANKS_SEQ2 = 6;
    parameter int BANKS_SEQ3 = 7;
    parameter int BANKS_SEQ4 = 9;
    parameter int BANKS_SEQ5 = 10;
    parameter int SETS_PER_BANK = 16;
    parameter int WAYS = 4;
    parameter int COUNT_BITS = 12;
    parameter int FIFO_DEPTH = 64;
`endif

    parameter int PAGE_WIDTH = PAGE_CHUNKS * CHUNK_WIDTH;
    parameter int MAX_SEQ_LEN = 5;
    parameter int MIN_SEQ_LEN = 2;
    parameter int DICT_COUNT_BITS = 6;
    parameter int DICT_LEN_BITS = 2;
    parameter int DICT_STORAGE_BITS = MEMORY_BLOCKS * 64 * 8;
    parameter int MAX_DECOMP_SEG_TOKENS = (CHUNK_WIDTH + DECOMP_LIFOS - 1) / DECOMP_LIFOS;
    parameter int MAX_LIFO_STACK_SYMBOLS = CHUNK_WIDTH;

    parameter int PIPE_WIDTH_SEQ2 = 8;
    parameter int PIPE_WIDTH_SEQ3 = 10;
    parameter int PIPE_WIDTH_SEQ4 = 12;
    parameter int PIPE_WIDTH_SEQ5 = 14;
    parameter int INIT_COUNT_POSITIONS_PER_CYCLE = 8;

    typedef logic [8:0] symbol_t;
    typedef logic [4:0][8:0] seq_t;
    typedef logic [DICT_COUNT_BITS-1:0] dict_count_t;
    typedef logic [DICT_STORAGE_BITS-1:0] dict_packed_t;
    typedef logic [$clog2(DICT_STORAGE_BITS + 1)-1:0] dict_bit_count_t;

    typedef struct packed {
        symbol_t sym;
        logic valid;
    } vsym_t;

    typedef struct packed {
        seq_t seq;
        logic inc;
        logic valid;
    } seq_update_t;

    typedef struct packed {
        logic [$clog2(BANKS_SEQ5)-1:0] bank_idx;
        logic [$clog2(SETS_PER_BANK)-1:0] set_idx;
        seq_t seq;
        logic inc;
        logic valid;
    } hashed_update_t;

    typedef struct packed {
        logic [$clog2(BANKS_SEQ5)-1:0] bank_idx;
        logic [$clog2(SETS_PER_BANK)-1:0] set_idx;
        seq_t seq;
        logic signed [COUNT_BITS-1:0] count;
        logic valid;
    } agg_update_t;

    typedef struct packed {
        logic signed [COUNT_BITS-1:0] count;
        seq_t seq;
        logic valid;
    } ht_entry_t;

    typedef struct packed {
        seq_t seq;
        logic [2:0] seq_len;
        logic signed [COUNT_BITS-1:0] count;
        logic valid;
    } top_candidate_t;

    function automatic logic [2:0] seq_len_from_pipe_width(input int pipe_width);
        case (pipe_width)
            PIPE_WIDTH_SEQ2: seq_len_from_pipe_width = 3'd2;
            PIPE_WIDTH_SEQ3: seq_len_from_pipe_width = 3'd3;
            PIPE_WIDTH_SEQ4: seq_len_from_pipe_width = 3'd4;
            PIPE_WIDTH_SEQ5: seq_len_from_pipe_width = 3'd5;
            default:         seq_len_from_pipe_width = 3'd0;
        endcase
    endfunction

    function automatic logic signed [COUNT_BITS+7:0] utility_numerator(
        input logic [2:0] seq_len,
        input logic signed [COUNT_BITS-1:0] count
    );
        int seq_len_i;
        seq_len_i = seq_len;
        utility_numerator = count * (9 * (seq_len_i - 1)) - (9 * seq_len_i + 2);
    endfunction

    function automatic logic [7:0] utility_denominator(input logic [2:0] seq_len);
        case (seq_len)
            3'd2: utility_denominator = 8'd20;
            3'd3: utility_denominator = 8'd29;
            3'd4: utility_denominator = 8'd38;
            3'd5: utility_denominator = 8'd47;
            default: utility_denominator = 8'd1;
        endcase
    endfunction

    function automatic logic [7:0] dict_entry_cost_bits(input logic [2:0] seq_len);
        int seq_len_i;
        seq_len_i = seq_len;
        dict_entry_cost_bits = 9 * seq_len_i + 2;
    endfunction

    function automatic logic [DICT_LEN_BITS-1:0] dict_len_encode(input logic [2:0] seq_len);
        case (seq_len)
            3'd2: dict_len_encode = 2'b00;
            3'd3: dict_len_encode = 2'b01;
            3'd4: dict_len_encode = 2'b10;
            3'd5: dict_len_encode = 2'b11;
            default: dict_len_encode = 2'b00;
        endcase
    endfunction

    function automatic logic [2:0] dict_len_decode(input logic [DICT_LEN_BITS-1:0] packed_len);
        dict_len_decode = {1'b0, packed_len} + 3'd2;
    endfunction

    function automatic symbol_t dict_code_symbol(input dict_count_t dict_idx);
        dict_code_symbol = {1'b1, {(8 - DICT_COUNT_BITS){1'b0}}, dict_idx};
    endfunction
endpackage
