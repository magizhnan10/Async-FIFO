// =============================================================================
// test_threshold_flags.sv  -  Scenario 5: awfull/arempty under dynamic stimulus
//
// What it targets:
//   The sanity test only hits awfull/arempty incidentally during a monotonic
//   fill sweep -- it never crosses a threshold boundary in both directions.
//   This test fills to just below the awfull threshold, then alternates:
//   write one (crosses awfull threshold up), read one (crosses back down),
//   write one (crosses up again), etc. Then does the symmetric thing around
//   the arempty threshold.
//
//   An earlier version of this test filled to "A_FULL_TH - 1" before the
//   awfull section, confusing the MARGIN value (e.g. 2) with the actual
//   fill level where awfull changes state (DEPTH - A_FULL_TH, e.g. 14).
//   That put the whole awfull section near-EMPTY instead of near-FULL, so
//   awfull sat at 0 throughout and the section silently tested nothing.
//   Fixed here by filling to (DEPTH - A_FULL_TH - 1).
//
//   It also used a flat 2-cycle margin between every toggle step. That's
//   fine for the "toward the threshold" direction in each section (a
//   same-domain pointer change, no synchronizer involved), but not enough
//   for the "away from the threshold" direction, which depends on the
//   OTHER domain's pointer crossing the 2-flop synchronizer first (~3
//   cycles measured). Fixed here by only widening the margin -- and adding
//   an explicit check -- on the direction that actually needs it.
//
//   This exercises:
//     - awfull asserting (write direction, same-domain, checked quickly)
//       and deasserting (read direction, cross-domain, checked after
//       SETTLE_CYCLES) correctly on the exact boundary cycle
//     - arempty same, with the two directions swapped
//     - No missed transitions in either direction
//
// What the scoreboard catches:
//   The scoreboard's own generic per-cycle flag checker still runs
//   throughout, as always. In addition, this test adds explicit
//   e.sb.check() calls for the exact toggle-boundary cycles, since those
//   fill levels sit inside the scoreboard's own deliberate settle-margin
//   gap for its generic check and wouldn't otherwise be covered.
// =============================================================================

