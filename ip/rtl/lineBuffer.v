`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/20/2026 03:20:53 PM
// Design Name: 
// Module Name: lineBuffer
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


module lineBuffer#(
    parameter W_IN = 512,
    parameter NO_OF_CHANNELS = 3,
    parameter DATA_WIDTH = NO_OF_CHANNELS<<3
)(
    input clk,
    input reset_n,
    
    // upstream interface
    input valid_i,
    input [DATA_WIDTH-1:0] data_i,
    output ready_o,
    
    // downstream interface
    output reg valid_o,
    output reg [DATA_WIDTH-1:0] data_o,

    input ready_i
    );
    
    localparam BIT_WIDTH  = $clog2(W_IN);
    
    reg [DATA_WIDTH-1:0] line [W_IN-1:0];
    reg [BIT_WIDTH-1:0]  ptr;
    reg                  filled;
    
    assign ready_o = ready_i || ~valid_o;    

    always@(posedge clk) begin 
        if (!reset_n) begin 
            data_o <= 0;
            ptr <= 0;
            filled <= 0;
            valid_o <= 0;
        end
        else begin 
            if (ready_o) begin // pipeline ready to move
                if (valid_i) begin // if valid pixel available
                    // read and write on same cycle (read first and write)
                    data_o <= line[ptr];
                    line[ptr] <= data_i;
                    
                    valid_o <= filled; // when filled valid is high
                    
                    if (ptr == W_IN - 2) begin // as extra latch on output of memory so 1 subtracted
                        ptr <= 0;
                        filled <= 1'b1;
                    end
                    else begin 
                        ptr <= ptr + 1;
                    end
                end
                else begin 
                    valid_o <= 1'b0;
                end
            end
        end
    end
    

endmodule
