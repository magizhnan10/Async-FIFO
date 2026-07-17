`timescale 1ns / 1ps

// =============================================================================
// fifo_mem_sva.sv
//
// Bind-attached assertion module for fifo_mem.v. Second priority per the
// module ranking -- fifo_mem.v has no bug history and simple structure,
// so this is X-propagation insurance rather than a behavioral re-check
// (data ordering/content correctness is already the scoreboard's job via
// its reference queue). Added to the simulation fileset directly.
// =============================================================================

module fifo_mem_sva #(
    parameter W = 8,
    parameter N = 4
) (
    input wire         wclk,
    input wire         wen,
    input wire [N-1:0] waddr,
    input wire [W-1:0] wdata,
    input wire         rclk,
    input wire [N-1:0] raddr
);

  // Write-side input health: address/data must be defined whenever a
  // write is actually qualified. Cheap insurance against an X leaking in
  // from upstream (an integration bug elsewhere), not a memory-content
  // check.
  a_no_x_waddr: assert property (@(posedge wclk) wen |-> !$isunknown(waddr))
    else $error("waddr is X/Z during a qualified write");
  a_no_x_wdata: assert property (@(posedge wclk) wen |-> !$isunknown(wdata))
    else $error("wdata is X/Z during a qualified write");

  // Read-side: only the address is checked here, deliberately. rdata
  // content for an address that has never been written is legitimately
  // X in simulation -- flagging that would be a false positive, not a
  // caught bug, since this module has no notion of "has this address
  // been written yet." Content correctness for addresses that HAVE been
  // written is already covered by the scoreboard's reference queue.
  a_no_x_raddr: assert property (@(posedge rclk) !$isunknown(raddr))
    else $error("raddr is X/Z");

endmodule

bind fifo_mem fifo_mem_sva #(.W(W), .N(N)) u_fifo_mem_sva (.*);
