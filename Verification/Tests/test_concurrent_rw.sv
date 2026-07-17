// =============================================================================
// test_concurrent_rw.sv  -  Scenario 2: Simultaneous read+write, steady state
//
// What it targets:
//   In the sanity test and wraparound test, writes and reads are never
//   issued in the same cycle - fills complete before drains begin. This
//   test fills the FIFO halfway then issues w_en AND r_en simultaneously
//   for SUSTAINED_CYCLES consecutive cycles. Fill level should stay
//   constant (every write is offset by a read). Flags should stay stable
//   (no spurious full/empty). Data order must be preserved.
//
//   This is the first test that exercises the scoreboard's simultaneous-
//   update logic (fill_level++ and fill_level-- from two independent
//   packets arriving in the same timestep). If there's a race in the
//   scoreboard itself, this test will trigger it.
//
// What the scoreboard catches:
//   Data integrity across interleaved writes+reads. Fill-level stability:
//   any spurious wfull/rempty assertion during the sustained concurrent
//   window is a flag mismatch.
// =============================================================================

class test_concurrent_rw;

  env  e;
  virtual fifo_if #(.W(8)) vif;
  int  DEPTH;
  int  SUSTAINED_CYCLES;

  function new(env e_, virtual fifo_if #(.W(8)) vif_, int depth_,
               int sustained_ = 32);
    e               = e_;
    vif             = vif_;
    DEPTH           = depth_;
    SUSTAINED_CYCLES = sustained_;
  endfunction

  task run();
    fifo_transaction wt, rt;
    int half = DEPTH / 2;

    $display("=============================================================");
    $display(" test_concurrent_rw: fill to half (%0d), then %0d concurrent cycles",
             half, SUSTAINED_CYCLES);
    $display("=============================================================");

    // Fill to half depth.
    for (int i = 0; i < half; i++) begin
      wt = new(OP_WRITE, i[7:0], 0);
      e.wagent.seqr.put(wt);
    end
    repeat (half + 2) @(posedge vif.clk);

    // Sustained simultaneous r+w. Push one write and one read transaction
    // per iteration -- both drivers are blocked on get() and will pick up
    // their respective transactions at the same posedge, producing genuine
    // same-cycle w_en && r_en.
    $display("  -- sustained concurrent r+w --");
    for (int i = 0; i < SUSTAINED_CYCLES; i++) begin
      wt = new(OP_WRITE, (8'hA0 + i) % 256, 0);
      rt = new(OP_READ,  0, 0);
      e.wagent.seqr.put(wt);
      e.ragent.seqr.put(rt);
      // Stagger by one cycle so drivers don't build up a large backlog
      // that makes scoreboard fill_level accounting harder to trace.
      @(posedge vif.clk);
    end
    repeat (4) @(posedge vif.clk);

    // Drain the remaining half.
    $display("  -- draining residual half --");
    for (int i = 0; i < half; i++) begin
      rt = new(OP_READ, 0, 0);
      e.ragent.seqr.put(rt);
    end
    repeat (half + 2) @(posedge vif.clk);

    $display("  concurrent_rw scenario done");
  endtask

endclass