`timescale 1ps / 1ps
module PrefixSum16 (
    input logic [15:0] in,
    output logic [4:0] out [0:15]
);

// wire creation
wire w_0_in1, w_0_in2, w_1_in1, w_1_in2, w_2_in1, w_2_in2, w_3_in1, w_3_in2, w_4_in1, w_4_in2, w_5_in1, w_5_in2, w_6_in1, w_6_in2, w_7_in1, w_7_in2;
wire w_19_in2, w_20_in2, w_21_in2, w_22_in2, w_23_in2, w_24_in2, w_25_in2;
wire [1:0] w_0_out, w_1_out, w_2_out, w_3_out, w_4_out, w_5_out, w_6_out, w_7_out, w_8_in1, w_8_in2, w_9_in1, w_9_in2, w_10_in1, w_10_in2, w_11_in1, w_11_in2;
wire [1:0] w_16_in2, w_17_in2, w_18_in2, w_19_in1, w_19_out;
wire [2:0] w_8_out, w_9_out, w_10_out, w_11_out, w_12_in1, w_12_in2, w_13_in1, w_13_in2, w_15_in2, w_16_in1, w_16_out, w_20_in1, w_20_out, w_21_in1, w_21_out;
wire [3:0] w_12_out, w_13_out, w_14_in1, w_14_in2, w_15_in1, w_15_out, w_17_in1, w_17_out, w_18_in1, w_18_out, w_22_in1, w_22_out, w_23_in1, w_23_out, w_24_in1, w_24_out;
wire [3:0] w_25_in1, w_25_out;
wire [4:0] w_14_out;

// wire assignment
assign w_8_in1 = w_0_out;
assign w_8_in2 = w_1_out;
assign w_9_in1 = w_2_out;
assign w_9_in2 = w_3_out;
assign w_10_in1 = w_4_out;
assign w_10_in2 = w_5_out;
assign w_11_in1 = w_6_out;
assign w_11_in2 = w_7_out;
assign w_12_in1 = w_8_out;
assign w_12_in2 = w_9_out;
assign w_13_in1 = w_10_out;
assign w_13_in2 = w_11_out;
assign w_14_in1 = w_12_out;
assign w_14_in2 = w_13_out;
assign w_15_in1 = w_12_out;
assign w_15_in2 = w_10_out;
assign w_16_in1 = w_8_out;
assign w_16_in2 = w_2_out;
assign w_17_in1 = w_12_out;
assign w_17_in2 = w_4_out;
assign w_18_in1 = w_15_out;
assign w_18_in2 = w_6_out;
assign w_19_in1 = w_0_out;
assign w_20_in1 = w_8_out;
assign w_21_in1 = w_16_out;
assign w_22_in1 = w_12_out;
assign w_23_in1 = w_17_out;
assign w_24_in1 = w_15_out;
assign w_25_in1 = w_18_out;

// adder creation
Adder_0_16 adder_0 (w_0_in1, w_0_in2, w_0_out);
Adder_1_16 adder_1 (w_1_in1, w_1_in2, w_1_out);
Adder_2_16 adder_2 (w_2_in1, w_2_in2, w_2_out);
Adder_3_16 adder_3 (w_3_in1, w_3_in2, w_3_out);
Adder_4_16 adder_4 (w_4_in1, w_4_in2, w_4_out);
Adder_5_16 adder_5 (w_5_in1, w_5_in2, w_5_out);
Adder_6_16 adder_6 (w_6_in1, w_6_in2, w_6_out);
Adder_7_16 adder_7 (w_7_in1, w_7_in2, w_7_out);
Adder_8_16 adder_8 (w_8_in1, w_8_in2, w_8_out);
Adder_9_16 adder_9 (w_9_in1, w_9_in2, w_9_out);
Adder_10_16 adder_10 (w_10_in1, w_10_in2, w_10_out);
Adder_11_16 adder_11 (w_11_in1, w_11_in2, w_11_out);
Adder_12_16 adder_12 (w_12_in1, w_12_in2, w_12_out);
Adder_13_16 adder_13 (w_13_in1, w_13_in2, w_13_out);
Adder_14_16 adder_14 (w_14_in1, w_14_in2, w_14_out);
Adder_15_16 adder_15 (w_15_in1, w_15_in2, w_15_out);
Adder_16_16 adder_16 (w_16_in1, w_16_in2, w_16_out);
Adder_17_16 adder_17 (w_17_in1, w_17_in2, w_17_out);
Adder_18_16 adder_18 (w_18_in1, w_18_in2, w_18_out);
Adder_19_16 adder_19 (w_19_in1, w_19_in2, w_19_out);
Adder_20_16 adder_20 (w_20_in1, w_20_in2, w_20_out);
Adder_21_16 adder_21 (w_21_in1, w_21_in2, w_21_out);
Adder_22_16 adder_22 (w_22_in1, w_22_in2, w_22_out);
Adder_23_16 adder_23 (w_23_in1, w_23_in2, w_23_out);
Adder_24_16 adder_24 (w_24_in1, w_24_in2, w_24_out);
Adder_25_16 adder_25 (w_25_in1, w_25_in2, w_25_out);

// wire inputs
assign w_0_in1 = in[0];
assign w_0_in2 = in[1];
assign w_19_in2 = in[2];
assign w_1_in1 = in[2];
assign w_1_in2 = in[3];
assign w_20_in2 = in[4];
assign w_2_in1 = in[4];
assign w_2_in2 = in[5];
assign w_21_in2 = in[6];
assign w_3_in1 = in[6];
assign w_3_in2 = in[7];
assign w_22_in2 = in[8];
assign w_4_in1 = in[8];
assign w_4_in2 = in[9];
assign w_23_in2 = in[10];
assign w_5_in1 = in[10];
assign w_5_in2 = in[11];
assign w_24_in2 = in[12];
assign w_6_in1 = in[12];
assign w_6_in2 = in[13];
assign w_25_in2 = in[14];
assign w_7_in1 = in[14];
assign w_7_in2 = in[15];

// wire outputs
assign out[0] = in[0];
assign out[1] = w_0_out;
assign out[2] = w_19_out;
assign out[3] = w_8_out;
assign out[4] = w_20_out;
assign out[5] = w_16_out;
assign out[6] = w_21_out;
assign out[7] = w_12_out;
assign out[8] = w_22_out;
assign out[9] = w_17_out;
assign out[10] = w_23_out;
assign out[11] = w_15_out;
assign out[12] = w_24_out;
assign out[13] = w_18_out;
assign out[14] = w_25_out;
assign out[15] = w_14_out;

endmodule

module Adder_0_16 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_1_16 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_2_16 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_3_16 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_4_16 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_5_16 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_6_16 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_7_16 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_8_16 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_9_16 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_10_16 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_11_16 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_12_16 (
    input logic [2:0] in1,
    input logic [2:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_13_16 (
    input logic [2:0] in1,
    input logic [2:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_14_16 (
    input logic [3:0] in1,
    input logic [3:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_15_16 (
    input logic [3:0] in1,
    input logic [2:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_16_16 (
    input logic [2:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_17_16 (
    input logic [3:0] in1,
    input logic [1:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_18_16 (
    input logic [3:0] in1,
    input logic [1:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_19_16 (
    input logic [1:0] in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_20_16 (
    input logic [2:0] in1,
    input logic in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_21_16 (
    input logic [2:0] in1,
    input logic in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_22_16 (
    input logic [3:0] in1,
    input logic in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_23_16 (
    input logic [3:0] in1,
    input logic in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_24_16 (
    input logic [3:0] in1,
    input logic in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_25_16 (
    input logic [3:0] in1,
    input logic in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule
