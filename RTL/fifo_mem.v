`timescale 1ns / 1ps

module fifo_mem #(
    parameter W = 8,   // data width
    parameter N = 4    // address width  (depth = 2**N)
) (
    // Write port
    input  wire           wclk,
    input  wire           wen,
    input  wire [N-1:0]   waddr,
    input  wire [W-1:0]   wdata,

    // Read port
    input  wire           rclk,
    input  wire [N-1:0]   raddr,
    output reg  [W-1:0]   rdata
);

    reg [W-1:0] mem [0:(1<<N)-1];

    always @(posedge wclk) begin
        if (wen)
            mem[waddr] <= wdata;
    end
    
    always @(posedge rclk) begin
        rdata <= mem[raddr];
    end

endmodule