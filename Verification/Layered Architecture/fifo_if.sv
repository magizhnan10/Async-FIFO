// =============================================================================
// fifo_if.sv
//
// Interface wrapping the async_fifo pin-level signals. Driver and monitor
// classes receive a *virtual* handle to this interface, never raw wires --
// that's what lets a class method reach into the testbench from outside the
// module hierarchy.
//
// PHASE 3: wclk/rclk are now independent ports, replacing the single shared
// clk used through Stage 3. Every other signal is unchanged -- only the
// clocking split. write_driver.sv/write_monitor.sv now clock off wclk,
// read_driver.sv/read_monitor.sv off rclk, matching the DUT's own domain
// boundaries for the first time in the testbench (the RTL itself always
// had wclk/rclk as genuinely separate ports; only the testbench tied them
// together, as an intentional Stage 3 simplification).
// =============================================================================

interface fifo_if #(
  parameter W = 8
) (
  input logic wclk,
  input logic rclk
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
  initial begin
    w_en = 1'b0;
    r_en = 1'b0;
  end

endinterface