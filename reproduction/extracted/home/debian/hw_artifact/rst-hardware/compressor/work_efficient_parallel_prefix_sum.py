#!/usr/bin/env python3
from itertools import groupby
from copy import deepcopy
import sys

# batched is only in Python 3.12+, provide fallback
try:
    from itertools import batched
except ImportError:
    def batched(iterable, n):
        """Batch data into lists of length n. The last batch may be shorter."""
        from itertools import islice
        it = iter(iterable)
        while True:
            batch = list(islice(it, n))
            if not batch:
                return
            yield batch

# SIZE can be overridden by command line argument
SIZE = 12 if len(sys.argv) < 2 else int(sys.argv[1])

class Value:
    def __init__(self, val):
        self.result = val

    def update(self):
        pass

    def __repr__(self):
        return f"{self.result}"

    def wire_count(self):
        return 1


total_adders = 0
adders = []


class Adder:
    def __init__(self, left, right):
        global total_adders
        global adders
        adders.append(self)
        self.id = total_adders
        self.in1_wire = f"w_{self.id}_in1"
        self.in2_wire = f"w_{self.id}_in2"
        self.out_wire = f"w_{self.id}_out"

        total_adders += 1
        self.left = left
        self.right = right
        self.result = None

        # might need to adjust this if it causes synopsys to freak out
        self.in1_width = self.left.wire_count().bit_length()
        self.in2_width = self.right.wire_count().bit_length()
        self.out_width = self.wire_count().bit_length()

    def update(self):
        if self.result is None:
            self.left.update()
            self.right.update()
            self.result = self.left.result + self.right.result

    def __repr__(self):
        return f"({self.left}+{self.right})"

    def wire_count(self):
        total = 0
        if type(self.left) is Adder:
            total += self.left.wire_count()
        else:
            total += 1
        if type(self.right) is Adder:
            total += self.right.wire_count()
        else:
            total += 1
        return total


class PrefixSumCircuit:
    def create_top_circuit(self):
        modulo = 2
        while modulo < len(self.top_wires):
            for idx, wire in enumerate(self.top_wires):
                if idx % modulo == modulo - 1:
                    self.top_wires[idx].append(
                        Adder(self.top_wires[idx - modulo // 2][-1], wire[-1])
                    )
            modulo *= 2

    def create_bottom_circuit(self):
        wire_counts = set()
        for wire in self.top_wires:
            if len(wire) != 1:
                wire_counts.add(wire[-1].wire_count())
        for wire_count in sorted(wire_counts, reverse=True):
            for idx, wire in enumerate(self.top_wires):
                if len(wire) != 1:  # adders
                    offset = wire[-1].wire_count()
                    if offset == wire_count and idx - offset != -1:
                        self.bottom_wires[idx].append(
                            Adder(
                                self.bottom_wires[idx - offset][-1],
                                self.bottom_wires[idx][-1],
                            )
                        )
        for idx, wire in enumerate(self.top_wires):
            if len(wire) == 1 and idx:
                self.bottom_wires[idx].append(
                    Adder(self.bottom_wires[idx - 1][-1], self.bottom_wires[idx][-1])
                )

    def __init__(self, size: int):
        self.size = size
        # just making sure it's a legit power of two
        # assert size > 0 and size == 2 ** (size - 1).bit_length()
        # self.top_wires = [[f'w{idx}'] for idx in range(size)]
        self.top_wires = [[Value(None)] for idx in range(size)]
        self.create_top_circuit()
        self.bottom_wires = deepcopy(self.top_wires)
        self.create_bottom_circuit()
        self.wires = self.bottom_wires

    def calculate(self, binary_arr):
        assert len(binary_arr) == self.size
        for wire, res in zip(self.wires, binary_arr):
            wire[0].result = res
        output = []
        for wire in self.wires:
            wire[-1].update()
            output.append(wire[-1].result)
        return output


x = PrefixSumCircuit(SIZE)

# print(total_adders)
# print(x.calculate([1]*SIZE))

# print(x.wires)


def algorithm_1_adder_count(size):
    assert size > 0 and size == 2 ** (size - 1).bit_length()
    max_shift = size // 2
    shift = 1
    total = 0
    while shift <= max_shift:
        total += size - shift
        shift *= 2
    return total


# print(algorithm_1_adder_count(SIZE))

# just makes sure things don't end up with lines too long
# can group assign statements too, but just this for now and we'll see
# lol forgor wires are different sizes.


def wire_verilog_maker(wires):
    wires = sorted(wires, key=lambda x: x[1])  # sort by wire size then group
    groups = []
    widths = []
    for k, g in groupby(wires, key=lambda x: x[1]):
        groups.append(list(g))
        widths.append(k)
    lines = []
    for width, group in zip(widths, groups):
        for batch in batched(map(lambda x: x[0], group), 16):
            if width > 1:
                lines.append(f"wire [{width-1}:0] " + ", ".join(batch) + ";\n")
            else:
                lines.append(f"wire " + ", ".join(batch) + ";\n")
    return lines


def create_verilog_code(circuit):
    modules = []
    wires = []
    wire_assignments = []
    initializations = []
    for adder in adders:
        # Adder_# adder_# (in1, in2, out);
        initializations.append(
            f"Adder_{adder.id}_{SIZE} adder_{adder.id} ({adder.in1_wire}, {adder.in2_wire}, {adder.out_wire});\n"
        )
        wires.append((adder.in1_wire, adder.in1_width))
        wires.append((adder.in2_wire, adder.in2_width))
        wires.append((adder.out_wire, adder.out_width))
        if type(adder.left) == Adder:
            wire_assignments.append(
                f"assign {adder.in1_wire} = {adder.left.out_wire};\n"
            )
        if type(adder.right) == Adder:
            wire_assignments.append(
                f"assign {adder.in2_wire} = {adder.right.out_wire};\n"
            )
        in1_str = f"logic [{adder.in1_width - 1}:0] in1" if adder.in1_width > 1 else "logic in1"
        in2_str = f"logic [{adder.in2_width - 1}:0] in2" if adder.in2_width > 1 else "logic in2"
        string = f"""module Adder_{adder.id}_{SIZE} (
    input {in1_str},
    input {in2_str},
    output logic [{adder.out_width-1}:0] out
);
assign out = in1 + in2;
endmodule
"""
        modules.append(string)
    # handle input wires and output wires next
    output_size = circuit.size.bit_length()
    inputs = []
    outputs = []
    for idx, wire in enumerate(circuit.wires):
        wire[0].id = idx  # set value index

    for idx, wire in enumerate(circuit.wires):
        if len(wire) == 1:  # direct connect
            outputs.append(f"assign out[{idx}] = in[{idx}];\n")
        else:
            outputs.append(f"assign out[{idx}] = {wire[-1].out_wire};\n")
            if type(wire[1].left) == Value:
                inputs.append(f"assign {wire[1].in1_wire} = in[{wire[1].left.id}];\n")
            if type(wire[1].right) == Value:
                inputs.append(f"assign {wire[1].in2_wire} = in[{wire[1].right.id}];\n")

    top_mod = f"""`timescale 1ps / 1ps
module PrefixSum{SIZE} (
    input logic [{SIZE-1}:0] in,
    output logic [{output_size-1}:0] out [0:{SIZE-1}]
);

// wire creation
{"".join(wire_verilog_maker(wires))}
// wire assignment
{"".join(wire_assignments)}
// adder creation
{"".join(initializations)}
// wire inputs
{"".join(inputs)}
// wire outputs
{"".join(outputs)}
endmodule
"""
    modules = "\n".join(modules)
    return top_mod + "\n" + modules

# little test
# import random
# from itertools import accumulate
# for _ in range(1000):
#     x = PrefixSumCircuit(SIZE)
#     arr = [random.randint(0, 1) for _ in range(12)]
#     assert x.calculate(arr) == list(accumulate(arr))

if __name__ == "__main__":
    code = create_verilog_code(x)

    # Output file can be specified as second argument, otherwise use default
    if len(sys.argv) >= 3:
        output_file = sys.argv[2]
    else:
        output_file = f"generated/prefix_sum_{SIZE}.sv"

    with open(output_file, "w") as f:
        f.write(code)

    if len(sys.argv) >= 2:
        print(f"Generated PrefixSum{SIZE} -> {output_file}")

# LOL 502 adders instead of 1793. big improvement. will also figure out how small they can be
