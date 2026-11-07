from itertools import accumulate
import re

# LIFO_COUNT = 4
# DATA_WIDTH = 64
with open('decompressor/parameter_pkg.sv', 'r') as f:
    for line in f.read().splitlines():
        line = line.strip()
        if not line.startswith("//"):
            if 'LIFO_COUNT=' in line:
                LIFO_COUNT = int(re.search(r'\d+', line).group())
            elif 'DATA_WIDTH=' in line:
                DATA_WIDTH = int(re.search(r'\d+', line).group())
print(f"Generating for LIFO_COUNT={LIFO_COUNT} DATA_WIDTH={DATA_WIDTH}")
path = 'decompressor/partitioner_generated.sv'

from math import ceil, log2
LIFO_INPUT_WIDTH = ceil(DATA_WIDTH/LIFO_COUNT)
data_bit_width = ceil(log2(DATA_WIDTH+1))
lifo_input_bit_width = ceil(log2(LIFO_INPUT_WIDTH+1))
def create_verilog(data_width, lifo_count, lifo_input_width, path):
    with open(path, 'w') as f:
        f.write('''`timescale 1ps / 1ps
`default_nettype none
import parameter_pkg::*;
module Partitioner (
    input logic clk, enable,
    input  logic [7:0] compressed_data [DATA_WIDTH],
    input  logic [$clog2(DATA_WIDTH+1)-1:0] length,
    output logic [7:0] lifo_inputs [LIFO_COUNT][LIFO_INPUT_WIDTH],
    output logic [$clog2(LIFO_INPUT_WIDTH+1)-1:0] lengths [LIFO_COUNT]
);
always_ff @(posedge clk) begin
if (enable) begin
''')
        f.write(f'''for (int i=0; i<{lifo_count}; i++) begin
    for (int j=0; j<{lifo_input_width}; j++) begin
        lifo_inputs[i][j] <= '0;
    end
    lengths[i] <= '0;
end
''')
        f.write('case (length)\n')
        for i in range(1, data_width+1):
            part_lengths = [0] * lifo_count
            l_div_n = i // lifo_count
            l_mod_n = i % lifo_count
            for idx, _ in enumerate(part_lengths):
                part_lengths[idx] = l_div_n+1 if idx<l_mod_n else l_div_n
            lengths = list(accumulate(part_lengths, initial=0))
            f.write(' '*4+f"{data_bit_width}'d{i}: begin\n")
            for lifo_idx in range(lifo_count):
                start_idx = lengths[lifo_idx]
                # end_idx = lengths[lifo_idx+1]
                if part_lengths[lifo_idx]:
                    f.write(' '*8+f"for (int i=0; i<{lifo_input_width}; i++) begin\n")
                    f.write(' '*12+f"if (i<{part_lengths[lifo_idx]}) begin\n")
                    f.write(' '*16+f"lifo_inputs[{lifo_idx}][i]<=compressed_data[{start_idx}+i];\n")
                    f.write(' '*16+f"lengths[{lifo_idx}]<={lifo_input_bit_width}'d{part_lengths[lifo_idx]};\n")
                    f.write(' '*12+'end\n')
                    f.write(' '*8+'end\n')
            f.write(' '*4+f"end\n")
        f.write('endcase\n')
        f.write('''end
end
endmodule
''')

create_verilog(DATA_WIDTH, LIFO_COUNT, LIFO_INPUT_WIDTH, path)
