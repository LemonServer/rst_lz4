`timescale 1ps / 1ps
module PrefixSum32 (
    input logic [31:0] in,
    output logic [5:0] out [0:31]
);

// wire creation
wire w_0_in1, w_0_in2, w_1_in1, w_1_in2, w_2_in1, w_2_in2, w_3_in1, w_3_in2, w_4_in1, w_4_in2, w_5_in1, w_5_in2, w_6_in1, w_6_in2, w_7_in1, w_7_in2;
wire w_8_in1, w_8_in2, w_9_in1, w_9_in2, w_10_in1, w_10_in2, w_11_in1, w_11_in2, w_12_in1, w_12_in2, w_13_in1, w_13_in2, w_14_in1, w_14_in2, w_15_in1, w_15_in2;
wire w_42_in2, w_43_in2, w_44_in2, w_45_in2, w_46_in2, w_47_in2, w_48_in2, w_49_in2, w_50_in2, w_51_in2, w_52_in2, w_53_in2, w_54_in2, w_55_in2, w_56_in2;
wire [1:0] w_0_out, w_1_out, w_2_out, w_3_out, w_4_out, w_5_out, w_6_out, w_7_out, w_8_out, w_9_out, w_10_out, w_11_out, w_12_out, w_13_out, w_14_out, w_15_out;
wire [1:0] w_16_in1, w_16_in2, w_17_in1, w_17_in2, w_18_in1, w_18_in2, w_19_in1, w_19_in2, w_20_in1, w_20_in2, w_21_in1, w_21_in2, w_22_in1, w_22_in2, w_23_in1, w_23_in2;
wire [1:0] w_35_in2, w_36_in2, w_37_in2, w_38_in2, w_39_in2, w_40_in2, w_41_in2, w_42_in1, w_42_out;
wire [2:0] w_16_out, w_17_out, w_18_out, w_19_out, w_20_out, w_21_out, w_22_out, w_23_out, w_24_in1, w_24_in2, w_25_in1, w_25_in2, w_26_in1, w_26_in2, w_27_in1, w_27_in2;
wire [2:0] w_32_in2, w_33_in2, w_34_in2, w_35_in1, w_35_out, w_43_in1, w_43_out, w_44_in1, w_44_out;
wire [3:0] w_24_out, w_25_out, w_26_out, w_27_out, w_28_in1, w_28_in2, w_29_in1, w_29_in2, w_31_in2, w_32_in1, w_32_out, w_36_in1, w_36_out, w_37_in1, w_37_out, w_45_in1;
wire [3:0] w_45_out, w_46_in1, w_46_out, w_47_in1, w_47_out, w_48_in1, w_48_out;
wire [4:0] w_28_out, w_29_out, w_30_in1, w_30_in2, w_31_in1, w_31_out, w_33_in1, w_33_out, w_34_in1, w_34_out, w_38_in1, w_38_out, w_39_in1, w_39_out, w_40_in1, w_40_out;
wire [4:0] w_41_in1, w_41_out, w_49_in1, w_49_out, w_50_in1, w_50_out, w_51_in1, w_51_out, w_52_in1, w_52_out, w_53_in1, w_53_out, w_54_in1, w_54_out, w_55_in1, w_55_out;
wire [4:0] w_56_in1, w_56_out;
wire [5:0] w_30_out;

// wire assignment
assign w_16_in1 = w_0_out;
assign w_16_in2 = w_1_out;
assign w_17_in1 = w_2_out;
assign w_17_in2 = w_3_out;
assign w_18_in1 = w_4_out;
assign w_18_in2 = w_5_out;
assign w_19_in1 = w_6_out;
assign w_19_in2 = w_7_out;
assign w_20_in1 = w_8_out;
assign w_20_in2 = w_9_out;
assign w_21_in1 = w_10_out;
assign w_21_in2 = w_11_out;
assign w_22_in1 = w_12_out;
assign w_22_in2 = w_13_out;
assign w_23_in1 = w_14_out;
assign w_23_in2 = w_15_out;
assign w_24_in1 = w_16_out;
assign w_24_in2 = w_17_out;
assign w_25_in1 = w_18_out;
assign w_25_in2 = w_19_out;
assign w_26_in1 = w_20_out;
assign w_26_in2 = w_21_out;
assign w_27_in1 = w_22_out;
assign w_27_in2 = w_23_out;
assign w_28_in1 = w_24_out;
assign w_28_in2 = w_25_out;
assign w_29_in1 = w_26_out;
assign w_29_in2 = w_27_out;
assign w_30_in1 = w_28_out;
assign w_30_in2 = w_29_out;
assign w_31_in1 = w_28_out;
assign w_31_in2 = w_26_out;
assign w_32_in1 = w_24_out;
assign w_32_in2 = w_18_out;
assign w_33_in1 = w_28_out;
assign w_33_in2 = w_20_out;
assign w_34_in1 = w_31_out;
assign w_34_in2 = w_22_out;
assign w_35_in1 = w_16_out;
assign w_35_in2 = w_2_out;
assign w_36_in1 = w_24_out;
assign w_36_in2 = w_4_out;
assign w_37_in1 = w_32_out;
assign w_37_in2 = w_6_out;
assign w_38_in1 = w_28_out;
assign w_38_in2 = w_8_out;
assign w_39_in1 = w_33_out;
assign w_39_in2 = w_10_out;
assign w_40_in1 = w_31_out;
assign w_40_in2 = w_12_out;
assign w_41_in1 = w_34_out;
assign w_41_in2 = w_14_out;
assign w_42_in1 = w_0_out;
assign w_43_in1 = w_16_out;
assign w_44_in1 = w_35_out;
assign w_45_in1 = w_24_out;
assign w_46_in1 = w_36_out;
assign w_47_in1 = w_32_out;
assign w_48_in1 = w_37_out;
assign w_49_in1 = w_28_out;
assign w_50_in1 = w_38_out;
assign w_51_in1 = w_33_out;
assign w_52_in1 = w_39_out;
assign w_53_in1 = w_31_out;
assign w_54_in1 = w_40_out;
assign w_55_in1 = w_34_out;
assign w_56_in1 = w_41_out;

// adder creation
Adder_0_32 adder_0 (w_0_in1, w_0_in2, w_0_out);
Adder_1_32 adder_1 (w_1_in1, w_1_in2, w_1_out);
Adder_2_32 adder_2 (w_2_in1, w_2_in2, w_2_out);
Adder_3_32 adder_3 (w_3_in1, w_3_in2, w_3_out);
Adder_4_32 adder_4 (w_4_in1, w_4_in2, w_4_out);
Adder_5_32 adder_5 (w_5_in1, w_5_in2, w_5_out);
Adder_6_32 adder_6 (w_6_in1, w_6_in2, w_6_out);
Adder_7_32 adder_7 (w_7_in1, w_7_in2, w_7_out);
Adder_8_32 adder_8 (w_8_in1, w_8_in2, w_8_out);
Adder_9_32 adder_9 (w_9_in1, w_9_in2, w_9_out);
Adder_10_32 adder_10 (w_10_in1, w_10_in2, w_10_out);
Adder_11_32 adder_11 (w_11_in1, w_11_in2, w_11_out);
Adder_12_32 adder_12 (w_12_in1, w_12_in2, w_12_out);
Adder_13_32 adder_13 (w_13_in1, w_13_in2, w_13_out);
Adder_14_32 adder_14 (w_14_in1, w_14_in2, w_14_out);
Adder_15_32 adder_15 (w_15_in1, w_15_in2, w_15_out);
Adder_16_32 adder_16 (w_16_in1, w_16_in2, w_16_out);
Adder_17_32 adder_17 (w_17_in1, w_17_in2, w_17_out);
Adder_18_32 adder_18 (w_18_in1, w_18_in2, w_18_out);
Adder_19_32 adder_19 (w_19_in1, w_19_in2, w_19_out);
Adder_20_32 adder_20 (w_20_in1, w_20_in2, w_20_out);
Adder_21_32 adder_21 (w_21_in1, w_21_in2, w_21_out);
Adder_22_32 adder_22 (w_22_in1, w_22_in2, w_22_out);
Adder_23_32 adder_23 (w_23_in1, w_23_in2, w_23_out);
Adder_24_32 adder_24 (w_24_in1, w_24_in2, w_24_out);
Adder_25_32 adder_25 (w_25_in1, w_25_in2, w_25_out);
Adder_26_32 adder_26 (w_26_in1, w_26_in2, w_26_out);
Adder_27_32 adder_27 (w_27_in1, w_27_in2, w_27_out);
Adder_28_32 adder_28 (w_28_in1, w_28_in2, w_28_out);
Adder_29_32 adder_29 (w_29_in1, w_29_in2, w_29_out);
Adder_30_32 adder_30 (w_30_in1, w_30_in2, w_30_out);
Adder_31_32 adder_31 (w_31_in1, w_31_in2, w_31_out);
Adder_32_32 adder_32 (w_32_in1, w_32_in2, w_32_out);
Adder_33_32 adder_33 (w_33_in1, w_33_in2, w_33_out);
Adder_34_32 adder_34 (w_34_in1, w_34_in2, w_34_out);
Adder_35_32 adder_35 (w_35_in1, w_35_in2, w_35_out);
Adder_36_32 adder_36 (w_36_in1, w_36_in2, w_36_out);
Adder_37_32 adder_37 (w_37_in1, w_37_in2, w_37_out);
Adder_38_32 adder_38 (w_38_in1, w_38_in2, w_38_out);
Adder_39_32 adder_39 (w_39_in1, w_39_in2, w_39_out);
Adder_40_32 adder_40 (w_40_in1, w_40_in2, w_40_out);
Adder_41_32 adder_41 (w_41_in1, w_41_in2, w_41_out);
Adder_42_32 adder_42 (w_42_in1, w_42_in2, w_42_out);
Adder_43_32 adder_43 (w_43_in1, w_43_in2, w_43_out);
Adder_44_32 adder_44 (w_44_in1, w_44_in2, w_44_out);
Adder_45_32 adder_45 (w_45_in1, w_45_in2, w_45_out);
Adder_46_32 adder_46 (w_46_in1, w_46_in2, w_46_out);
Adder_47_32 adder_47 (w_47_in1, w_47_in2, w_47_out);
Adder_48_32 adder_48 (w_48_in1, w_48_in2, w_48_out);
Adder_49_32 adder_49 (w_49_in1, w_49_in2, w_49_out);
Adder_50_32 adder_50 (w_50_in1, w_50_in2, w_50_out);
Adder_51_32 adder_51 (w_51_in1, w_51_in2, w_51_out);
Adder_52_32 adder_52 (w_52_in1, w_52_in2, w_52_out);
Adder_53_32 adder_53 (w_53_in1, w_53_in2, w_53_out);
Adder_54_32 adder_54 (w_54_in1, w_54_in2, w_54_out);
Adder_55_32 adder_55 (w_55_in1, w_55_in2, w_55_out);
Adder_56_32 adder_56 (w_56_in1, w_56_in2, w_56_out);

// wire inputs
assign w_0_in1 = in[0];
assign w_0_in2 = in[1];
assign w_42_in2 = in[2];
assign w_1_in1 = in[2];
assign w_1_in2 = in[3];
assign w_43_in2 = in[4];
assign w_2_in1 = in[4];
assign w_2_in2 = in[5];
assign w_44_in2 = in[6];
assign w_3_in1 = in[6];
assign w_3_in2 = in[7];
assign w_45_in2 = in[8];
assign w_4_in1 = in[8];
assign w_4_in2 = in[9];
assign w_46_in2 = in[10];
assign w_5_in1 = in[10];
assign w_5_in2 = in[11];
assign w_47_in2 = in[12];
assign w_6_in1 = in[12];
assign w_6_in2 = in[13];
assign w_48_in2 = in[14];
assign w_7_in1 = in[14];
assign w_7_in2 = in[15];
assign w_49_in2 = in[16];
assign w_8_in1 = in[16];
assign w_8_in2 = in[17];
assign w_50_in2 = in[18];
assign w_9_in1 = in[18];
assign w_9_in2 = in[19];
assign w_51_in2 = in[20];
assign w_10_in1 = in[20];
assign w_10_in2 = in[21];
assign w_52_in2 = in[22];
assign w_11_in1 = in[22];
assign w_11_in2 = in[23];
assign w_53_in2 = in[24];
assign w_12_in1 = in[24];
assign w_12_in2 = in[25];
assign w_54_in2 = in[26];
assign w_13_in1 = in[26];
assign w_13_in2 = in[27];
assign w_55_in2 = in[28];
assign w_14_in1 = in[28];
assign w_14_in2 = in[29];
assign w_56_in2 = in[30];
assign w_15_in1 = in[30];
assign w_15_in2 = in[31];

// wire outputs
assign out[0] = in[0];
assign out[1] = w_0_out;
assign out[2] = w_42_out;
assign out[3] = w_16_out;
assign out[4] = w_43_out;
assign out[5] = w_35_out;
assign out[6] = w_44_out;
assign out[7] = w_24_out;
assign out[8] = w_45_out;
assign out[9] = w_36_out;
assign out[10] = w_46_out;
assign out[11] = w_32_out;
assign out[12] = w_47_out;
assign out[13] = w_37_out;
assign out[14] = w_48_out;
assign out[15] = w_28_out;
assign out[16] = w_49_out;
assign out[17] = w_38_out;
assign out[18] = w_50_out;
assign out[19] = w_33_out;
assign out[20] = w_51_out;
assign out[21] = w_39_out;
assign out[22] = w_52_out;
assign out[23] = w_31_out;
assign out[24] = w_53_out;
assign out[25] = w_40_out;
assign out[26] = w_54_out;
assign out[27] = w_34_out;
assign out[28] = w_55_out;
assign out[29] = w_41_out;
assign out[30] = w_56_out;
assign out[31] = w_30_out;

endmodule

module Adder_0_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_1_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_2_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_3_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_4_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_5_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_6_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_7_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_8_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_9_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_10_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_11_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_12_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_13_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_14_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_15_32 (
    input logic in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_16_32 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_17_32 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_18_32 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_19_32 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_20_32 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_21_32 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_22_32 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_23_32 (
    input logic [1:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_24_32 (
    input logic [2:0] in1,
    input logic [2:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_25_32 (
    input logic [2:0] in1,
    input logic [2:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_26_32 (
    input logic [2:0] in1,
    input logic [2:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_27_32 (
    input logic [2:0] in1,
    input logic [2:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_28_32 (
    input logic [3:0] in1,
    input logic [3:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_29_32 (
    input logic [3:0] in1,
    input logic [3:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_30_32 (
    input logic [4:0] in1,
    input logic [4:0] in2,
    output logic [5:0] out
);
assign out = in1 + in2;
endmodule

module Adder_31_32 (
    input logic [4:0] in1,
    input logic [3:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_32_32 (
    input logic [3:0] in1,
    input logic [2:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_33_32 (
    input logic [4:0] in1,
    input logic [2:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_34_32 (
    input logic [4:0] in1,
    input logic [2:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_35_32 (
    input logic [2:0] in1,
    input logic [1:0] in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_36_32 (
    input logic [3:0] in1,
    input logic [1:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_37_32 (
    input logic [3:0] in1,
    input logic [1:0] in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_38_32 (
    input logic [4:0] in1,
    input logic [1:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_39_32 (
    input logic [4:0] in1,
    input logic [1:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_40_32 (
    input logic [4:0] in1,
    input logic [1:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_41_32 (
    input logic [4:0] in1,
    input logic [1:0] in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_42_32 (
    input logic [1:0] in1,
    input logic in2,
    output logic [1:0] out
);
assign out = in1 + in2;
endmodule

module Adder_43_32 (
    input logic [2:0] in1,
    input logic in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_44_32 (
    input logic [2:0] in1,
    input logic in2,
    output logic [2:0] out
);
assign out = in1 + in2;
endmodule

module Adder_45_32 (
    input logic [3:0] in1,
    input logic in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_46_32 (
    input logic [3:0] in1,
    input logic in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_47_32 (
    input logic [3:0] in1,
    input logic in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_48_32 (
    input logic [3:0] in1,
    input logic in2,
    output logic [3:0] out
);
assign out = in1 + in2;
endmodule

module Adder_49_32 (
    input logic [4:0] in1,
    input logic in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_50_32 (
    input logic [4:0] in1,
    input logic in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_51_32 (
    input logic [4:0] in1,
    input logic in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_52_32 (
    input logic [4:0] in1,
    input logic in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_53_32 (
    input logic [4:0] in1,
    input logic in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_54_32 (
    input logic [4:0] in1,
    input logic in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_55_32 (
    input logic [4:0] in1,
    input logic in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule

module Adder_56_32 (
    input logic [4:0] in1,
    input logic in2,
    output logic [4:0] out
);
assign out = in1 + in2;
endmodule
