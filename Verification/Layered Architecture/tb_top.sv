// =============================================================================
// tb_top.sv
//
// Top-level module. Responsibilities deliberately kept minimal:
//   - generate clk/rst_n (still single-clock per Step 3 of the plan --
//     wclk and rclk both tie to the same `clk` net, wrst_n/rrst_n both tie
//     to the same `rst_n` net, exactly as in the original directed TB)
//   - instantiate the interface and the DUT
//   - construct env + test, kick off run()
//
// No checking, no stimulus generation lives here -- that discipline is the
// entire point of this conversion.
// =============================================================================

`timescale 1ns / 1ps

`include "fifo_tb_pkg.sv"
import fifo_tb_pkg::*;

module tb_top;

  localparam W          = 8;
  localparam N           = 4;
  localparam DEPTH       = (1 << N);
  localparam A_FULL_TH   = 2;
  localparam A_EMPTY_TH  = 2;
  localparam CLK_PERIOD  = 10;

  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  initial begin
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
  end

  fifo_if #(.W(W)) vif (.clk(clk));

  // -----------------------------------------------------------------
  // DUT instantiation -- against the documented async_fifo interface.
  // wclk/rclk and wrst_n/rrst_n both tied to the single clk/rst_n nets,
  // matching the directed TB's single-clock sanity configuration.
  // -----------------------------------------------------------------
  async_fifo #(
    .W         (W),
    .N         (N),
    .A_FULL_TH (A_FULL_TH),
    .A_EMPTY_TH(A_EMPTY_TH)
  ) dut (
    .wclk    (clk),
    .rclk    (clk),
    .arst_n  (rst_n),
    .w_en    (vif.w_en),
    .r_en    (vif.r_en),
    .wdata   (vif.wdata),
    .rdata   (vif.rdata),
    .wfull   (vif.wfull),
    .rempty  (vif.rempty),
    .awfull  (vif.awfull),
    .arempty (vif.arempty)
  );

  env                       e;
  fifo_sanity_test          t0;
  test_boundary_backtoback  tbb;
  test_wraparound      t1;
  test_concurrent_rw   t2;
  test_full_boundary   t3;
  test_empty_boundary  t4;
  test_threshold_flags t5;

  // Waveform-visible mirror of the scoreboard's fill_level. fill_level
  // itself lives inside a dynamically-allocated class object (e.sb), so
  // it isn't reliably addable to a waveform directly -- this plain
  // module-scope variable is, since it's part of the static hierarchy.
  // Sampled a few time units after the scoreboard's own #2 post-edge
  // update (see scoreboard.sv run()), so it reflects the just-updated
  // value within the same cycle rather than lagging by one.
  int dbg_fill_level;
  always @(posedge clk) begin
    #3;
    if (e != null) dbg_fill_level = e.sb.fill_level;
  end

  int total_errors;

  initial begin
    total_errors = 0;

    // Wait for reset to be released and align to a clean posedge before
    // starting agents -- avoids delta-cycle ambiguity at driver/monitor startup.
    wait (rst_n === 1'b1);
    repeat (12)@(posedge clk);

    e = new(vif, DEPTH, A_FULL_TH, A_EMPTY_TH);
    e.run();
    @(posedge clk); // let agents' forever loops reach their first wait point

    // ------------------------------------------------------------------
    // Test 0: basic sanity (reset -> fill -> drain)
    // ------------------------------------------------------------------
    t0 = new(e, vif, DEPTH);
    t0.run();
    total_errors += e.sb.error_count;
    e.reset(rst_n);

    // ------------------------------------------------------------------
    // Test 0.5: zero-gap back-to-back overflow/underflow boundary probe
    // ------------------------------------------------------------------
    tbb = new(e, vif, DEPTH);
    tbb.run();
    total_errors += e.sb.error_count;
    e.reset(rst_n);

    // ------------------------------------------------------------------
    // Test 1: pointer wraparound across multiple laps
    // ------------------------------------------------------------------
    t1 = new(e, vif, DEPTH);
    t1.run();
    total_errors += e.sb.error_count;
    e.reset(rst_n);

    // ------------------------------------------------------------------
    // Test 2: sustained concurrent r+w at steady state
    // ------------------------------------------------------------------
    t2 = new(e, vif, DEPTH);
    t2.run();
    total_errors += e.sb.error_count;
    e.reset(rst_n);

    // ------------------------------------------------------------------
    // Test 3: recovery from the full boundary (read frees a slot, write
    // resubmitted after the synchronizer settles)
    // ------------------------------------------------------------------
    t3 = new(e, vif, DEPTH);
    t3.run();
    total_errors += e.sb.error_count;
    e.reset(rst_n);

    // ------------------------------------------------------------------
    // Test 4: recovery from the empty boundary (write fills a slot, read
    // resubmitted after the synchronizer settles)
    // ------------------------------------------------------------------
    t4 = new(e, vif, DEPTH);
    t4.run();
    total_errors += e.sb.error_count;
    e.reset(rst_n);

//    // ------------------------------------------------------------------
//    // Test 5: awfull/arempty threshold toggle under dynamic stimulus
//    // ------------------------------------------------------------------
    t5 = new(e, vif, DEPTH, A_FULL_TH, A_EMPTY_TH);
    t5.run();
    total_errors += e.sb.error_count;

    // ------------------------------------------------------------------
    // Final combined report -- only $finish lives here, not in any test
    // ------------------------------------------------------------------
    $display("=============================================================");
    if (total_errors == 0)
      $display(" ALL SCENARIOS PASSED");
    else
      $display(" %0d TOTAL ERRORS ACROSS ALL SCENARIOS", total_errors);
    $display("=============================================================");

    if (total_errors != 0) $finish(1);
    else                   $finish(0);
  end

  // Safety timeout -- sized for all 6 scenarios combined.
  initial begin
    #2000000;
    $display("FAIL: testbench timed out -- a test likely hung waiting on a flag");
    $finish(1);
  end

endmodule