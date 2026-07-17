// =============================================================================
// random_fifo_txn.sv
//
// Constrained-random producer for the FIFO testbench. Extends
// fifo_transaction rather than modifying it, per that file's own header
// comment: "the class shape itself shouldn't need to change when
// randomization is introduced later; only the sequence that fills it in
// changes." This class IS that later sequence-side change -- the base
// class, sequencers, drivers, monitors, and scoreboard are all reused
// completely unchanged.
//
// Knobs (wr_weight/rd_weight, delay distribution) are plain class members,
// not hardcoded into the constraint, so a test/sequence can retarget the
// mix before calling randomize() -- e.g. a write-heavy fill-stress pass
// vs. a read-heavy drain-stress pass vs. a balanced steady-state pass --
// without needing a new class per scenario.
// =============================================================================

class random_fifo_txn extends fifo_transaction;

  // ---------------------------------------------------------------------
  // Op mix. Plain (non-rand) ints read by the dist constraint below --
  // override on the instance before randomize() to bias write-heavy,
  // read-heavy, or balanced traffic. Defaults to a balanced mix.
  // ---------------------------------------------------------------------
  int unsigned wr_weight = 50;
  int unsigned rd_weight = 50;

  constraint c_op_mix {
    op dist { OP_WRITE := wr_weight, OP_READ := rd_weight };
  }

  // ---------------------------------------------------------------------
  // Delay-before-issue. Heavily biased toward 0 (back-to-back, no gap)
  // since that's the window test_boundary_backtoback.sv showed to be the
  // one that actually exposes flag-timing bugs as data corruption rather
  // than a flag mismatch -- random stimulus should keep landing in that
  // window often, not just occasionally. The tail out to 5 still gives
  // some cycles with genuine idle gaps between transactions.
  // ---------------------------------------------------------------------
  constraint c_delay {
    delay_cy dist {
      0       := 60,
      [1:2]   := 25,
      [3:5]   := 15
    };
  }

  // ---------------------------------------------------------------------
  // Data payload. Mostly uniform random, with a small weighted bias
  // toward the two corner values (all-0s / all-1s) that are most likely
  // to expose a stuck-at or bit-slice bug in fifo_mem's byte array if one
  // exists -- without displacing the bulk of coverage from full-range
  // random data.
  // ---------------------------------------------------------------------
  constraint c_data {
    data dist {
      8'h00        := 10,
      8'hFF        := 10,
      [8'h01:8'hFE] := 80
    };
  }

  function new(op_e op_ = OP_WRITE, bit [7:0] data_ = 0, int delay_cy_ = 0);
    super.new(op_, data_, delay_cy_);
  endfunction

endclass
