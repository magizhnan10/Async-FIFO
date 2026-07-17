`timescale 1ns / 1ps

module rst_sync (
    input  wire clk,
    input  wire arst_n,
    output wire rst_n
);

    (* ASYNC_REG = "TRUE" *) reg stage1;
    (* ASYNC_REG = "TRUE" *) reg stage2;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            // Assert instantly - no clock needed
            stage1 <= 1'b0;
            stage2 <= 1'b0;
        end else begin
            // Release synchronously - shift a 1 through
            stage1 <= 1'b1;
            stage2 <= stage1;
        end
    end

    // rst_n is the fully-synchronized output
    assign rst_n = stage2;

endmodule