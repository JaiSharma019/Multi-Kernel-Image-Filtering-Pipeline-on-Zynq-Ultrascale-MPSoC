`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/20/2026 03:17:53 PM
// Design Name: 
// Module Name: image_filter_top
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


module image_filter_top #(
    parameter W_IN = 512,
    parameter H_IN = 512,
    parameter KERNEL = 2,
    parameter NO_OF_CHANNELS = 3,
    parameter DATA_WIDTH = (NO_OF_CHANNELS<<3)
)(
    input clk,
    input reset_n,
    
    // AXI4 Stream slave (input from DMA/DDR)
    input [DATA_WIDTH-1:0] s_axis_tdata,
    input                  s_axis_tvalid,
    output                 s_axis_tready,
    input                  s_axis_tlast,
    
    // AXI4 Stream master (output to DMA/DDR)
    output [DATA_WIDTH-1:0] m_axis_tdata,
    output                  m_axis_tvalid,
    input                   m_axis_tready,
    output                  m_axis_tlast
    );
    
    wire [9*DATA_WIDTH-1:0] window_data;
    wire window_valid;
    wire window_tlast;
    wire mac_ready;
        
    // instantiate memory buffer
    window #(
        .W_IN(W_IN),
        .H_IN(H_IN),
        .NO_OF_CHANNELS(NO_OF_CHANNELS)
    ) U_WINDOW (
        .clk(clk),
        .reset_n(reset_n),
        .data_i(s_axis_tdata),
        .valid_i(s_axis_tvalid), // Only accept if pipeline isn't stalled
        .data_o(window_data),
        .ready_o(s_axis_tready),
        .tlast_i(s_axis_tlast),
        .ready_i(mac_ready),
        .tlast_o(window_tlast),
        .valid_o(window_valid)
    );
    
    // generating MAC operation
    generate 
        if (NO_OF_CHANNELS==3) begin: RGB_CONV
            wire [71:0] window_R, window_G, window_B;
            genvar i;
            for (i=0;i<9;i=i+1) begin: SPLIT_RGB
                assign window_R[i*8+:8] = window_data[i*24+16+:8]; // at the top of data
                assign window_G[i*8+:8] = window_data[i*24+8+:8];  // as {R,G,B}
                assign window_B[i*8+:8] = window_data[i*24+:8];
            end
            
            wire [7:0] pixel_R, pixel_G, pixel_B;
            wire valid_R, tlast_R, ready_R; // only for one channel the status signals are enough
            
            convolution #(
                .W_IN(W_IN),
                .H_IN(H_IN),
                .DATA_WIDTH(8),
                .KERNEL(KERNEL)
            ) U_MAC_R (
                .clk(clk),
                .reset_n(reset_n),
                .window_data_i(window_R),
                .window_valid_i(window_valid),
                .tlast_i(window_tlast),
                .conv_valid_o(valid_R),
                .pixel_o(pixel_R),
                .tlast_o(tlast_R),
                .ready_i(m_axis_tready),
                .ready_o(ready_R)
            );
            
            convolution #(
                .W_IN(W_IN),
                .H_IN(H_IN),
                .DATA_WIDTH(8),
                .KERNEL(KERNEL)
            ) U_MAC_G (
                .clk(clk),
                .reset_n(reset_n),
                .window_data_i(window_G),
                .window_valid_i(window_valid),
                .tlast_i(window_tlast),
                .conv_valid_o(),
                .pixel_o(pixel_G),
                .tlast_o(),
                .ready_i(m_axis_tready),
                .ready_o()
            );
            
            convolution #(
                .W_IN(W_IN),
                .H_IN(H_IN),
                .DATA_WIDTH(8),
                .KERNEL(KERNEL)
            ) U_MAC_B (
                .clk(clk),
                .reset_n(reset_n),
                .window_data_i(window_B),
                .window_valid_i(window_valid),
                .tlast_i(window_tlast),
                .conv_valid_o(),
                .pixel_o(pixel_B),
                .tlast_o(),
                .ready_i(m_axis_tready),
                .ready_o()
            );
            
            assign mac_ready = ready_R; 
            assign m_axis_tvalid = valid_R;
            assign m_axis_tlast = tlast_R;
            assign m_axis_tdata = {pixel_R, pixel_G, pixel_B}; 
            
        end
        else begin: GRAY_CONV
            
            // instatiate one time the convolution module
            convolution #(
                .W_IN(W_IN),
                .H_IN(H_IN),
                .DATA_WIDTH(DATA_WIDTH),
                .KERNEL(KERNEL)
            ) U_MAC (
                .clk(clk),
                .reset_n(reset_n),
                .window_data_i(window_data),
                .window_valid_i(window_valid), 
                .conv_valid_o(m_axis_tvalid),
                .pixel_o(m_axis_tdata),
                .tlast_i(window_tlast),
                .tlast_o(m_axis_tlast),
                .ready_i(m_axis_tready),
                .ready_o(mac_ready)
            );
            
        end
    endgenerate
   
endmodule
