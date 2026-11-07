#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

from sorting_net_verilog_gen import NETWORKS


WIDTH_SYMBOLS = {
    8: "PIPE_WIDTH_SEQ2",
    10: "PIPE_WIDTH_SEQ3",
    12: "PIPE_WIDTH_SEQ4",
    14: "PIPE_WIDTH_SEQ5",
}


VARIANT_CUTS = {
    "SeqSorterPipe1": {
        8: (3,),
        10: (4,),
        12: (4,),
        14: (5,),
    },
    "SeqSorterPipe2": {
        8: (2, 4),
        10: (2, 5),
        12: (3, 6),
        14: (3, 6),
    },
    "SeqSorterPipe3": {
        8: (1, 3, 5),
        10: (2, 4, 6),
        12: (2, 4, 6),
        14: (2, 5, 7),
    },
    "SeqSorterPipe4": {
        8: (1, 2, 4, 5),
        10: (1, 3, 5, 6),
        12: (1, 3, 5, 7),
        14: (2, 4, 6, 8),
    },
    "SeqSorterPipe5": {
        8: (1, 3, 4, 5),
        10: (2, 4, 5, 6),
        12: (2, 4, 6, 7),
        14: (1, 3, 5, 7),
    },
    "SeqSorterPipe6": {
        8: (1, 2, 3, 5),
        10: (2, 3, 5, 6),
        12: (2, 4, 5, 7),
        14: (2, 4, 6, 7),
    },
    "SeqSorterPipe7": {
        8: (1, 2, 3, 4, 5),
        10: (1, 2, 3, 4, 5, 6),
        12: (1, 2, 3, 4, 5, 6, 7),
        14: (1, 2, 3, 4, 5, 6, 7, 8),
    },
    "SeqSorterPipe8": {
        8: (1, 2, 3, 4, 5, 6),
        10: (1, 2, 3, 4, 5, 6, 7),
        12: (1, 2, 3, 4, 5, 6, 7, 8),
        14: (1, 2, 3, 4, 5, 6, 7, 8, 9),
    },
}


def emit_common_defs(lines: list[str]) -> None:
    lines.extend(
        [
            "    localparam int SORT_KEY_W = 1 + $clog2(BANKS_SEQ5) + $bits(seq_t) + 1 + $clog2(SETS_PER_BANK);",
            "",
            "    typedef logic [SORT_KEY_W-1:0] sort_key_t;",
            "",
            "    typedef struct packed {",
            "        sort_key_t key;",
            "        hashed_update_t update;",
            "    } keyed_update_t;",
            "",
            "    typedef struct packed {",
            "        keyed_update_t lo;",
            "        keyed_update_t hi;",
            "    } keyed_pair_t;",
            "",
            "    function automatic seq_t active_seq(input hashed_update_t update);",
            "        case (PIPE_WIDTH)",
            "            PIPE_WIDTH_SEQ2: active_seq = {27'b0, update.seq[1], update.seq[0]};",
            "            PIPE_WIDTH_SEQ3: active_seq = {18'b0, update.seq[2], update.seq[1], update.seq[0]};",
            "            PIPE_WIDTH_SEQ4: active_seq = {9'b0, update.seq[3], update.seq[2], update.seq[1], update.seq[0]};",
            "            default:         active_seq = update.seq;",
            "        endcase",
            "    endfunction",
            "",
            "    function automatic sort_key_t sort_key(input hashed_update_t update);",
            "        sort_key = {",
            "            ~update.valid,",
            "            update.valid ? update.bank_idx : '0,",
            "            update.valid ? active_seq(update) : '0,",
            "            update.valid ? update.inc : 1'b0,",
            "            update.valid ? update.set_idx : '0",
            "        };",
            "    endfunction",
            "",
            "    function automatic keyed_pair_t ce_pair(",
            "        input keyed_update_t lhs,",
            "        input keyed_update_t rhs",
            "    );",
            "        keyed_pair_t pair;",
            "        begin",
            "            if (rhs.key < lhs.key) begin",
            "                pair.lo = rhs;",
            "                pair.hi = lhs;",
            "            end else begin",
            "                pair.lo = lhs;",
            "                pair.hi = rhs;",
            "            end",
            "            return pair;",
            "        end",
            "    endfunction",
            "",
        ]
    )


