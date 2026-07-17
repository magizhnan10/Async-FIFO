// =============================================================================
// test_random_stimulus.sv  -  Scenario: constrained-random mixed traffic
//
// What it targets:
//   Everything the six directed scenarios target individually (full/empty
//   boundaries, wraparound, threshold flags, back-to-back timing,
//   concurrent r+w), but under arbitrary randomized interleaving instead
//   of one hand-picked sequence per scenario. The directed tests prove
//   "this specific known-dangerous pattern is handled correctly"; this
//   test's job is to turn up patterns nobody hand-picked.
//
//   Reuses write_agent/read_agent/scoreboard completely unchanged --  only
//   the stimulus source differs (random_fifo_txn instead of directly
//   constructed fifo_transaction). This is the entire point of having
//   pushed all checking logic out of the driver and into the
//   monitor/scoreboard: a new stimulus source needed zero changes anywhere
//   else in the environment.
//
//   NUM_TXNS / WR_WEIGHT / RD_WEIGHT are constructor arguments (not fixed
//   constants), matching the pattern already used by REPEAT/SETTLE_CYCLES
//   in the directed tests -- this lets a future multi-seed regression
//   script dial up intensity or skew the write/read mix per run without
//   editing this file.
//
// What the scoreboard catches:
//   Same generic per-cycle flag/data checks as every other scenario --
//   nothing new is added here.  This test's only job is stimulus
//   generation; correctness judgment stays entirely in the scoreboard,
//   as it does for every other test.
//
// Known limitation (honest, not hidden): the environment is still
// single-clock (Step 3 of the plan -- wclk == rclk == clk). This test
// stresses pointer/flag/data-integrity logic under arbitrary randomized
// interleaving, which is real value now, but it does not yet exercise
// genuine CDC race conditions (independent random clock periods/phase).
// That lands once the async clock split (a later plan step) is done.
// =============================================================================

class test_random_stimulus;

  env  e;
  virtual fifo_if #(.W(8)) vif;
  int  DEPTH;

  int  NUM_TXNS;
  int  WR_WEIGHT;
  int  RD_WEIGHT;

  function new(env e_, virtual fifo_if #(.W(8)) vif_, int depth_,
               int num_txns_  = 200,
               int wr_weight_ = 50,
               int rd_weight_ = 50);
    e         = e_;
    vif       = vif_;
    DEPTH     = depth_;
    NUM_TXNS  = num_txns_;
    WR_WEIGHT = wr_weight_;
    RD_WEIGHT = rd_weight_;
  endfunction

  task run();
    random_fifo_txn t;
    int wr_issued, rd_issued;

    $display("=============================================================");
    $display(" test_random_stimulus: %0d random txns (wr_weight=%0d rd_weight=%0d)",
              NUM_TXNS, WR_WEIGHT, RD_WEIGHT);
    $display("=============================================================");

    wr_issued = 0;
    rd_issued = 0;

    // Generation loop: build one randomized transaction at a time and
    // route it to the correct sequencer based on the randomized op.
    // Pushed as fast as the loop runs, same as the directed tests do --
    // per-transaction pacing (delay_cy) is honored downstream by the
    // driver, not here.
    for (int i = 0; i < NUM_TXNS; i++) begin
      t = new();
      t.wr_weight = WR_WEIGHT;
      t.rd_weight = RD_WEIGHT;

      if (!t.randomize()) begin
        $display("  ERROR: random_fifo_txn::randomize() failed at txn %0d", i);
        continue;
      end

      if (t.op == OP_WRITE) begin
        e.wagent.seqr.put(t);
        wr_issued++;
      end else begin
        e.ragent.seqr.put(t);
        rd_issued++;
      end
    end

    $display("  -- issued: %0d writes, %0d reads --", wr_issued, rd_issued);

    // Drain margin: each side's driver processes its mailbox strictly
    // serially, honoring up to c_delay's max (5 cycles) plus one drive
    // cycle per transaction. Sized against the larger of the two issued
    // counts (weights may be skewed far from 50/50) plus flat margin for
    // synchronizer settle + scoreboard propagation.
    repeat ((((wr_issued > rd_issued) ? wr_issued : rd_issued) * 7) + 20)
      @(posedge vif.clk);

    $display("  random_stimulus scenario done");
  endtask

endclass
