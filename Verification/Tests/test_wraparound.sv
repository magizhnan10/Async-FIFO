// =============================================================================
// test_wraparound.sv  -  Scenario 1: Pointer wraparound continuity
//
// What it targets:
//   The sanity test does exactly one fill→drain cycle, so wptr/rptr each
//   increment from 0 to DEPTH and stop. The wrap bit (MSB of the (N+1)-bit
//   pointer, §3.2.3) never toggles a second time. This test runs LAPS
//   complete fill→drain cycles back to back so the pointers lap the counter
//   multiple times. Any bug in the wrap-bit full/empty discrimination
//   (the condition wptr == rptr means empty, wptr[N]!=rptr[N] && lower bits
//   equal means full) shows up after the first lap, not the zeroth.
//
// What the scoreboard catches:
//   Data integrity: every write's data matches the corresponding read, even
//   across wrap boundaries. Flag correctness: wfull/rempty never assert at
//   the wrong fill level across laps.
// =============================================================================

class test_wraparound;

  env  e;
  virtual fifo_if #(.W(8)) vif;
  int  DEPTH;
  int  LAPS;

  function new(env e_, virtual fifo_if #(.W(8)) vif_, int depth_, int laps_ = 4);
    e     = e_;
    vif   = vif_;
    DEPTH = depth_;
    LAPS  = laps_;
  endfunction

  task run();
    fifo_transaction t;
    int base_data;

    $display("=============================================================");
    $display(" test_wraparound: %0d fill/drain laps (DEPTH=%0d)", LAPS, DEPTH);
    $display("=============================================================");

    for (int lap = 0; lap < LAPS; lap++) begin
      $display("  -- lap %0d/%0d --", lap+1, LAPS);
      base_data = lap * DEPTH;

      // Fill to full. Use lap-offset data so the scoreboard sees unique
      // values across laps (easier to debug mismatches in waveforms).
      for (int i = 0; i < DEPTH; i++) begin
        t = new(OP_WRITE, (base_data + i) % 256, 0);
        e.wagent.seqr.put(t);
      end
      repeat (DEPTH + 2) @(posedge vif.wclk);

      // Drain to empty. Read-side: rclk-paced, since read_driver processes
      // reads at rclk cadence, not wclk.
      for (int i = 0; i < DEPTH; i++) begin
        t = new(OP_READ, 0, 0);
        e.ragent.seqr.put(t);
      end
      repeat (DEPTH + 2) @(posedge vif.rclk);
    end

    $display("  wraparound scenario done");
  endtask

endclass