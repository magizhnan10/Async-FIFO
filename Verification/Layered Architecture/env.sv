// =============================================================================
// env.sv
//
// Top-level testbench environment: instantiates both agents and the
// scoreboard, and starts everything running. A test class configures and
// drives env (via the agents' sequencers); env itself contains no
// scenario-specific logic -- that separation is what lets multiple test
// classes reuse one env unchanged.
// =============================================================================

class env;

  virtual fifo_if #(.W(8)) vif;

  write_agent wagent;
  read_agent  ragent;
  scoreboard  sb;

  int DEPTH;
  int A_FULL_TH;
  int A_EMPTY_TH;

  function new(virtual fifo_if #(.W(8)) vif_,
               int depth_, int a_full_th_, int a_empty_th_);
    vif        = vif_;
    DEPTH      = depth_;
    A_FULL_TH  = a_full_th_;
    A_EMPTY_TH = a_empty_th_;

    wagent = new(vif);
    ragent = new(vif);
    sb     = new(wagent.mon, ragent.mon, DEPTH, A_FULL_TH, A_EMPTY_TH);
  endfunction

  // Reset DUT + scoreboard between test scenarios. rst_n is driven directly
  // here since reset is a testbench-level concern that lives above the agent
  // layer. The scoreboard's mailboxes are flushed to prevent stale packets
  // from a prior scenario bleeding into the next scenario's checks.
  //
  // PHASE 3: fork...join across both domains instead of a single clk wait,
  // so this works for any wclk/rclk period pair without assuming which one
  // is faster -- the effective hold/settle time becomes max(4 or 12 periods
  // of wclk, same of rclk) automatically.
  //
  // PHASE 4 FIX: a test scenario's own "wait for drain" margin undershooting
  // by even one transaction leaves that transaction still sitting, unread,
  // in the read (or write) sequencer's trans_mbx when reset() is called.
  // The driver isn't stopped by reset -- it just blocks in-flight until
  // rst_n releases, then happily dequeues and drives that leftover
  // transaction against the NEXT scenario's freshly-reset DUT state, well
  // after the scoreboard has already been reset to expect nothing. That
  // surfaces downstream as "read observed as accepted but reference queue
  // is empty" and cascading data mismatches, often several scenarios later
  // once the leftover transaction happens to get serviced. Flushing both
  // sequencers' trans_mbx here, in addition to the monitor mailboxes,
  // makes reset() a hard boundary regardless of whether a scenario's own
  // drain margin was exactly right.
  task reset(ref logic rst_n);
    fifo_transaction t;
    rst_n = 1'b0;
    fork
      repeat (4) @(posedge vif.wclk);
      repeat (4) @(posedge vif.rclk);
    join
    rst_n = 1'b1;
    fork
      repeat (12) @(posedge vif.wclk);
      repeat (12) @(posedge vif.rclk);
    join
    sb.reset();
    while (wagent.seqr.trans_mbx.try_get(t)) ;
    while (ragent.seqr.trans_mbx.try_get(t)) ;
  endtask

  task run();
    fork
      wagent.run();
      ragent.run();
      sb.run();
    join_none
  endtask

endclass