def emit_width_branch(
    width: int,
    layers: list[list[tuple[int, int]]],
    cuts: tuple[int, ...],
    branch_header: str,
) -> list[str]:
    cut_to_idx = {cut: idx for idx, cut in enumerate(cuts)}
    lines = [branch_header]
    lines.append(f"            localparam int LATENCY = {len(cuts)};")
    lines.append(f"            logic [LATENCY-1:0] valid_pipe;")
    for cut_idx in range(len(cuts)):
        lines.append(f"            keyed_update_t cut{cut_idx}_d [{width}];")
        lines.append(f"            keyed_update_t cut{cut_idx}_q [{width}];")
    lines.append("")
    lines.append("            assign o_valid = valid_pipe[LATENCY - 1];")
    lines.append("")
    lines.append("            always_ff @(posedge clk) begin")
    lines.append("                if (rst) begin")
    lines.append("                    valid_pipe <= '0;")
    lines.append(f"                    for (int i = 0; i < {width}; i++) begin")
    for cut_idx in range(len(cuts)):
        lines.append(f"                        cut{cut_idx}_q[i] <= '0;")
    lines.append("                    end")
    lines.append("                end else begin")
    lines.append("                    valid_pipe[0] <= i_valid;")
    for cut_idx in range(1, len(cuts)):
        lines.append(f"                    valid_pipe[{cut_idx}] <= valid_pipe[{cut_idx - 1}];")
    lines.append(f"                    for (int i = 0; i < {width}; i++) begin")
    for cut_idx in range(len(cuts)):
        lines.append(f"                        cut{cut_idx}_q[i] <= cut{cut_idx}_d[i];")
    lines.append("                    end")
    lines.append("                end")
    lines.append("            end")
    lines.append("")
    lines.append("            always_comb begin")
    for stage_idx in range(len(layers) + 1):
        lines.append(f"                keyed_update_t stage{stage_idx} [{width}];")
    lines.append("                keyed_pair_t pair;")
    lines.append("")
    lines.append(f"                for (int i = 0; i < {width}; i++) begin")
    lines.append("                    o_updates[i] = '0;")
    for cut_idx in range(len(cuts)):
        lines.append(f"                    cut{cut_idx}_d[i] = '0;")
    lines.append("                end")
    lines.append("")
    lines.append(f"                for (int i = 0; i < {width}; i++) begin")
    lines.append("                    stage0[i].update = i_updates[i];")
    lines.append("                    stage0[i].key = sort_key(i_updates[i]);")
    lines.append("                end")
    lines.append("")

    for layer_idx, layer in enumerate(layers, start=1):
        cut_before = cut_to_idx.get(layer_idx - 1)
        source = f"stage{layer_idx - 1}"
        if cut_before is not None:
            source = f"cut{cut_before}_q"
        lines.append(f"                stage{layer_idx} = {source};")
        for lhs_idx, rhs_idx in layer:
            lines.append(
                f"                pair = ce_pair(stage{layer_idx}[{lhs_idx}], stage{layer_idx}[{rhs_idx}]); "
                f"stage{layer_idx}[{lhs_idx}] = pair.lo; stage{layer_idx}[{rhs_idx}] = pair.hi;"
            )
        lines.append("")
        cut_after = cut_to_idx.get(layer_idx)
        if cut_after is not None:
            lines.append(f"                for (int i = 0; i < {width}; i++) begin")
            lines.append(f"                    cut{cut_after}_d[i] = stage{layer_idx}[i];")
            lines.append("                end")
            lines.append("")

    final_source = f"stage{len(layers)}"
    final_cut = cut_to_idx.get(len(layers))
    if final_cut is not None:
        final_source = f"cut{final_cut}_q"

    lines.append(f"                for (int i = 0; i < {width}; i++) begin")
    lines.append(f"                    o_updates[i] = {final_source}[i].update;")
    lines.append("                end")
    lines.append("            end")
    return lines


