// =============================================================================
// test_empty_boundary.sv  -  Scenario 4: Recovery from the empty boundary
//
// What it targets:
//   Mirror of test_full_boundary.sv, at the other extreme. Start empty.
//   Issue w_en AND r_en simultaneously.
//
//   Correct behavior: the write succeeds immediately (fill 0->1) -- wfull
//   doesn't need any information from the read domain to know it isn't
//   full, so there's no synchronizer delay involved in the write's own
//   acceptance decision. The read is correctly BLOCKED this same cycle:
//   rempty is derived from the write pointer as seen through a 2-flop
//   synchronizer, so it cannot know about a same-cycle write no matter how
//   the RTL is built -- exactly the mirror-image constraint that made the
//   original test_full_boundary.sv's premise physically impossible.
//
//   An earlier version of this test issued its "drain the entry" read only
//   2 cycles later, which isn't enough time for rempty to have caught up
//   (measured settle time is ~3 cycles) -- so that read was silently
//   blocked every time, and the FIFO quietly accumulated entries instead
//   of returning to empty each iteration, without ever tripping a FAIL,
//   because nothing was checking for it.
//
//   What this version actually checks:
//     1. The simultaneous write is accepted; the simultaneous read is not
//        (implicitly, by construction -- not separately asserted).
//     2. Within SETTLE_CYCLES, rempty correctly deasserts, reflecting the
//        new entry. Checked explicitly, because fill level 1 sits inside
//        the scoreboard's own deliberate settle-margin gap for its
//        generic per-cycle check.
//     3. The entry is then actually drained (only after rempty is
//        confirmed low), and its data flows through the scoreboard's
//        normal ref_queue check like any other read.
//     4. After all REPEAT iterations, fill_level must be back to exactly
//        0 -- the definitive closing check that nothing was ever left
//        stuck behind, which is exactly the failure mode the original
//        timing bug caused.
//
// What the scoreboard catches:
//   - The explicit rempty-deassertion check added in this test (Step 2).
//   - Any rdata mismatch on the drain reads, as always.
//   - The explicit fill_level == 0 closing check (Step 4).
// =============================================================================

class test_empty_boundary;

  env  e;
  virtual fifo_if #(.W(8)) vif;
  int  DEPTH;
  int  REPEAT;
  int  SETTLE_CYCLES;   // cycles to allow a new entry to cross the
                         // synchronizer before expecting rempty to deassert

  function new(env e_, virtual fifo_if #(.W(8)) vif_, int depth_,
               int repeat_ = 8, int settle_cycles_ = 4);
    e             = e_;
    vif           = vif_;
    DEPTH         = depth_;
    REPEAT        = repeat_;
    SETTLE_CYCLES = settle_cycles_;
  endfunction

  task run();
    fifo_transaction wt, rt;

    $display("=============================================================");
    $display(" test_empty_boundary: filling-write recovery at empty, x%0d", REPEAT);
    $display("=============================================================");

    // Start empty (DUT already reset before this test by the test runner).

    for (int i = 0; i < REPEAT; i++) begin
      $display("  -- empty boundary hit %0d --", i + 1);

      // Step 1: simultaneous write + read at true empty. The read here
      // is EXPECTED to be dropped -- that's correct behavior, not a
      // bug, so it is deliberately not checked for acceptance.
      wt = new(OP_WRITE, (8'hC0 + i) % 256, 0);
      rt = new(OP_READ,  0, 0);
      e.wagent.seqr.put(wt);
      e.ragent.seqr.put(rt);
      @(posedge vif.clk);

      // Step 2: wait for the new entry to propagate through the
      // synchronizer, then explicitly confirm rempty has deasserted.
      repeat (SETTLE_CYCLES) @(posedge vif.clk);
      e.sb.check((vif.rempty === 1'b0),
        "rempty must deassert within SETTLE_CYCLES of a filling write at the empty boundary");

      // Step 3: drain the one entry now that rempty is genuinely low.
      rt = new(OP_READ, 0, 0);
      e.ragent.seqr.put(rt);
      repeat (2) @(posedge vif.clk);
    end

    repeat (4) @(posedge vif.clk);

    // Step 4: definitive closing check -- nothing should be left behind.
    // This is exactly the check that would have caught the original
    // timing bug: with the old 2-cycle margin, this would have read
    // REPEAT (8), not 0.
    e.sb.check((e.sb.fill_level == 0),
      "FIFO must return to fully empty after all empty-boundary recovery cycles");

    $display("  empty_boundary scenario done");
  endtask

endclass