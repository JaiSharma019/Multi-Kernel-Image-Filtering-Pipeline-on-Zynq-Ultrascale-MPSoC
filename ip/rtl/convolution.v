`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/20/2026 03:22:18 PM
// Design Name: 
// Module Name: convolution
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module convolution #(
    parameter W_IN = 512,
    parameter H_IN = 512,
    parameter DATA_WIDTH = 8,
    parameter KERNEL = 2
)(
    input clk,
    input reset_n,
    
    // upstream interface
    input [9*DATA_WIDTH-1:0] window_data_i,
    input window_valid_i,
    input tlast_i,
    
    input ready_i,
    output ready_o,
    
    // downstream interface
    output reg conv_valid_o,
    output reg [DATA_WIDTH-1:0] pixel_o,
    output reg tlast_o
    );
    
    localparam MULT_WIDTH = DATA_WIDTH + 9;
    localparam SUM_WIDTH  = MULT_WIDTH + 2;
    localparam PIXEL_WIDTH = SUM_WIDTH + 2;
    
    // KERNELS
    // 0: Identity kernel
    localparam signed [7:0] ID_W00 = 0, ID_W01 = 0, ID_W02 = 0;
    localparam signed [7:0] ID_W10 = 0, ID_W11 = 1, ID_W12 = 0;
    localparam signed [7:0] ID_W20 = 0, ID_W21 = 0, ID_W22 = 0;

    // 1: Gaussian Blur (divide by 16 later)
    localparam signed [7:0] BL_W00 = 1, BL_W01 = 2, BL_W02 = 1;
    localparam signed [7:0] BL_W10 = 2, BL_W11 = 4, BL_W12 = 2;
    localparam signed [7:0] BL_W20 = 1, BL_W21 = 2, BL_W22 = 1;

    // 2: Sobel X (Vertical Edge Detection)
    localparam signed [7:0] SX_W00 = -1, SX_W01 = 0, SX_W02 = 1;
    localparam signed [7:0] SX_W10 = -2, SX_W11 = 0, SX_W12 = 2;
    localparam signed [7:0] SX_W20 = -1, SX_W21 = 0, SX_W22 = 1;
    
    // 3: Full Sobel  (Horizontal & Vertical Edge Detection)
    localparam signed [7:0] SY_W00 = -1, SY_W01 = -2, SY_W02 = -1;
    localparam signed [7:0] SY_W10 =  0, SY_W11 =  0, SY_W12 =  0;
    localparam signed [7:0] SY_W20 =  1, SY_W21 =  2, SY_W22 =  1;
    
    // 4: Sharpen filter
    localparam signed [7:0] SP_W00 =  0, SP_W01 = -1, SP_W02 =  0;
    localparam signed [7:0] SP_W10 = -1, SP_W11 =  5, SP_W12 = -1;
    localparam signed [7:0] SP_W20 =  0, SP_W21 = -1, SP_W22 =  0;
    
    // 5: Scharr Edge detection
    // Scharr X
    localparam signed [7:0] SCX_W00 =  -3, SCX_W01 = 0, SCX_W02 =  3;
    localparam signed [7:0] SCX_W10 = -10, SCX_W11 = 0, SCX_W12 = 10;
    localparam signed [7:0] SCX_W20 =  -3, SCX_W21 = 0, SCX_W22 =  3;
    // Scharr Y
    localparam signed [7:0] SCY_W00 = -3, SCY_W01 = -10, SCY_W02 = -3;
    localparam signed [7:0] SCY_W10 =  0, SCY_W11 =   0, SCY_W12 =  0;
    localparam signed [7:0] SCY_W20 =  3, SCY_W21 =  10, SCY_W22 =  3;


    wire [DATA_WIDTH-1:0] p00, p01, p02;
    wire [DATA_WIDTH-1:0] p10, p11, p12;
    wire [DATA_WIDTH-1:0] p20, p21, p22;
    
    assign p00 = window_data_i[DATA_WIDTH-1:0];
    assign p01 = window_data_i[2*DATA_WIDTH-1:DATA_WIDTH];
    assign p02 = window_data_i[3*DATA_WIDTH-1:2*DATA_WIDTH];
    assign p10 = window_data_i[4*DATA_WIDTH-1:3*DATA_WIDTH];
    assign p11 = window_data_i[5*DATA_WIDTH-1:4*DATA_WIDTH];
    assign p12 = window_data_i[6*DATA_WIDTH-1:5*DATA_WIDTH];
    assign p20 = window_data_i[7*DATA_WIDTH-1:6*DATA_WIDTH];
    assign p21 = window_data_i[8*DATA_WIDTH-1:7*DATA_WIDTH];
    assign p22 = window_data_i[9*DATA_WIDTH-1:8*DATA_WIDTH];
    
    wire signed [7:0] wA00, wA01, wA02, wA10, wA11, wA12, wA20, wA21, wA22; // Path 1
    wire signed [7:0] wB00, wB01, wB02, wB10, wB11, wB12, wB20, wB21, wB22; // Path 2
    
    generate
        case (KERNEL)
            1: begin : GEN_BLUR
                assign wA00 = BL_W00; assign wA01 = BL_W01; assign wA02 = BL_W02;
                assign wA10 = BL_W10; assign wA11 = BL_W11; assign wA12 = BL_W12;
                assign wA20 = BL_W20; assign wA21 = BL_W21; assign wA22 = BL_W22;
                assign wB00 = 8'd0; assign wB01 = 8'd0; assign wB02 = 8'd0;
                assign wB10 = 8'd0; assign wB11 = 8'd0; assign wB12 = 8'd0;
                assign wB20 = 8'd0; assign wB21 = 8'd0; assign wB22 = 8'd0;
            end
            2: begin : GEN_SOBEL_X
                assign wA00 = SX_W00; assign wA01 = SX_W01; assign wA02 = SX_W02;
                assign wA10 = SX_W10; assign wA11 = SX_W11; assign wA12 = SX_W12;
                assign wA20 = SX_W20; assign wA21 = SX_W21; assign wA22 = SX_W22;
                assign wB00 = 8'd0; assign wB01 = 8'd0; assign wB02 = 8'd0;
                assign wB10 = 8'd0; assign wB11 = 8'd0; assign wB12 = 8'd0;
                assign wB20 = 8'd0; assign wB21 = 8'd0; assign wB22 = 8'd0;
            end
            3: begin : GEN_FULL_SOBEL
                assign wA00 = SX_W00; assign wA01 = SX_W01; assign wA02 = SX_W02;
                assign wA10 = SX_W10; assign wA11 = SX_W11; assign wA12 = SX_W12;
                assign wA20 = SX_W20; assign wA21 = SX_W21; assign wA22 = SX_W22;
                assign wB00 = SY_W00; assign wB01 = SY_W01; assign wB02 = SY_W02;
                assign wB10 = SY_W10; assign wB11 = SY_W11; assign wB12 = SY_W12;
                assign wB20 = SY_W20; assign wB21 = SY_W21; assign wB22 = SY_W22;
            end
            4: begin : GEN_SHARP
                assign wA00 = SP_W00; assign wA01 = SP_W01; assign wA02 = SP_W02;
                assign wA10 = SP_W10; assign wA11 = SP_W11; assign wA12 = SP_W12;
                assign wA20 = SP_W20; assign wA21 = SP_W21; assign wA22 = SP_W22;
                assign wB00 = 8'd0; assign wB01 = 8'd0; assign wB02 = 8'd0;
                assign wB10 = 8'd0; assign wB11 = 8'd0; assign wB12 = 8'd0;
                assign wB20 = 8'd0; assign wB21 = 8'd0; assign wB22 = 8'd0;
            end
            5: begin : GEN_SCHARR 
                assign wA00 = SCX_W00; assign wA01 = SCX_W01; assign wA02 = SCX_W02;
                assign wA10 = SCX_W10; assign wA11 = SCX_W11; assign wA12 = SCX_W12;
                assign wA20 = SCX_W20; assign wA21 = SCX_W21; assign wA22 = SCX_W22;
                assign wB00 = SCY_W00; assign wB01 = SCY_W01; assign wB02 = SCY_W02;
                assign wB10 = SCY_W10; assign wB11 = SCY_W11; assign wB12 = SCY_W12;
                assign wB20 = SCY_W20; assign wB21 = SCY_W21; assign wB22 = SCY_W22;
            end
            default: begin : GEN_IDENTITY
                assign wA00 = ID_W00; assign wA01 = ID_W01; assign wA02 = ID_W02;
                assign wA10 = ID_W10; assign wA11 = ID_W11; assign wA12 = ID_W12;
                assign wA20 = ID_W20; assign wA21 = ID_W21; assign wA22 = ID_W22;
                assign wB00 = 8'd0; assign wB01 = 8'd0; assign wB02 = 8'd0;
                assign wB10 = 8'd0; assign wB11 = 8'd0; assign wB12 = 8'd0;
                assign wB20 = 8'd0; assign wB21 = 8'd0; assign wB22 = 8'd0;
            end
        endcase
    endgenerate
    


    // MAC pipeline
    reg signed [MULT_WIDTH-1:0] multA00, multA01, multA02;
    reg signed [MULT_WIDTH-1:0] multA10, multA11, multA12;
    reg signed [MULT_WIDTH-1:0] multA20, multA21, multA22;
    
    reg signed [MULT_WIDTH-1:0] multB00, multB01, multB02;
    reg signed [MULT_WIDTH-1:0] multB10, multB11, multB12;
    reg signed [MULT_WIDTH-1:0] multB20, multB21, multB22;
    
    reg [2:0] stage;
    reg [2:0] tlast_reg;
    // pipeline will be shifting when we are ready
    assign ready_o = ready_i || ~conv_valid_o;
    wire enable = ready_o;
    // stage 1
    always@(posedge clk) begin 
        if (!reset_n) begin 
            multA00 <= 0; multA01 <= 0; multA02 <= 0;
            multA10 <= 0; multA11 <= 0; multA12 <= 0;
            multA20 <= 0; multA21 <= 0; multA22 <= 0;
            multB00 <= 0; multB01 <= 0; multB02 <= 0;
            multB10 <= 0; multB11 <= 0; multB12 <= 0;
            multB20 <= 0; multB21 <= 0; multB22 <= 0;
            stage[0] <= 1'b0;
            tlast_reg[0] <= 1'b0;
        end
        else begin 
            if (enable) begin
                stage[0] <= window_valid_i;
                tlast_reg[0] <= tlast_i;
                if (window_valid_i) begin 
                    // path 1 products
                    multA00 <= $signed({1'b0, p00}) * wA00;
                    multA01 <= $signed({1'b0, p01}) * wA01;
                    multA02 <= $signed({1'b0, p02}) * wA02;
                    
                    multA10 <= $signed({1'b0, p10}) * wA10;
                    multA11 <= $signed({1'b0, p11}) * wA11;
                    multA12 <= $signed({1'b0, p12}) * wA12;
                    
                    multA20 <= $signed({1'b0, p20}) * wA20;
                    multA21 <= $signed({1'b0, p21}) * wA21;
                    multA22 <= $signed({1'b0, p22}) * wA22;
                    
                    // path 2 products
                    multB00 <= $signed({1'b0, p00}) * wB00;
                    multB01 <= $signed({1'b0, p01}) * wB01;
                    multB02 <= $signed({1'b0, p02}) * wB02;
                    
                    multB10 <= $signed({1'b0, p10}) * wB10;
                    multB11 <= $signed({1'b0, p11}) * wB11;
                    multB12 <= $signed({1'b0, p12}) * wB12;
                    
                    multB20 <= $signed({1'b0, p20}) * wB20;
                    multB21 <= $signed({1'b0, p21}) * wB21;
                    multB22 <= $signed({1'b0, p22}) * wB22;
                end
            end
        end
    end
    
    reg signed [SUM_WIDTH-1:0] rowA0_sum;
    reg signed [SUM_WIDTH-1:0] rowA1_sum;
    reg signed [SUM_WIDTH-1:0] rowA2_sum;
    
    reg signed [SUM_WIDTH-1:0] rowB0_sum;
    reg signed [SUM_WIDTH-1:0] rowB1_sum;
    reg signed [SUM_WIDTH-1:0] rowB2_sum;
    // stage 2
    always@(posedge clk) begin 
        if (!reset_n) begin 
            rowA0_sum <= 0;
            rowA1_sum <= 0;
            rowA2_sum <= 0;
            rowB0_sum <= 0;
            rowB1_sum <= 0;
            rowB2_sum <= 0;
            stage[1] <= 1'b0;
            tlast_reg[1] <= 1'b0;
        end
        else begin 
            if (enable) begin
                stage[1] <= stage[0];
                tlast_reg[1] <= tlast_reg[0];
                if (stage[0]) begin 
                    // path 1 row addiions
                    rowA0_sum <= multA00 + multA01 + multA02;
                    rowA1_sum <= multA10 + multA11 + multA12;
                    rowA2_sum <= multA20 + multA21 + multA22;
                    // path 2 row additons
                    rowB0_sum <= multB00 + multB01 + multB02;
                    rowB1_sum <= multB10 + multB11 + multB12;
                    rowB2_sum <= multB20 + multB21 + multB22;
                end
            end
        end
    end
    
    reg signed [PIXEL_WIDTH-1:0] finalA_sum;
    reg signed [PIXEL_WIDTH-1:0] finalB_sum;
    // stage 3
    always @(posedge clk) begin
        if (!reset_n) begin
            finalA_sum   <= 0;
            finalB_sum   <= 0;
            stage[2]     <= 1'b0;
            tlast_reg[2] <= 1'b0;
        end
        else if (enable) begin
            stage[2]     <= stage[1];
            tlast_reg[2] <= tlast_reg[1];
            if (stage[1]) begin
                finalA_sum <= rowA0_sum + rowA1_sum + rowA2_sum;
                finalB_sum <= rowB0_sum + rowB1_sum + rowB2_sum;
            end
        end
    end
    
    wire signed [PIXEL_WIDTH-1:0] absA_sum, absB_sum;
    wire signed [PIXEL_WIDTH-1:0] sobel_sum;
    reg signed [PIXEL_WIDTH-1:0] norm_sum;

    assign absA_sum = (finalA_sum < 0) ? (0 - finalA_sum) : finalA_sum;
    assign absB_sum = (finalB_sum < 0) ? (0 - finalB_sum) : finalB_sum;
    assign sobel_sum = absA_sum + absB_sum;
    // stage 4
    always@(*) begin 
        case (KERNEL) 
            1: norm_sum = (finalA_sum>>>4);
            2: norm_sum = absA_sum;
            3: norm_sum = sobel_sum;
            5: norm_sum = sobel_sum>>>2;
            default: norm_sum = finalA_sum;
        endcase
    end                     
                          
    always@(posedge clk) begin 
        if (!reset_n) begin 
            pixel_o <= 8'd0;
            conv_valid_o <= 1'b0;
            tlast_o <= 1'b0; 
        end
        else begin 
            if (enable) begin 
                conv_valid_o <= stage[2];
                tlast_o <= tlast_reg[2];
                if (stage[2]) begin 
                    if (norm_sum < 0) begin 
                        pixel_o <= 8'd0;
                    end
                    else if (norm_sum > 8'd255) begin 
                        pixel_o <= 8'd255;
                    end
                    else begin 
                        pixel_o <= norm_sum[7:0];
                    end
                end
            end
        end
    end
    
endmodule

