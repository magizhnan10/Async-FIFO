`timescale 1ns / 1ps

module sync_2ff #(
        parameter W = 5
)(
   input wire [W-1:0] d,
   input wire clk,
   input wire rst_n,
   output wire [W-1:0] q
    );
    
    (* ASYNC_REG = "TRUE" *) reg [W-1:0] ff1;
    (* ASYNC_REG = "TRUE" *) reg [W-1:0] ff2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ff1 <= {W{1'b0}};
            ff2 <= {W{1'b0}};
        end else begin
            ff1 <= d;
            ff2 <= ff1;
        end
    end
    
    assign q = ff2;
endmodule
