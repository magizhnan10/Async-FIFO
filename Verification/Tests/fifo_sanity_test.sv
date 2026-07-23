// =============================================================================
// fifo_sanity_test.sv
//
// Same scenario as the original directed (non-class) testbench:
//   1. Reset check
//   2. Fill to full (DEPTH writes), checking wfull/awfull don't fire early
//   3. Write-while-full (ignored)
//   4. Drain to empty (DEPTH reads), checking rempty/arempty don't fire early
//   5. Read-while-empty (ignored)
//
// The difference is entirely architectural: this class only PUSHES
// transactions into env.wagent.seqr / env.ragent.seqr. It never touches a
// DUT pin directly, and it never checks a DUT output directly -- all
// checking happens in the scoreboard, driven by what the monitors actually
// observed. This test class doesn't even know the scoreboard exists.
//
// Reset is still applied directly here via the interface, since reset
// sequencing is a testbench-level concern, not a per-transaction one --
// no class in the agent layer owns reset.
// =============================================================================

class fifo_sanity_test;

  env e;
  virtual fifo_if #(.W(8)) vif;

  int DEPTH;

  function new(env e_, virtual fifo_if #(.W(8)) vif_, int depth_);
    e     = e_;
    vif   = vif_;
    DEPTH = depth_;
  endfunction

  task apply_reset();
    // Reset itself is applied and waited-out by tb_top before this test is
    // even constructed; this task just confirms idle pin values, mirroring
    // the directed TB's pre-test idle state.
    vif.w_en  = 1'b0;
    vif.r_en  = 1'b0;
    vif.wdata = '0;
    @(posedge vif.wclk);
    #1;
  endtask

  task run();
    fifo_transaction t;

    $display("=============================================================");
    $display(" fifo_sanity_test (class-based) starting");
    $display("=============================================================");

    apply_reset();

    // ---------------------------------------------------------------
    // Fill to full: push DEPTH write transactions, one per cycle
    // (delay_cy = 0 means "issue immediately, no idle gap"). The
    // sequencer/driver issue these one at a time since the driver loop
    // processes its mailbox serially -- this naturally reproduces the
    // directed TB's one-write-per-cycle pacing.
    // ---------------------------------------------------------------
    $display("--- Filling FIFO to full (%0d writes) ---", DEPTH);
    for (int i = 0; i < DEPTH; i++) begin
      t = new(OP_WRITE, i[7:0], 0);
      e.wagent.seqr.put(t);
    end

    // Wait for all DEPTH writes to actually be driven before moving on.
    // Each write takes exactly 1 cycle once issued; add margin.
    repeat (DEPTH + 6) @(posedge vif.wclk);

    // ---------------------------------------------------------------
    // Write-while-full: issue one more write; driver will assert w_en
    // even though wfull is expected high, and the monitor will
    // correctly report it as not-accepted.
    // ---------------------------------------------------------------
    $display("--- Attempting write while full (should be ignored) ---");
    t = new(OP_WRITE, 8'hFF, 0);
    e.wagent.seqr.put(t);
    repeat (2) @(posedge vif.wclk);

    // ---------------------------------------------------------------
    // Drain to empty: push DEPTH read transactions.
    // ---------------------------------------------------------------
    $display("--- Draining FIFO to empty (%0d reads) ---", DEPTH);
    for (int i = 0; i < DEPTH; i++) begin
      t = new(OP_READ, 0, 0);
      e.ragent.seqr.put(t);
    end
    // Read completion is paced by read_driver on rclk, not wclk. With
    // independent, skewed clock periods (Phase 3) a wclk-counted wait no
    // longer bounds read-side completion -- must wait on rclk here.
    repeat (DEPTH + 6) @(posedge vif.rclk);

    // ---------------------------------------------------------------
    // Read-while-empty: should be ignored.
    // ---------------------------------------------------------------
    $display("--- Attempting read while empty (should be ignored) ---");
    t = new(OP_READ, 0, 0);
    e.ragent.seqr.put(t);
    repeat (2) @(posedge vif.rclk);

    e.sb.report();
    // tb_top accumulates error_count and calls $finish after all scenarios.
  endtask

endclass