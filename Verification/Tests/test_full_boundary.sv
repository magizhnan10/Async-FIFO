 // =============================================================================
// test_full_boundary.sv  -  Scenario 3: Recovery from the full boundary
//
// What it targets:
//   Fill to exactly full. Then issue w_en AND r_en in the same cycle.
//
//   Correct behavior (this is a hard consequence of the CDC design, not a
//   choice): the read succeeds immediately (frees a slot in the read
//   domain). The write is correctly BLOCKED this same cycle -- the write
//   side's wfull is derived from the read pointer as seen through a 2-flop
//   synchronizer, so it cannot know about a same-cycle read no matter how
//   the RTL is built. Expecting same-cycle write acceptance here (as an
//   earlier version of this test did) is asking for something no correctly
//   synchronized async FIFO can do.
//
//   What SHOULD happen, and what this version actually checks:
//     1. The simultaneous read is accepted; the simultaneous write is not.
//     2. Within SETTLE_CYCLES (the measured ~3-cycle synchronizer latency,
//        plus margin), wfull correctly deasserts, reflecting the freed
//        slot. This is checked explicitly, because fill level DEPTH-1
//        sits inside the scoreboard's own deliberate settle-margin gap
//        for its generic per-cycle flag check.
//     3. A freshly-resubmitted write for that freed slot is accepted and
//        actually lands -- proven not by trusting the flag a second time,
//        but by draining everything at the end and letting the
//        scoreboard's ref_queue catch a silently-dropped write as a data
//        mismatch.
//
//   Repeated REPEAT times to stress the recovery path itself, not just its
//   first occurrence.
//
// What the scoreboard catches:
//   - The explicit wfull-deassertion check added in this test (Step 2).
//   - A short ref_queue during the final drain, if a resubmitted write in
//     Step 3 was ever silently dropped.
//   - Any of its own generic per-cycle flag/data checks, as always.
// =============================================================================

class test_full_boundary;

  env  e;
  virtual fifo_if #(.W(8)) vif;
  int  DEPTH;
  int  REPEAT;
  int  SETTLE_CYCLES;   // cycles to allow the freed slot to cross the
                         // synchronizer before expecting wfull to deassert

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
    $display(" test_full_boundary: freeing-read recovery at full, x%0d", REPEAT);
    $display("=============================================================");

    // Fill to full.
    for (int i = 0; i < DEPTH; i++) begin
      wt = new(OP_WRITE, i[7:0], 0);
      e.wagent.seqr.put(wt);
    end
    repeat (DEPTH + 2) @(posedge vif.clk);

    for (int i = 0; i < REPEAT; i++) begin
      $display("  -- full boundary hit %0d --", i + 1);

      // Step 1: simultaneous write attempt + read at the true full
      // boundary. The write here is EXPECTED to be dropped -- that's
      // correct behavior, not a bug, so it is deliberately not checked
      // for acceptance.
      wt = new(OP_WRITE, (8'hB0 + i) % 256, 0);
      rt = new(OP_READ,  0, 0);
      e.wagent.seqr.put(wt);
      e.ragent.seqr.put(rt);
      @(posedge vif.clk);

      // Step 2: wait for the freed slot to propagate through the
      // synchronizer, then explicitly confirm wfull has deasserted.
      repeat (SETTLE_CYCLES) @(posedge vif.clk);
      e.sb.check((vif.wfull === 1'b0),
        "wfull must deassert within SETTLE_CYCLES of a freeing read at the full boundary");

      // Step 3: resubmit a write for the freed slot, now that wfull is
      // genuinely low. This is the actual proof that the freed slot is
      // usable again -- if this write is silently dropped, the final
      // drain below will come up one short and the scoreboard's
      // ref_queue check will catch it as a data mismatch.
      wt = new(OP_WRITE, (8'hB8 + i) % 256, 0);
      e.wagent.seqr.put(wt);
      repeat (2) @(posedge vif.clk);
    end

    repeat (4) @(posedge vif.clk);

    // Drain everything remaining.
    $display("  -- draining --");
    for (int i = 0; i < DEPTH; i++) begin
      rt = new(OP_READ, 0, 0);
      e.ragent.seqr.put(rt);
    end
    repeat (DEPTH + 2) @(posedge vif.clk);

    $display("  full_boundary scenario done");
  endtask

endclass