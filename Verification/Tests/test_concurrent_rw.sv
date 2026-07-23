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
    repeat (half + 2) @(posedge vif.wclk);

    // Sustained simultaneous r+w. Previously this pushed one write AND one
    // read per wclk edge, assuming both drivers would pick them up on
    // "the same cycle." That assumption doesn't hold with independent
    // clocks: write_driver consumes at wclk pace (fast), but read_driver
    // only consumes at rclk pace (slower here), so writes were racing
    // ahead of reads over the course of the loop -- the FIFO was actually
    // drifting toward full rather than staying at half, silently dropping
    // writes once it hit the boundary, which none of this test's checks
    // were designed to expect. Instead, each side now paces its own push
    // loop on its own clock, so both sides issue exactly SUSTAINED_CYCLES
    // transactions over the same real-time window -- preserving the
    // intended near-constant fill level without requiring same-edge
    // synchronization that two independent clocks can't provide.
    $display("  -- sustained concurrent r+w --");
    fork
      begin : write_stream
        for (int i = 0; i < SUSTAINED_CYCLES; i++) begin
          wt = new(OP_WRITE, (8'hA0 + i) % 256, 0);
          e.wagent.seqr.put(wt);
          @(posedge vif.wclk);
        end
      end
      begin : read_stream
        for (int i = 0; i < SUSTAINED_CYCLES; i++) begin
          rt = new(OP_READ, 0, 0);
          e.ragent.seqr.put(rt);
          @(posedge vif.rclk);
        end
      end
    join
    // Small settle margin on both clocks: each side's push loop now paces
    // itself at that side's own consumption rate, so there's no backlog
    // buildup to drain here the way there was before -- just the usual
    // couple of cycles for the last transaction's effects to land.
    fork
      repeat (4) @(posedge vif.wclk);
      repeat (4) @(posedge vif.rclk);
    join

    // Drain the remaining half.
    $display("  -- draining residual half --");
    for (int i = 0; i < half; i++) begin
      rt = new(OP_READ, 0, 0);
      e.ragent.seqr.put(rt);
    end
    // Read-side drain: rclk-paced.
    repeat (half + 2) @(posedge vif.rclk);

    $display("  concurrent_rw scenario done");
  endtask

endclass