// =============================================================================
// write_driver.sv
//
// Replaces do_write() from the directed testbench. Key architectural
// change: the driver ONLY drives pins. It does not check wfull, does not
// maintain a reference model, and does not decide pass/fail -- all of that
// moved to the monitor + scoreboard. This is the separation that lets the
// driver later be reused unchanged under constrained-random stimulus, and
// reused unchanged once wclk becomes independent of rclk.
//
// The driver DOES respect wfull operationally (it won't blindly assert
// w_en if the FIFO is full when told to write) -- but that's a *driving*
// decision (don't issue a transaction that the protocol can't accept this
// cycle), not a *checking* decision. Whether wfull behaved correctly is the
// monitor/scoreboard's job to judge, not the driver's.
// =============================================================================

class write_driver;

  virtual fifo_if #(.W(8)) vif;
  write_sequencer          seqr;

  function new(virtual fifo_if #(.W(8)) vif_, write_sequencer seqr_);
    vif  = vif_;
    seqr = seqr_;
  endfunction

  // Main driver loop: pull one transaction at a time, drive it for exactly
  // one clock, deassert w_en. Runs forever in its own process; the test
  // controls pacing by controlling what gets put into the sequencer.
  task run();
    fifo_transaction t;
    forever begin
      seqr.trans_mbx.get(t);

      // honor requested idle delay before driving
      repeat (t.delay_cy) @(posedge vif.clk);

      // Drive for exactly one cycle. If the FIFO happens to be full,
      // we still issue the request -- this lets a "write while full"
      // directed scenario be expressed naturally as a transaction the
      // driver issues anyway, with acceptance/rejection judged later by
      // the monitor from the DUT's actual pin behavior.
      vif.wdata <= t.data;
      vif.w_en  <= 1'b1;
      @(posedge vif.clk);
      vif.w_en  <= 1'b0;
    end
  endtask

endclass
