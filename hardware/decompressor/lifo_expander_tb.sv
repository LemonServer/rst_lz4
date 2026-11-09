`timescale 1ps / 1ps
`default_nettype none

module tb_LifoExpander;
    import rst_pkg::*;

    localparam int CLK_HALF = 5;
    localparam int TIMEOUT_CYCLES = CHUNK_WIDTH * 8;
    localparam int STACK_BANKS = 10;
    localparam int STACK_DEPTH = MAX_LIFO_STACK_SYMBOLS;
    localparam int BANK_DEPTH = (STACK_DEPTH + STACK_BANKS - 1) / STACK_BANKS;
    localparam int RANDOM_CASES = 60;
    localparam int MAX_RANDOM_DICT = (MAX_DICT_ENTRIES < 12) ? MAX_DICT_ENTRIES : 12;

    logic clk;
    logic rst;
    logic start;
    vsym_t compressed_in [MAX_DECOMP_SEG_TOKENS];
    seq_t dict_seqs [MAX_DICT_ENTRIES];
    logic [2:0] dict_lens [MAX_DICT_ENTRIES];
    dict_count_t dict_count;
    symbol_t decompressed_out [CHUNK_WIDTH];
    logic [$clog2(CHUNK_WIDTH + 1)-1:0] out_count;
    logic done;

    symbol_t ref_stack [0:CHUNK_WIDTH-1];
    symbol_t ref_next_stack [0:CHUNK_WIDTH-1];
    symbol_t ref_out [0:CHUNK_WIDTH-1];
    symbol_t dut_stack [0:CHUNK_WIDTH-1];
    int ref_depth;
    int ref_out_count;
    int dict_output_lits [0:MAX_DICT_ENTRIES-1];
    int unsigned prng_state;

    LifoExpander dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .compressed_in(compressed_in),
        .dict_seqs(dict_seqs),
        .dict_lens(dict_lens),
        .dict_count(dict_count),
        .decompressed_out(decompressed_out),
        .out_count(out_count),
        .done(done)
    );

    always #(CLK_HALF) clk = ~clk;

    function automatic symbol_t literal_sym(input int value);
        begin
            literal_sym = symbol_t'(value & 9'h0ff);
        end
    endfunction

    function automatic symbol_t code_sym(input int idx);
        begin
            code_sym = symbol_t'(9'h100 + idx);
        end
    endfunction

    function automatic logic ref_sym_is_code(input symbol_t sym);
        begin
            ref_sym_is_code = sym[8];
        end
    endfunction

    function automatic int unsigned next_rand();
        begin
            prng_state = (prng_state * 32'd1664525) + 32'd1013904223;
            next_rand = prng_state;
        end
    endfunction

    function automatic int rand_range(input int lo, input int hi);
        int span;
        begin
            if (hi <= lo) begin
                rand_range = lo;
            end else begin
                span = hi - lo + 1;
                rand_range = lo + int'(next_rand() % span);
            end
        end
    endfunction

    task automatic clear_stimulus;
        begin
            start = 1'b0;
            dict_count = '0;
            for (int i = 0; i < MAX_DECOMP_SEG_TOKENS; i++) begin
                compressed_in[i] = '0;
            end
            for (int i = 0; i < MAX_DICT_ENTRIES; i++) begin
                dict_seqs[i] = '0;
                dict_lens[i] = '0;
                dict_output_lits[i] = 0;
            end
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                ref_stack[i] = '0;
                ref_next_stack[i] = '0;
                ref_out[i] = '0;
                dut_stack[i] = '0;
            end
            ref_depth = 0;
            ref_out_count = 0;
        end
    endtask

    task automatic reset_dut;
        begin
            clear_stimulus();
            rst = 1'b1;
            repeat (3) @(posedge clk);
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

    task automatic build_ref_initial_stack;
        begin
            ref_depth = 0;
            ref_out_count = 0;
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                ref_stack[i] = '0;
                ref_out[i] = '0;
            end
            for (int i = 0; i < MAX_DECOMP_SEG_TOKENS; i++) begin
                if (compressed_in[i].valid) begin
                    ref_stack[ref_depth] = compressed_in[i].sym;
                    ref_depth++;
                end
            end
        end
    endtask

    task automatic decode_dut_stack;
        begin
            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                dut_stack[i] = '0;
            end

            for (int logical_pos = 0; logical_pos < dut.sp_r; logical_pos++) begin
                int bank;
                int occurrence;
                int count;

                bank = (dut.top_phase_r + logical_pos) % STACK_BANKS;
                occurrence = logical_pos / STACK_BANKS;
                count = dut.bank_counts_r[bank];

                if (occurrence >= count) begin
                    $fatal(1, "decode_dut_stack bank underflow logical_pos=%0d bank=%0d occ=%0d count=%0d",
                        logical_pos, bank, occurrence, count);
                end

                dut_stack[logical_pos] = dut.bank_mem_r[bank][occurrence];
            end
        end
    endtask

    task automatic compare_dut_to_ref(input string case_name, input int cycle_idx);
        int bank_sum;
        int bank_min;
        int bank_max;
        begin
            decode_dut_stack();

            if (dut.sp_r != ref_depth) begin
                $fatal(1, "%s cycle=%0d depth mismatch got=%0d expected=%0d",
                    case_name, cycle_idx, dut.sp_r, ref_depth);
            end

            for (int i = 0; i < ref_depth; i++) begin
                if (dut_stack[i] !== ref_stack[i]) begin
                    $fatal(1, "%s cycle=%0d stack[%0d] mismatch got=%0h expected=%0h",
                        case_name, cycle_idx, i, dut_stack[i], ref_stack[i]);
                end
            end

            if (dut.out_count_r != ref_out_count) begin
                $fatal(1, "%s cycle=%0d out_count mismatch got=%0d expected=%0d",
                    case_name, cycle_idx, dut.out_count_r, ref_out_count);
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                symbol_t want;
                want = (i < ref_out_count) ? ref_out[i] : '0;
                if (decompressed_out[i] !== want) begin
                    $fatal(1, "%s cycle=%0d decompressed_out[%0d] mismatch got=%0h expected=%0h",
                        case_name, cycle_idx, i, decompressed_out[i], want);
                end
            end

            if (done !== (ref_depth == 0)) begin
                $fatal(1, "%s cycle=%0d done mismatch got=%0b expected=%0b",
                    case_name, cycle_idx, done, (ref_depth == 0));
            end

            bank_sum = 0;
            bank_min = BANK_DEPTH;
            bank_max = 0;
            for (int bank = 0; bank < STACK_BANKS; bank++) begin
                int count;
                count = dut.bank_counts_r[bank];
                bank_sum += count;
                if (count < bank_min) begin
                    bank_min = count;
                end
                if (count > bank_max) begin
                    bank_max = count;
                end
            end

            if (bank_sum != dut.sp_r) begin
                $fatal(1, "%s cycle=%0d bank sum mismatch got=%0d expected=%0d",
                    case_name, cycle_idx, bank_sum, dut.sp_r);
            end
            if ((bank_max - bank_min) > 1) begin
                $fatal(1, "%s cycle=%0d bank skew too large min=%0d max=%0d",
                    case_name, cycle_idx, bank_min, bank_max);
            end
        end
    endtask

    task automatic ref_step(input string case_name);
        int consumed;
        int prod_len;
        int new_depth;
        int top_code_idx;
        int below_code_idx;
        int top_seq_len;
        int below_seq_len;
        symbol_t top_sym;
        symbol_t below_sym;
        symbol_t prod_syms [0:(2 * MAX_SEQ_LEN) - 1];
        logic top_is_code;
        logic below_is_code;
        logic dual_issue;
        begin
            if (ref_depth == 0) begin
                return;
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                ref_next_stack[i] = '0;
            end
            for (int i = 0; i < (2 * MAX_SEQ_LEN); i++) begin
                prod_syms[i] = '0;
            end

            top_sym = ref_stack[0];
            top_is_code = ref_sym_is_code(top_sym);
            below_sym = '0;
            below_is_code = 1'b0;
            dual_issue = 1'b0;
            consumed = 1;
            prod_len = 0;
            top_code_idx = 0;
            below_code_idx = 0;
            top_seq_len = 0;
            below_seq_len = 0;

            if (ref_depth > 1) begin
                below_sym = ref_stack[1];
                below_is_code = ref_sym_is_code(below_sym);
                dual_issue = !(top_is_code && !below_is_code);
                consumed = dual_issue ? 2 : 1;
            end

            if (!top_is_code) begin
                if (ref_out_count >= CHUNK_WIDTH) begin
                    $fatal(1, "%s reference output overflow on top literal", case_name);
                end
                ref_out[ref_out_count] = top_sym;
                ref_out_count++;
            end

            if (dual_issue && !below_is_code) begin
                if (ref_out_count >= CHUNK_WIDTH) begin
                    $fatal(1, "%s reference output overflow on below literal", case_name);
                end
                ref_out[ref_out_count] = below_sym;
                ref_out_count++;
            end

            if (top_is_code) begin
                top_code_idx = top_sym[7:0];
                if (top_code_idx < MAX_DICT_ENTRIES && top_code_idx < dict_count) begin
                    top_seq_len = dict_lens[top_code_idx];
                end
                for (int j = 0; j < MAX_SEQ_LEN; j++) begin
                    if (j < top_seq_len) begin
                        prod_syms[prod_len + j] = dict_seqs[top_code_idx][j];
                    end
                end
                prod_len += top_seq_len;
            end

            if (dual_issue && below_is_code) begin
                below_code_idx = below_sym[7:0];
                if (below_code_idx < MAX_DICT_ENTRIES && below_code_idx < dict_count) begin
                    below_seq_len = dict_lens[below_code_idx];
                end
                for (int j = 0; j < MAX_SEQ_LEN; j++) begin
                    if (j < below_seq_len) begin
                        prod_syms[prod_len + j] = dict_seqs[below_code_idx][j];
                    end
                end
                prod_len += below_seq_len;
            end

            new_depth = ref_depth - consumed + prod_len;
            if (new_depth > CHUNK_WIDTH) begin
                $fatal(1, "%s reference stack overflow depth=%0d", case_name, new_depth);
            end

            for (int i = 0; i < prod_len; i++) begin
                ref_next_stack[i] = prod_syms[i];
            end
            for (int i = consumed; i < ref_depth; i++) begin
                ref_next_stack[prod_len + i - consumed] = ref_stack[i];
            end

            for (int i = 0; i < CHUNK_WIDTH; i++) begin
                ref_stack[i] = (i < new_depth) ? ref_next_stack[i] : '0;
            end
            ref_depth = new_depth;
        end
    endtask

    task automatic run_loaded_case(input string case_name);
        int cycles;
        begin
            build_ref_initial_stack();
            pulse_start();
            @(posedge clk);
            compare_dut_to_ref(case_name, 0);

            cycles = 0;
            while (!done && cycles < TIMEOUT_CYCLES) begin
                ref_step(case_name);
                @(posedge clk);
                cycles++;
                compare_dut_to_ref(case_name, cycles);
            end

            if (!done) begin
                $fatal(1, "%s timed out waiting for done", case_name);
            end

            $display("%s passed in %0d cycles", case_name, cycles);
        end
    endtask

    task automatic setup_empty_case;
        begin
            reset_dut();
        end
    endtask

    task automatic setup_dual_code_case;
        begin
            reset_dut();

            dict_count = 2;
            dict_lens[0] = 3'd2;
            dict_seqs[0][0] = literal_sym("A");
            dict_seqs[0][1] = literal_sym("B");
            dict_output_lits[0] = 2;

            dict_lens[1] = 3'd2;
            dict_seqs[1][0] = literal_sym("C");
            dict_seqs[1][1] = literal_sym("D");
            dict_output_lits[1] = 2;

            compressed_in[0] = '{sym: code_sym(0), valid: 1'b1};
            compressed_in[1] = '{sym: code_sym(1), valid: 1'b1};
        end
    endtask

    task automatic setup_nested_restriction_case;
        begin
            reset_dut();

            dict_count = 2;
            dict_lens[0] = 3'd2;
            dict_seqs[0][0] = literal_sym("A");
            dict_seqs[0][1] = code_sym(1);
            dict_output_lits[0] = 3;

            dict_lens[1] = 3'd2;
            dict_seqs[1][0] = literal_sym("B");
            dict_seqs[1][1] = literal_sym("C");
            dict_output_lits[1] = 2;

            compressed_in[0] = '{sym: code_sym(0), valid: 1'b1};
            compressed_in[1] = '{sym: literal_sym("D"), valid: 1'b1};
        end
    endtask

    task automatic setup_max_prod_case;
        begin
            reset_dut();

            dict_count = 2;
            dict_lens[0] = 3'd5;
            dict_lens[1] = 3'd5;
            dict_output_lits[0] = 5;
            dict_output_lits[1] = 5;

            for (int i = 0; i < 5; i++) begin
                dict_seqs[0][i] = literal_sym("a" + i);
                dict_seqs[1][i] = literal_sym("f" + i);
            end

            compressed_in[0] = '{sym: code_sym(0), valid: 1'b1};
            compressed_in[1] = '{sym: code_sym(1), valid: 1'b1};
            compressed_in[2] = '{sym: literal_sym("z"), valid: 1'b1};
        end
    endtask

    task automatic setup_random_case(input int case_idx);
        int live_dict_count;
        int valid_count;
        int running_output;
        begin
            reset_dut();

            live_dict_count = rand_range(0, MAX_RANDOM_DICT);
            dict_count = dict_count_t'(live_dict_count);

            for (int idx = 0; idx < live_dict_count; idx++) begin
                int tries;
                bit accepted;

                accepted = 1'b0;
                tries = 0;
                while (!accepted && tries < 64) begin
                    int seq_len;
                    int output_lits;

                    seq_len = rand_range(MIN_SEQ_LEN, MAX_SEQ_LEN);
                    output_lits = 0;
                    for (int lane = 0; lane < MAX_SEQ_LEN; lane++) begin
                        dict_seqs[idx][lane] = '0;
                    end

                    for (int lane = 0; lane < seq_len; lane++) begin
                        bit choose_code;

                        choose_code = (idx > 0) && (rand_range(0, 99) < 55);
                        if (choose_code) begin
                            int code_idx;
                            code_idx = rand_range(0, idx - 1);
                            dict_seqs[idx][lane] = code_sym(code_idx);
                            output_lits += dict_output_lits[code_idx];
                        end else begin
                            dict_seqs[idx][lane] = literal_sym(rand_range(0, 255));
                            output_lits += 1;
                        end
                    end

                    if (output_lits <= CHUNK_WIDTH) begin
                        dict_lens[idx] = seq_len[2:0];
                        dict_output_lits[idx] = output_lits;
                        accepted = 1'b1;
                    end else begin
                        tries++;
                    end
                end

                if (!accepted) begin
                    dict_lens[idx] = MIN_SEQ_LEN[2:0];
                    dict_output_lits[idx] = MIN_SEQ_LEN;
                    for (int lane = 0; lane < MAX_SEQ_LEN; lane++) begin
                        dict_seqs[idx][lane] = '0;
                    end
                    for (int lane = 0; lane < MIN_SEQ_LEN; lane++) begin
                        dict_seqs[idx][lane] = literal_sym((case_idx + idx + lane) & 8'hff);
                    end
                end
            end

            valid_count = rand_range(0, MAX_DECOMP_SEG_TOKENS);
            running_output = 0;

            for (int idx = 0; idx < valid_count; idx++) begin
                int remaining_tokens;
                int choice;

                remaining_tokens = valid_count - idx - 1;
                choice = -1;

                if ((live_dict_count > 0) && (rand_range(0, 99) < 65)) begin
                    for (int tries = 0; tries < 8; tries++) begin
                        int code_idx;
                        code_idx = rand_range(0, live_dict_count - 1);
                        if ((running_output + dict_output_lits[code_idx] + remaining_tokens) <= CHUNK_WIDTH) begin
                            choice = code_idx;
                            break;
                        end
                    end
                end

                if (choice >= 0) begin
                    compressed_in[idx] = '{sym: code_sym(choice), valid: 1'b1};
                    running_output += dict_output_lits[choice];
                end else begin
                    compressed_in[idx] = '{sym: literal_sym(rand_range(0, 255)), valid: 1'b1};
                    running_output += 1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        prng_state = 32'h1bad_f00d;
        clear_stimulus();

        setup_empty_case();
        run_loaded_case("empty");

        setup_dual_code_case();
        run_loaded_case("dual_code");

        setup_nested_restriction_case();
        run_loaded_case("nested_restriction");

        setup_max_prod_case();
        run_loaded_case("max_prod_len");

        for (int case_idx = 0; case_idx < RANDOM_CASES; case_idx++) begin
            string case_name;
            case_name = $sformatf("random_%0d", case_idx);
            setup_random_case(case_idx);
            run_loaded_case(case_name);
        end

        $display("tb_LifoExpander passed");
        $finish;
    end
endmodule
