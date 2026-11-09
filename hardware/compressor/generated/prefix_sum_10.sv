`timescale 1ps / 1ps
module PrefixSum10 (
    input logic [9:0] in,
    output logic [3:0] out [0:9]
);

// wire creation
wire w_0_in1, w_0_in2, w_1_in1, w_1_in2, w_2_in1, w_2_in2, w_3_in1, w_3_in2, w_4_in1, w_4_in2, w_10_in2, w_11_in2, w_12_in2, w_13_in2;
wire [1:0] w_0_out, w_1_out, w_2_out, w_3_out, w_4_out, w_5_in1, w_5_in2, w_6_in1, w_6_in2, w_8_in2, w_9_in2, w_10_in1, w_10_out;
wire [2:0] w_5_out, w_6_out, w_7_in1, w_7_in2, w_8_in1, w_8_out, w_11_in1, w_11_out, w_12_in1, w_12_out;
wire [3:0] w_7_out, w_9_in1, w_9_out, w_13_in1, w_13_out;

// wire assignment
assign w_5_in1 = w_0_out;
assign w_5_in2 = w_1_out;
assign w_6_in1 = w_2_out;
assign w_6_in2 = w_3_out;
assign w_7_in1 = w_5_out;
assign w_7_in2 = w_6_out;
assign w_8_in1 = w_5_out;
assign w_8_in2 = w_2_out;
assign w_9_in1 = w_7_out;
assign w_9_in2 = w_4_out;
assign w_10_in1 = w_0_out;
assign w_11_in1 = w_5_out;
assign w_12_in1 = w_8_out;
assign w_13_in1 = w_7_out;

// adder creation
Adder_0_10 adder_0 (w_0_in1, w_0_in2, w_0_out);
Adder_1_10 adder_1 (w_1_in1, w_1_in2, w_1_out);
Adder_2_10 adder_2 (w_2_in1, w_2_in2, w_2_out);
Adder_3_10 adder_3 (w_3_in1, w_3_in2, w_3_out);
Adder_4_10 adder_4 (w_4_in1, w_4_in2, w_4_out);
Adder_5_10 adder_5 (w_5_in1, w_5_in2, w_5_out);
Adder_6_10 adder_6 (w_6_in1, w_6_in2, w_6_out);
Adder_7_10 adder_7 (w_7_in1, w_7_in2, w_7_out);
Adder_8_10 adder_8 (w_8_in1, w_8_in2, w_8_out);
Adder_9_10 adder_9 (w_9_in1, w_9_in2, w_9_out);
Adder_10_10 adder_10 (w_10_in1, w_10_in2, w_10_out);
Adder_11_10 adder_11 (w_11_in1, w_11_in2, w_11_out);
Adder_12_10 adder_12 (w_12_in1, w_12_in2, w_12_out);
Adder_13_10 adder_13 (w_13_in1, w_13_in2, w_13_out);

// wire inputs
assign w_0_in1 = in[0];
assign w_0_in2 = in[1];
assign w_10_in2 = in[2];
assign w_1_in1 = in[2];
assign w_1_in2 = in[3];
assign w_11_in2 = in[4];
assign w_2_in1 = in[4];
assign w_2_in2 = in[5];
assign w_12_in2 = in[6];
assign w_3_in1 = in[6];
assign w_3_in2 = in[7];
assign w_13_in2 = in[8];
assign w_4_in1 = in[8];
assign w_4_in2 = in[9];

// wire outputs
assign out[0] = in[0];
assign out[1] = w_0_out;
assign out[2] = w_10_out;
assign out[3] = w_5_out;
assign out[4] = w_11_out;
assign out[5] = w_8_out;
assign out[6] = w_12_out;
assign out[7] = w_7_out;
assign out[8] = w_13_out;
assign out[9] = w_9_out;

endmodule

module Adder_0_10 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_1_10 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_2_10 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_3_10 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_4_10 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_5_10 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_6_10 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_7_10 (
    input logic [2:0] in1,
    input logic [2:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_8_10 (
    input logic [2:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_9_10 (
    input logic [3:0] in1,
    input logic [1:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_10_10 (
    input logic [1:0] in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_11_10 (
    input logic [2:0] in1,
    input logic in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_12_10 (
    input logic [2:0] in1,
    input logic in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_13_10 (
    input logic [3:0] in1,
    input logic in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule
