// =============================================================================
// scoreboard.sv
//
// Absorbs the directed testbench's ref_queue/ref_push/ref_pop plus its
// inline flag-boundary checks, restructured as an independent class that
// listens to monitors via mailboxes.
//
// Write-side and read-side are handled by two independent forever-loops
// (legitimately independent, since they are independent data streams), but
// EACH loop is internally atomic: for a given packet, the fill_level update
// and the flag check against that same fill_level happen in the same
// procedural step, with no intervening process that could observe a
// half-updated state. This is what fixes the race present in an earlier
// version that split data-update and flag-check into separate processes
// reading separate mailboxes.
//
// fill_level is shared mutable state between the two loops (a write
// increments it, a read decrements it) -- in SystemVerilog, ordinary
// variable read/modify/write inside one begin/end block without an
// intervening blocking statement is not preemptible, so each loop's
// "update fill_level then check flags derived from it" sequence is safe
// even though both loops run concurrently.
// =============================================================================

class scoreboard;

  write_monitor wmon;
  read_monitor  rmon;

  int A_FULL_TH;
  int A_EMPTY_TH;
  int DEPTH;

  bit [7:0] ref_queue[$];

  // Independent fill-level tracker, driven only by accepted writes/reads
  // observed via monitor packets -- the scoreboard's own model of FIFO
  // occupancy, used to predict expected flag values (the "predictor" role
  // folded into the scoreboard, per the plan).
  int fill_level;

  int error_count;
  int check_count;

  function new(write_monitor wmon_, read_monitor rmon_,
               int depth_, int a_full_th_, int a_empty_th_);
    wmon        = wmon_;
    rmon        = rmon_;
    DEPTH       = depth_;
    A_FULL_TH   = a_full_th_;
    A_EMPTY_TH  = a_empty_th_;
    fill_level  = 0;
    error_count = 0;
    check_count = 0;
  endfunction

  task check(bit cond, string msg);
    check_count++;
    if (!cond) begin
      error_count++;
      $display("[%0t] FAIL: %s", $time, msg);
    end else begin
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask


 task run();
    wmon_pkt_t wpkt;
    rmon_pkt_t rpkt;
    
    forever begin
      // Wait for a clock edge, plus margin to let monitors push their packets
      @(posedge wmon.vif.clk);
      #2; 
      
      // 1. Evaluate Reads (decrement fill_level)
      if (rmon.pkt_mbx.try_get(rpkt)) begin
        if (rpkt.accepted) begin
          if (ref_queue.size() == 0) begin
            check(0, "read observed as accepted but reference queue is empty");
          end else begin
            bit [7:0] expected = ref_queue.pop_front();
            fill_level--;
            check((rpkt.data === expected), 
                  $sformatf("rdata mismatch: got 0x%0h expected 0x%0h", rpkt.data, expected));
          end
        end
        // We will update the flag checks below
      end

      // 2. Evaluate Writes (increment fill_level)
      if (wmon.pkt_mbx.try_get(wpkt)) begin
        if (wpkt.accepted) begin
          ref_queue.push_back(wpkt.data);
          fill_level++;
        end
        // We will update the flag checks below
        // Pessimistic Read Flag Checks
      if (rpkt.accepted || rpkt.rempty != rmon.vif.rempty) begin
        if (fill_level == 0) 
            check((rpkt.rempty === 1'b1), "rempty must be 1 when completely empty");
        else if (fill_level > 3) 
            check((rpkt.rempty === 1'b0), "rempty must be 0 after sync delay has passed");
      end

      // Pessimistic Almost-Empty Flag Checks (arempty) -- same shape as
      // the rempty checks above, shifted by A_EMPTY_TH: "must be 1" is
      // checked at/inside the threshold itself (no margin needed, since
      // arempty tracks in lockstep once settled, same as rempty does
      // post-fix); "must be 0" keeps a 3-level margin above the
      // threshold so a transiently-stale synchronized pointer during
      // concurrent r+w can't produce a false FAIL.
      if (rpkt.accepted || rpkt.arempty != rmon.vif.arempty) begin
        if (fill_level <= A_EMPTY_TH)
            check((rpkt.arempty === 1'b1), "arempty must be 1 at/below almost-empty threshold");
        else if (fill_level > A_EMPTY_TH + 3)
            check((rpkt.arempty === 1'b0), "arempty must be 0 well above almost-empty threshold");
      end

      // Pessimistic Write Flag Checks
      if (wpkt.accepted || wpkt.wfull != wmon.vif.wfull) begin
        if (fill_level >= DEPTH) 
            check((wpkt.wfull === 1'b1), "wfull must be 1 when completely full");
        else if (fill_level < DEPTH - 3) 
            check((wpkt.wfull === 1'b0), "wfull must be 0 after sync delay has passed");
      end

      // Pessimistic Almost-Full Flag Checks (awfull) -- mirror of the
      // arempty checks above, shifted by A_FULL_TH from the hard-full
      // boundary.
      if (wpkt.accepted || wpkt.awfull != wmon.vif.awfull) begin
        if (fill_level >= DEPTH - A_FULL_TH)
            check((wpkt.awfull === 1'b1), "awfull must be 1 at/above almost-full threshold");
        else if (fill_level < DEPTH - A_FULL_TH - 3)
            check((wpkt.awfull === 1'b0), "awfull must be 0 well below almost-full threshold");
      end
      
      end
    end
  endtask

  // Call between test scenarios to clear accumulated state. The monitors'
  // mailboxes are also flushed so stale packets from a prior scenario don't
  // bleed into the next one's checks.
  function void reset();
    wmon_pkt_t wp;
    rmon_pkt_t rp;
    ref_queue.delete();
    fill_level  = 0;
    error_count = 0;
    check_count = 0;
    // drain any unconsumed packets left in the monitor mailboxes
    while (wmon.pkt_mbx.try_get(wp)) ;
    while (rmon.pkt_mbx.try_get(rp)) ;
  endfunction

  function void report();
    $display("=============================================================");
    if (error_count == 0)
      $display(" SCOREBOARD RESULT: ALL %0d CHECKS PASSED", check_count);
    else
      $display(" SCOREBOARD RESULT: %0d / %0d CHECKS FAILED", error_count, check_count);
    $display("=============================================================");
  endfunction

endclass