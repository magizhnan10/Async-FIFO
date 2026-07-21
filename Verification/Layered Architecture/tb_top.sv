// =============================================================================
// tb_top.sv
//
// Top-level module. Responsibilities deliberately kept minimal:
//   - generate wclk/rclk as two INDEPENDENT clock generators (Phase 3),
//     with independently configurable periods -- placeholder values below
//     are matched (10ns/10ns) as a checkpoint that the plumbing change
//     itself didn't break anything, independent of any ratio-skew
//     behavior. Change WCLK_PERIOD/RCLK_PERIOD to any values to exercise
//     a real skew; nothing else in this file, or in env.sv's reset task,
//     assumes a particular ratio or which domain is faster.
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

  // PHASE 3: independent periods, deliberately not required to be equal
  // or to be integer multiples of one another. Placeholder checkpoint
  // values below are matched (10/10); change independently to exercise
  // real ratio skew once the matched-period regression is confirmed clean.
  // PHASE 3 STEP 6: real skew, deliberately coprime (10/17, not a clean
  // 2:1 or other integer-multiple ratio) -- an integer-multiple ratio can
  // accidentally hide phase-alignment bugs that a coprime ratio won't,
  // since the two clocks' edges would otherwise re-align on a short,
  // predictable cadence.
  localparam WCLK_PERIOD = 10;
  localparam RCLK_PERIOD = 17;

  logic wclk;
  logic rclk;
  logic rst_n;

  initial wclk = 1'b0;
  always #(WCLK_PERIOD/2.0) wclk = ~wclk;

  initial rclk = 1'b0;
  always #(RCLK_PERIOD/2.0) rclk = ~rclk;

  // Reset assertion window sized to guarantee at least 4 edges on BOTH
  // domains regardless of which period is larger -- fork...join (not
  // join_none) blocks until both branches complete, so the effective
  // hold time is max(4*WCLK_PERIOD, 4*RCLK_PERIOD) automatically, with
  // no hardcoded assumption about which clock is faster.
  initial begin
    rst_n = 1'b0;
    fork
      repeat (4) @(posedge wclk);
      repeat (4) @(posedge rclk);
    join
    rst_n = 1'b1;
  end

  fifo_if #(.W(W)) vif (.wclk(wclk), .rclk(rclk));

  // -----------------------------------------------------------------
  // DUT instantiation -- against the documented async_fifo interface.
  // wclk/rclk now genuinely independent (Phase 3); wrst_n/rrst_n both
  // still tied to the single async rst_n net, since reset synchronization
  // itself is unaffected by this phase -- rst_sync.v already handles each
  // domain's own synchronization independently downstream of arst_n.
  // -----------------------------------------------------------------
  async_fifo #(
    .W         (W),
    .N         (N),
    .A_FULL_TH (A_FULL_TH),
    .A_EMPTY_TH(A_EMPTY_TH)
  ) dut (
    .wclk    (wclk),
    .rclk    (rclk),
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
  // Sampled off wclk purely as a debug-viewing convenience (fill_level
  // itself is updated by both domains independently via the scoreboard's
  // two loops -- this mirror doesn't need to be cycle-exact on both,
  // only close enough to be readable on a waveform).
  int dbg_fill_level;
  always @(posedge wclk) begin
    #3;
    if (e != null) dbg_fill_level = e.sb.fill_level;
  end

  int total_errors;

  initial begin
    total_errors = 0;

    // Wait for reset to be released, then settle on BOTH domains before
    // starting agents -- avoids delta-cycle ambiguity at driver/monitor
    // startup regardless of which clock is faster. fork...join blocks
    // until both branches complete, so this is max(12*WCLK_PERIOD,
    // 12*RCLK_PERIOD) automatically, with no assumption about ratio.
    wait (rst_n === 1'b1);
    fork
      repeat (12) @(posedge wclk);
      repeat (12) @(posedge rclk);
    join

    e = new(vif, DEPTH, A_FULL_TH, A_EMPTY_TH);
    e.run();

    // Let both agents' forever loops reach their first wait point,
    // regardless of which domain is faster.
    fork
      @(posedge wclk);
      @(posedge rclk);
    join

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