// =============================================================================
// fifo_if.sv
//
// Interface wrapping the async_fifo pin-level signals. Driver and monitor
// classes receive a *virtual* handle to this interface, never raw wires --
// that's what lets a class method reach into the testbench from outside the
// module hierarchy.
//
// Stage 3 note: clk is a single shared clock here (wclk == rclk == clk).
// This interface is intentionally written as if it might someday be split
// into separate wclk/rclk and wrst_n/rrst_n (Step 5 of the plan) -- but for
// now everything ties to the same clk/rst_n so the single-clock sanity
// behavior carries over unchanged.
// =============================================================================

interface fifo_if #(
  parameter W = 8
) (
  input logic clk
);

  logic            w_en;
  logic            r_en;
  logic [W-1:0]    wdata;
  logic [W-1:0]    rdata;
  logic            wfull;
  logic            rempty;
  logic            awfull;
  logic            arempty;

  // Defaults so w_en/r_en are never X between reset release and the
  // driver's first actual drive. On real hardware whatever's connected
  // to these pins presents a defined value from power-up (even if just
  // tied to 0 at reset) -- leaving them X here was purely a simulation
  // modeling gap, not something the DUT should be expected to tolerate.
  // (Found via wptr_full_sva.sv's a_no_x_awfull firing well after reset
  // had genuinely released -- wgray_next's ternary on wen, itself X
  // while w_en was undriven, was propagating into awfull's registered
  // comparison every cycle.)
  initial begin
    w_en = 1'b0;
    r_en = 1'b0;
  end

endinterface