// =============================================================================
// scoreboard.sv
//
// Absorbs the directed testbench's ref_queue/ref_push/ref_pop plus its
// inline flag-boundary checks, restructured as an independent class that
// listens to monitors via mailboxes.
//
// Write-side and read-side are handled by two independent forever-loops,
// each blocking on its OWN monitor's mailbox via a plain get() (not a
// clock-aligned poll). This is safe specifically because write_monitor and
// read_monitor each push exactly one packet per clock cycle, unconditionally
// (see monitor_pkt.sv) -- so a blocking get() per loop iteration is already
// aligned to the clock with no risk of ever blocking past a cycle boundary.
//
// EACH loop is internally atomic: for a given packet, the fill_level update
// and the flag check against that same fill_level happen in the same
// procedural step, with no intervening blocking statement that could let
// the other loop interleave mid-update. This is what fixes the race
// monitor_pkt.sv's own header describes from an earlier version that split
// data-update and flag-check into separate processes reading separate
// mailboxes.
//
// PHASE 2 FIX: an earlier version of this file funneled BOTH sides' flag
// checks through a single unified polling loop, with all four flag-check
// blocks nested inside "if (wmon.pkt_mbx.try_get(wpkt))". That silently
// skipped every read-side flag check (rempty/arempty) on any cycle with a
// read but no write, and made those checks read a possibly-stale rpkt left
// over from a prior cycle when no fresh read packet had arrived. Splitting
// into two genuinely independent get()-driven loops removes both problems
// at the root, and is also a more direct implementation of what this
// header already claimed the design did.
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

  // PHASE 2 FIX: single source of truth for the flag-boundary settle
  // margin, replacing four independent hardcoded "3"s. Derived from
  // sync_2ff.v's actual synchronizer depth (2 flops) plus one cycle of
  // combinational settle allowance -- not an arbitrary number. Exposed as
  // a constructor arg (with that derivation as the default) so it stays
  // adjustable without hunting through four separate comparisons, and so
  // it's the one place that needs revisiting once Phase 3 moves margins
  // from cycle counts to time units for independent clocks.
  localparam int SYNC_STAGES = 2;
  int SETTLE_MARGIN;

  function new(write_monitor wmon_, read_monitor rmon_,
               int depth_, int a_full_th_, int a_empty_th_,
               int settle_margin_ = SYNC_STAGES + 1);
    wmon          = wmon_;
    rmon          = rmon_;
    DEPTH         = depth_;
    A_FULL_TH     = a_full_th_;
    A_EMPTY_TH    = a_empty_th_;
    SETTLE_MARGIN = settle_margin_;
    fill_level    = 0;
    error_count   = 0;
    check_count   = 0;
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
    // PHASE 2 FIX: two independent blocking loops instead of one shared
    // clock-aligned poll. Each blocks on its own monitor's mailbox; since
    // each monitor pushes exactly one packet per cycle unconditionally,
    // this stays clock-aligned with no risk of drift, while making each
    // side's flag checks run on every cycle of THAT side's activity,
    // regardless of whether the other side had a transaction this cycle.
    fork
      begin : write_side
        wmon_pkt_t wpkt;
        forever begin
          wmon.pkt_mbx.get(wpkt);

          if (wpkt.accepted) begin
            ref_queue.push_back(wpkt.data);
            fill_level++;
          end

          // Write Flag Checks -- evaluated every cycle a write packet
          // arrives (i.e. every cycle), using this cycle's own packet.
          if (fill_level >= DEPTH)
            check((wpkt.wfull === 1'b1), "wfull must be 1 when completely full");
          else if (fill_level < DEPTH - SETTLE_MARGIN)
            check((wpkt.wfull === 1'b0), "wfull must be 0 after sync delay has passed");

          // Almost-Full Flag Checks (awfull) -- mirror of the arempty
          // checks below, shifted by A_FULL_TH from the hard-full boundary.
          if (fill_level >= DEPTH - A_FULL_TH)
            check((wpkt.awfull === 1'b1), "awfull must be 1 at/above almost-full threshold");
          else if (fill_level < DEPTH - A_FULL_TH - SETTLE_MARGIN)
            check((wpkt.awfull === 1'b0), "awfull must be 0 well below almost-full threshold");
        end
      end
      begin : read_side
        rmon_pkt_t rpkt;
        forever begin
          rmon.pkt_mbx.get(rpkt);

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

          // Read Flag Checks -- evaluated every cycle a read packet
          // arrives (i.e. every cycle), using this cycle's own packet.
          // No longer gated on write activity, and no longer reading a
          // possibly-stale packet from a prior cycle.
          if (fill_level == 0)
            check((rpkt.rempty === 1'b1), "rempty must be 1 when completely empty");
          else if (fill_level > SETTLE_MARGIN)
            check((rpkt.rempty === 1'b0), "rempty must be 0 after sync delay has passed");

          // Almost-Empty Flag Checks (arempty) -- same shape as the
          // rempty checks above, shifted by A_EMPTY_TH: "must be 1" is
          // checked at/inside the threshold itself (no margin needed,
          // since arempty tracks in lockstep once settled, same as
          // rempty does); "must be 0" keeps a SETTLE_MARGIN-level margin
          // above the threshold so a transiently-stale synchronized
          // pointer during concurrent r+w can't produce a false FAIL.
          if (fill_level <= A_EMPTY_TH)
            check((rpkt.arempty === 1'b1), "arempty must be 1 at/below almost-empty threshold");
          else if (fill_level > A_EMPTY_TH + SETTLE_MARGIN)
            check((rpkt.arempty === 1'b0), "arempty must be 0 well above almost-empty threshold");
        end
      end
    join_none
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