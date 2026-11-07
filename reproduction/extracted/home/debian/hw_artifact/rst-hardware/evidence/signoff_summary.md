# Small Synthesis Evidence Bundle: reviewer_small_tops_split

## Batch Snapshot

- Packaged batch directory: `synthesis/results/parser_smoke_batches/reviewer_small_tops_split`
- Profile: `tops_only`
- Tier: `small`
- Jobs done: `4/4`
- Compile jobs done: `4`
- Worst slack: `0.0 ps`

## Units

- Timing and slack are reported in `ps`.
- Power is reported in `mW`.
- Area values are DC `Design Area` / `report_area` totals from the ASAP7 library setup, so treat them as relative synthesized cell-area figures rather than routed silicon area.

## Top Metrics

### PageCompressorTop
- Status: `done`
- Area (ASAP7 DC Design Area): total `613903.4`, comb `357102.5`, noncomb `256800.9`, seq cells `50850`
- Timing: slack `0.00 ps`, start `pipe_seq4/sorted_stage_updates_reg[8][seq][3][5]`, end `pipe_seq4/aggregated_stage_updates_reg[0][seq][3][8]`
- Path hierarchy trace: `pipe_seq4, pipe_seq5, dict_serializer, <top>, <top_logic>`
- Hier delay attribution: `pipe_seq4=1051.23 ps, dict_serializer=296.10 ps, pipe_seq5=260.28 ps, <top_logic>=36.45 ps, <top>=0.00 ps`
- Area hierarchy preview: `Number of nets:=381391.0, Number of cells:=352862.0, Number of combinational cells:=301982.0, Number of sequential cells:=50850.0, Number of buf/inv:=43898.0, Buf/Inv area:=33588.1`
- Power: `activity=117.835 mW, clock_only=114.627 mW, zero_toggle=0.000 mW, activity-minus-clock-only=3.208 mW`
- Activity breakdown: `clock_network=111.627 mW, register=3.205 mW, combinational=3.638 mW, leakage=0.629 mW`

### PageDecompressorTop
- Status: `done`
- Area (ASAP7 DC Design Area): total `90773.9`, comb `58062.0`, noncomb `32711.9`, seq cells `6191`
- Timing: slack `0.00 ps`, start `chunk_decompressor/segmented_inputs_r_reg[0][0][valid]`, end `chunk_decompressor/gen_lifos[0].lifo_expander/bank_mem_r_reg[8][0][2]`
- Path hierarchy trace: `chunk_decompressor, <top_logic>, decompressed_out_r_reg[60][5], <top>`
- Hier delay attribution: `<top_logic>=740.07 ps, <top>=0.00 ps, chunk_decompressor=0.00 ps, decompressed_out_r_reg[60][5]=0.00 ps`
- Area hierarchy preview: `Number of nets:=62839.0, Number of cells:=59067.0, Number of combinational cells:=52873.0, Number of buf/inv:=6746.0, Number of sequential cells:=6191.0, Buf/Inv area:=4987.8`
- Power: `activity=18.233 mW, clock_only=14.222 mW, zero_toggle=0.000 mW, activity-minus-clock-only=4.011 mW`
- Activity breakdown: `clock_network=13.616 mW, register=2.464 mW, combinational=2.303 mW, leakage=0.149 mW`

### CompressorTop
- Status: `done`
- Area (ASAP7 DC Design Area): total `638968.8`, comb `351266.5`, noncomb `287702.3`, seq cells `55317`
- Timing: slack `0.00 ps`, start `pipe_seq4/aggregator/R_68091`, end `pipe_seq4/pending_updates_reg[0][6][count][3]`
- Path hierarchy trace: `pipe_seq4, mfr, pipe_seq3, hash_table, pipe_seq2, pipe_seq5, dict_count_r_reg[5], dict_serializer, <top>, <top_logic>, page_reg_reg[22][sym][5], page_reg_reg[23][sym][5]`
- Hier delay attribution: `hash_table=699.66 ps, mfr=325.73 ps, dict_serializer=317.77 ps, pipe_seq4=311.02 ps, pipe_seq5=291.53 ps, <top_logic>=46.05 ps, dict_count_r_reg[5]=33.65 ps, <top>=0.00 ps`
- Area hierarchy preview: `Number of nets:=379841.0, Number of cells:=351446.0, Number of combinational cells:=296099.0, Number of sequential cells:=55317.0, Number of buf/inv:=43588.0, Buf/Inv area:=33053.2`

### DecompressorTop
- Status: `done`
- Area (ASAP7 DC Design Area): total `71174.7`, comb `54829.0`, noncomb `16345.7`, seq cells `3303`
- Timing: slack `0.01 ps`, start `gen_lifos[0].lifo_expander/R_1501`, end `gen_lifos[0].lifo_expander/bank_mem_r_reg[9][0][4]`
- Path hierarchy trace: `gen_lifos[0].lifo_expander, R_1239, <top_logic>, gen_lifos[1].lifo_expander, <top>, dict_deserializer, dict_seqs_r_reg[7][0][3], dict_seqs_r_reg[5][0][6]`
- Hier delay attribution: `dict_deserializer=696.62 ps, <top_logic>=79.88 ps, R_1239=29.92 ps, <top>=0.00 ps, dict_seqs_r_reg[5][0][6]=0.00 ps, dict_seqs_r_reg[7][0][3]=0.00 ps, gen_lifos[0].lifo_expander=0.00 ps, gen_lifos[1].lifo_expander=0.00 ps`
- Area hierarchy preview: `Number of nets:=57230.0, Number of cells:=53778.0, Number of combinational cells:=50472.0, Number of buf/inv:=6335.0, Buf/Inv area:=4706.4, Number of ports:=3733.0`

## Functional / Perf Context

- `small` runtime harness: pages `16`, ratio `1.8208`, compressor throughput `0.1415 B/cycle`, decompressor throughput `1.2005 B/cycle`

## Gaps

- None.
