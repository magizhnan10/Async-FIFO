// =============================================================================
// test_boundary_backtoback.sv
//
// Regression test for the wfull/rempty one-cycle-late bug class fixed in
// wprt_full.v / rptr_empty.v. Unlike fifo_sanity_test.sv, this test leaves
// NO idle gap between the write/read that completes the fill/drain and the
// next attempted write/read -- the queued transactions are pushed in one
// batch, so write_driver/read_driver hold w_en/r_en continuously across the
// boundary with zero cycles of slack. That's the exact window the original
// bug lived in: fifo_sanity_test.sv's driver naturally deasserts w_en/r_en
// the instant its queue empties (right at the boundary), which meant it
// could only ever expose the bug as a flag-timing mismatch, never as actual
// data corruption. This test is built to expose the corruption directly.
//
// What this test checks, and how:
//   - Overflow probe: fill to DEPTH, then keep pushing OVERSHOOT more
//     writes with zero gap. If wfull is even one cycle late, one of these
//     lands, overwrites an unread entry, and the ref_queue/DUT data will
//     disagree on a later read -- caught by the scoreboard's existing
//     "rdata mismatch" check, no new scoreboard logic required.
//   - Underflow probe: mirror on the read side. An extra accepted read
//     past empty will either under-run the ref_queue (caught by "read
//     observed as accepted but reference queue is empty") or return stale
//     data (caught by "rdata mismatch").
//
// This test deliberately does NOT add new checks to the scoreboard -- the
// existing checks are sufficient once the stimulus actually reaches the
// boundary with no gap. That also means this test is meaningful against
// any scoreboard, not just one patched for this specific bug.
// =============================================================================

class test_boundary_backtoback;

  env e;
  virtual fifo_if #(.W(8)) vif;

  int DEPTH;
  int OVERSHOOT;

  function new(env e_, virtual fifo_if #(.W(8)) vif_, int depth_, int overshoot_ = 3);
    e         = e_;
    vif       = vif_;
    DEPTH     = depth_;
    OVERSHOOT = overshoot_;
  endfunction

  task run();
    fifo_transaction t;

    $display("=============================================================");
    $display(" test_boundary_backtoback starting (DEPTH=%0d, OVERSHOOT=%0d)", DEPTH, OVERSHOOT);
    $display("=============================================================");

    // -----------------------------------------------------------------
    // Overflow probe: DEPTH + OVERSHOOT writes queued in one batch, all
    // delay_cy=0. The driver drains this queue one write per cycle with
    // NO gap anywhere in the burst -- including right at the boundary,
    // unlike fifo_sanity_test.sv, which queues exactly DEPTH writes and
    // only adds one more after a multi-cycle wait.
    // -----------------------------------------------------------------
    $display("--- Overflow probe: %0d back-to-back writes, zero gap at boundary ---",
              DEPTH + OVERSHOOT);
    for (int i = 0; i < DEPTH + OVERSHOOT; i++) begin
      t = new(OP_WRITE, i[7:0], 0);
      e.wagent.seqr.put(t);
    end
    // Margin here is fine -- it's after the burst, not at the boundary.
    repeat (DEPTH + OVERSHOOT + 6) @(posedge vif.clk);

    // -----------------------------------------------------------------
    // Drain everything the scoreboard's reference model thinks is
    // present, so the underflow probe starts from a known-empty queue.
    // If the overflow probe corrupted anything, this drain is exactly
    // where the resulting rdata mismatch will surface.
    // -----------------------------------------------------------------
    $display("--- Draining to empty (exposes any overflow corruption from above) ---");
    for (int i = 0; i < DEPTH; i++) begin
      t = new(OP_READ, 0, 0);
      e.ragent.seqr.put(t);
    end
    repeat (DEPTH + 6) @(posedge vif.clk);

    // -----------------------------------------------------------------
    // Refill so there's something to underflow past.
    // -----------------------------------------------------------------
    $display("--- Refilling before underflow probe ---");
    for (int i = 0; i < DEPTH; i++) begin
      t = new(OP_WRITE, (8'hA0 + i[7:0]), 0);
      e.wagent.seqr.put(t);
    end
    repeat (DEPTH + 6) @(posedge vif.clk);

    // -----------------------------------------------------------------
    // Underflow probe: mirror of the overflow probe on the read side --
    // DEPTH + OVERSHOOT reads queued in one batch, zero gap at the
    // empty boundary.
    // -----------------------------------------------------------------
    $display("--- Underflow probe: %0d back-to-back reads, zero gap at boundary ---",
              DEPTH + OVERSHOOT);
    for (int i = 0; i < DEPTH + OVERSHOOT; i++) begin
      t = new(OP_READ, 0, 0);
      e.ragent.seqr.put(t);
    end
    repeat (DEPTH + OVERSHOOT + 6) @(posedge vif.clk);

    e.sb.report();
  endtask

endclass