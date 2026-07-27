`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/20/2026 03:19:24 PM
// Design Name: 
// Module Name: window
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


module window#(
    parameter W_IN = 512,
    parameter H_IN = 512,
    parameter NO_OF_CHANNELS = 3
)(
    input clk,
    input reset_n,
    
    // upstream interface
    input valid_i,
    input [(NO_OF_CHANNELS<<3)-1:0] data_i,
    output ready_o,
    input tlast_i,
    
    // downstream interface
    output reg valid_o,
    output [9*(NO_OF_CHANNELS<<3)-1:0] data_o,
    input ready_i,
    output tlast_o
    );
    
    localparam DATA_WIDTH = (NO_OF_CHANNELS<<3);
    localparam BIT_WIDTH  = $clog2(W_IN);
    localparam H_BIT_WIDTH = $clog2(H_IN);
    
    wire [DATA_WIDTH:0]   lb1_data;
    wire                  lb1_valid;
    wire [DATA_WIDTH-1:0] lb2_data;
    wire                  lb2_valid;
    wire                  ready1;
    
    wire enable;
    assign enable = ready_i || ~valid_o;
    
    // Line Buffer 1: Delays 1 Row
    lineBuffer #(
        .W_IN(W_IN),
        .NO_OF_CHANNELS(NO_OF_CHANNELS),
        .DATA_WIDTH(DATA_WIDTH + 1) // extra bit for tlast
    ) LB1 (
        .clk(clk),
        .reset_n(reset_n),
        .valid_i(valid_i),         // input in live stream is valid
        .data_i({tlast_i,data_i}), // input is live stream
        .ready_o(ready_o),         // LB1 dictates if the whole IP is ready for upstream data
        .valid_o(lb1_valid),
        .data_o(lb1_data),
        .ready_i(enable)           // this moves along with the pipeline
    );
    
    // Line Buffer 2: Delays LB1's output by 1 Row (Total 2 Rows delay)
    lineBuffer #(
        .W_IN(W_IN),
        .NO_OF_CHANNELS(NO_OF_CHANNELS)
    ) LB2 (
        .clk(clk),
        .reset_n(reset_n),
        .valid_i(lb1_valid),               // Input is LB1 output
        .data_i(lb1_data[DATA_WIDTH-1:0]), // explicit width slice and Input is LB1 output
        .ready_o(ready1),                  // LB1 talks to upstream (DMA) as that is the front gate door
        .valid_o(lb2_valid),
        .data_o(lb2_data),
        .ready_i(enable)                   // this also moves in with the pipeline
    );
    
    // shift registers
    reg [DATA_WIDTH-1:0] pixel00, pixel01, pixel02;
    reg [DATA_WIDTH-1:0] pixel10, pixel11, pixel12;
    reg [DATA_WIDTH-1:0] pixel20, pixel21, pixel22;
    
    reg [1:0] valid;
    reg center_valid;
    reg [BIT_WIDTH-1:0] col_cnt;
    reg [H_BIT_WIDTH-1:0] row_cnt;
    
    always@(posedge clk) begin 
        if (!reset_n) begin 
            pixel00 <= 0; pixel01 <= 0; pixel02 <= 0;
            pixel10 <= 0; pixel11 <= 0; pixel12 <= 0;
            pixel20 <= 0; pixel21 <= 0; pixel22 <= 0;
            valid   <= 2'b0;
            valid_o <= 1'b0;
        end
        else begin 
            if (enable) begin 
                if (valid_i) begin 
                    // shift top row (LB2)
                    pixel02 <= lb2_data;
                    pixel01 <= pixel02;
                    pixel00 <= pixel01;
                    // shift middle row (LB1)
                    pixel12 <= lb1_data[DATA_WIDTH-1:0];
                    pixel11 <= pixel12;
                    pixel10 <= pixel11;
                    // shift bottom row (live)
                    pixel22 <= data_i;
                    pixel21 <= pixel22;
                    pixel20 <= pixel21;
                    // shifting valid
                    center_valid <= lb1_valid; 
                    valid_o <= center_valid;
                end
                else begin 
                    valid_o <= 1'b0;
                    center_valid <= 1'b0;
                end
            end
        end
    end
    
    always@(posedge clk) begin 
        if (!reset_n) begin 
            col_cnt <= 0;
            row_cnt <= 0;
        end
        else begin 
            if (ready_i && valid_o) begin 
                if (col_cnt == W_IN - 1) begin
                    col_cnt <= 0;
                    if (row_cnt == H_IN - 1)
                        row_cnt <= 0;
                    else
                        row_cnt <= row_cnt + 1;
                end
                else begin
                    col_cnt <= col_cnt + 1;
                end
            end
        end
    end
    
    reg tlast_1;
    reg tlast_2; 
    
    always@(posedge clk) begin 
        if (!reset_n) begin 
            tlast_1 <= 1'b0;
            tlast_2 <= 1'b0;
        end
        else begin 
            if (enable) begin
                if (valid_i) begin 
                    // so that tlast reaches center pixel
                    tlast_1 <= lb1_data[DATA_WIDTH];
                    tlast_2 <= tlast_1;
                end else begin
                    // to clear if pipeline paused
                    tlast_1 <= 1'b0;
                    tlast_2 <= 1'b0;
                end
            end
        end
    end
    
    assign tlast_o = valid_o && tlast_2;
    
    // Horizontal Edge replication
    // replacing left column with center column on left edge
    wire [DATA_WIDTH-1:0] p00 = (col_cnt == 0) ? pixel01 : pixel00;
    wire [DATA_WIDTH-1:0] p10 = (col_cnt == 0) ? pixel11 : pixel10;
    wire [DATA_WIDTH-1:0] p20 = (col_cnt == 0) ? pixel21 : pixel20;

    // replacing right column with center column on right edge
    wire [DATA_WIDTH-1:0] p02 = (col_cnt == W_IN-1) ? pixel01 : pixel02;
    wire [DATA_WIDTH-1:0] p12 = (col_cnt == W_IN-1) ? pixel11 : pixel12;
    wire [DATA_WIDTH-1:0] p22 = (col_cnt == W_IN-1) ? pixel21 : pixel22;

    // Vertical Edge replication 
    // replacing the top row with middle row on top edge
    wire [DATA_WIDTH-1:0] final_p00 = (row_cnt == 0) ? p10   : p00;
    wire [DATA_WIDTH-1:0] final_p01 = (row_cnt == 0) ? pixel11 : pixel01;
    wire [DATA_WIDTH-1:0] final_p02 = (row_cnt == 0) ? p12   : p02;

    // replacing the bottom row with the middle row on bottom edge
    wire [DATA_WIDTH-1:0] final_p20 = (row_cnt == H_IN-1) ? p10   : p20;
    wire [DATA_WIDTH-1:0] final_p21 = (row_cnt == H_IN-1) ? pixel11 : pixel21;
    wire [DATA_WIDTH-1:0] final_p22 = (row_cnt == H_IN-1) ? p12   : p22;

    assign data_o = {final_p22, final_p21, final_p20, 
                     p12,     pixel11,   p10, 
                     final_p02, final_p01, final_p00};
    
endmodule