class test_threshold_flags;

  env  e;
  virtual fifo_if #(.W(8)) vif;
  int  DEPTH;
  int  A_FULL_TH;
  int  A_EMPTY_TH;
  int  TOGGLES;        // how many times to cross each threshold
  int  SETTLE_CYCLES;  // cycles to allow a cross-domain pointer change to
                        // settle before checking the "away" direction

  function new(env e_, virtual fifo_if #(.W(8)) vif_, int depth_,
               int a_full_th_, int a_empty_th_, int toggles_ = 8,
               int settle_cycles_ = 4);
    e             = e_;
    vif           = vif_;
    DEPTH         = depth_;
    A_FULL_TH     = a_full_th_;
    A_EMPTY_TH    = a_empty_th_;
    TOGGLES       = toggles_;
    SETTLE_CYCLES = settle_cycles_;
  endfunction

  task run();
    fifo_transaction wt, rt;
    int full_fill_start;

    $display("=============================================================");
    $display(" test_threshold_flags: awfull toggle x%0d, arempty toggle x%0d",
             TOGGLES, TOGGLES);
    $display("=============================================================");

    // ---------------------------------------------------------------
    // awfull threshold exercise:
    //   Fill to (DEPTH - A_FULL_TH - 1) -- just below the awfull
    //   threshold (DEPTH - A_FULL_TH). Then toggle across it TOGGLES
    //   times (write -> above threshold, read -> below threshold).
    // ---------------------------------------------------------------
    full_fill_start = DEPTH - A_FULL_TH - 1;
    $display("  -- filling to DEPTH-A_FULL_TH-1 (%0d writes) --", full_fill_start);
    for (int i = 0; i < full_fill_start; i++) begin
      wt = new(OP_WRITE, i[7:0], 0);
      e.wagent.seqr.put(wt);
    end
    repeat (full_fill_start + 2) @(posedge vif.wclk);

    $display("  -- toggling across awfull threshold --");
    for (int i = 0; i < TOGGLES; i++) begin
      // Write: fill rises to DEPTH-A_FULL_TH -> awfull should assert.
      // Same-domain effect (write pointer, no synchronizer involved) --
      // a short margin is enough.
      wt = new(OP_WRITE, (8'hD0 + i) % 256, 0);
      e.wagent.seqr.put(wt);
      repeat (2) @(posedge vif.wclk);
      e.sb.check((vif.awfull === 1'b1),
        "awfull must assert when fill reaches DEPTH-A_FULL_TH (write direction)");

      // Read: fill drops back to DEPTH-A_FULL_TH-1 -> awfull should
      // deassert. Cross-domain effect (read pointer has to cross the
      // synchronizer into the write domain) -- needs SETTLE_CYCLES
      // counted from the read's own capturing edge, not from put().
      rt = new(OP_READ, 0, 0);
      e.ragent.seqr.put(rt);
      @(posedge vif.wclk);
      // awfull is wclk-native, so counting in wclk cycles is correct;
      // +2 extra covers the read being captured anywhere within one
      // RCLK_PERIOD before it crosses into the wclk domain.
      repeat (SETTLE_CYCLES + 2) @(posedge vif.wclk);
      e.sb.check((vif.awfull === 1'b0),
        "awfull must deassert within SETTLE_CYCLES after fill drops back below DEPTH-A_FULL_TH");
    end

    // Drain completely before the arempty section.
    $display("  -- draining before arempty exercise --");
    // current fill = DEPTH - A_FULL_TH - 1
    for (int i = 0; i < full_fill_start; i++) begin
      rt = new(OP_READ, 0, 0);
      e.ragent.seqr.put(rt);
    end
    // Read-side drain: rclk-paced.
    repeat (full_fill_start + 2) @(posedge vif.rclk);

    // ---------------------------------------------------------------
    // arempty threshold exercise:
    //   Fill to (A_EMPTY_TH + 1) -- just above arempty threshold.
    //   Then toggle across arempty TOGGLES times (read -> below
    //   threshold, write -> above threshold).
    // ---------------------------------------------------------------
    $display("  -- filling to A_EMPTY_TH+1 (%0d writes) --", A_EMPTY_TH + 1);
    for (int i = 0; i < A_EMPTY_TH + 1; i++) begin
      wt = new(OP_WRITE, (8'hE0 + i) % 256, 0);
      e.wagent.seqr.put(wt);
    end
    repeat (A_EMPTY_TH + 4) @(posedge vif.wclk);

    $display("  -- toggling across arempty threshold --");
    for (int i = 0; i < TOGGLES; i++) begin
      // Read: fill drops to A_EMPTY_TH -> arempty should assert.
      // Same-domain effect (read pointer, no synchronizer involved) --
      // a short margin is enough.
      rt = new(OP_READ, 0, 0);
      e.ragent.seqr.put(rt);
      // arempty is rclk-native, and this is the same-domain direction
      // (read pointer only, no synchronizer involved) -- count on rclk.
      repeat (2) @(posedge vif.rclk);
      e.sb.check((vif.arempty === 1'b1),
        "arempty must assert when fill drops to A_EMPTY_TH (read direction)");

      // Write: fill rises to A_EMPTY_TH + 1 -> arempty should deassert.
      // Cross-domain effect (write pointer has to cross the
      // synchronizer into the read domain) -- needs SETTLE_CYCLES
      // counted from the write's own capturing edge, not from put().
      wt = new(OP_WRITE, (8'hE8 + i) % 256, 0);
      e.wagent.seqr.put(wt);
      @(posedge vif.wclk);
      // arempty is rclk-native; +2 extra covers the write being captured
      // anywhere within one WCLK_PERIOD before it crosses into rclk.
      repeat (SETTLE_CYCLES + 2) @(posedge vif.rclk);
      e.sb.check((vif.arempty === 1'b0),
        "arempty must deassert within SETTLE_CYCLES after fill rises back above A_EMPTY_TH");
    end

    // Final drain.
    $display("  -- final drain --");
    for (int i = 0; i < A_EMPTY_TH + 1; i++) begin
      rt = new(OP_READ, 0, 0);
      e.ragent.seqr.put(rt);
    end
    // Read-side drain: rclk-paced.
    repeat (A_EMPTY_TH + 4) @(posedge vif.rclk);

    // Definitive closing check -- nothing should be left behind, in
    // either section.
    e.sb.check((e.sb.fill_level == 0),
      "FIFO must return to fully empty after all threshold toggle cycles");

    $display("  threshold_flags scenario done");
  endtask

endclass