def emit_default_branch() -> list[str]:
    return [
        "        end else begin : gen_default",
        "            assign o_valid = i_valid;",
        "",
        "            always_comb begin",
        "                for (int i = 0; i < PIPE_WIDTH; i++) begin",
        "                    o_updates[i] = i_updates[i];",
        "                end",
        "            end",
    ]


def emit_variant_module(name: str, cuts_by_width: dict[int, tuple[int, ...]]) -> list[str]:
    lines = [
        f"module {name}",
        "    import rst_pkg::*;",
        "#(",
        "    parameter int PIPE_WIDTH = PIPE_WIDTH_SEQ2",
        ") (",
        "    input  logic clk,",
        "    input  logic rst,",
        "    input  logic i_valid,",
        "    input  hashed_update_t i_updates [PIPE_WIDTH],",
        "    output logic o_valid,",
        "    output hashed_update_t o_updates [PIPE_WIDTH]",
        ");",
    ]
    emit_common_defs(lines)
    lines.append("    generate")
    widths = sorted(cuts_by_width)
    for idx, width in enumerate(widths):
        if idx == 0:
            header = f"        if (PIPE_WIDTH == {width}) begin : gen_w{width}"
        else:
            header = f"        end else if (PIPE_WIDTH == {width}) begin : gen_w{width}"
        lines.extend(emit_width_branch(width, NETWORKS[width], cuts_by_width[width], header))
    lines.extend(emit_default_branch())
    lines.extend(
        [
            "        end",
            "    endgenerate",
            "endmodule",
            "",
        ]
    )
    return lines


def emit_comb_wrapper(width: int) -> list[str]:
    width_symbol = WIDTH_SYMBOLS[width]
    return [
        f"module SeqSorterW{width}",
        "    import rst_pkg::*;",
        "(",
        f"    input  hashed_update_t i_updates [{width_symbol}],",
        f"    output hashed_update_t o_updates [{width_symbol}]",
        ");",
        "    SeqSorter #(",
        f"        .PIPE_WIDTH({width_symbol})",
        "    ) dut (",
        "        .i_updates(i_updates),",
        "        .o_updates(o_updates)",
        "    );",
        "endmodule",
        "",
    ]


def emit_pipe_wrapper(module_name: str, width: int) -> list[str]:
    width_symbol = WIDTH_SYMBOLS[width]
    return [
        f"module {module_name}W{width}",
        "    import rst_pkg::*;",
        "(",
        "    input  logic clk,",
        "    input  logic rst,",
        "    input  logic i_valid,",
        f"    input  hashed_update_t i_updates [{width_symbol}],",
        "    output logic o_valid,",
        f"    output hashed_update_t o_updates [{width_symbol}]",
        ");",
        f"    {module_name} #(",
        f"        .PIPE_WIDTH({width_symbol})",
        "    ) dut (",
        "        .clk(clk),",
        "        .rst(rst),",
        "        .i_valid(i_valid),",
        "        .i_updates(i_updates),",
        "        .o_valid(o_valid),",
        "        .o_updates(o_updates)",
        "    );",
        "endmodule",
        "",
    ]


def generate_experiments() -> str:
    lines = [
        "`timescale 1ps / 1ps",
        "`default_nettype none",
        "",
        "// Generated by compressor/sorting_net_pipeline_experiments_gen.py",
        "",
    ]

    for name, cuts_by_width in VARIANT_CUTS.items():
        lines.extend(emit_variant_module(name, cuts_by_width))

    for width in sorted(WIDTH_SYMBOLS):
        lines.extend(emit_comb_wrapper(width))

    for name in VARIANT_CUTS:
        for width in sorted(WIDTH_SYMBOLS):
            lines.extend(emit_pipe_wrapper(name, width))

    return "\n".join(lines)


def main() -> None:
    output_path = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path("seq_sorter_pipeline_variants.sv")
    )
    output_path.write_text(generate_experiments(), encoding="ascii")
    print(f"Generated sorter experiment RTL -> {output_path}")


if __name__ == "__main__":
    main()
