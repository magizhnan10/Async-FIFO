// =============================================================================
// read_driver.sv
//
// Mirror of write_driver for the read side. Same separation-of-concerns
// rule applies: this class drives r_en for exactly one cycle per
// transaction and does not check rempty correctness or rdata content --
// that's the read_monitor + scoreboard's job.
// =============================================================================

class read_driver;

  virtual fifo_if #(.W(8)) vif;
  read_sequencer            seqr;

  function new(virtual fifo_if #(.W(8)) vif_, read_sequencer seqr_);
    vif  = vif_;
    seqr = seqr_;
  endfunction

  task run();
    fifo_transaction t;
    forever begin
      seqr.trans_mbx.get(t);
      repeat (t.delay_cy) @(posedge vif.clk);

      vif.r_en <= 1'b1;
      @(posedge vif.clk);
      vif.r_en <= 1'b0;
    end
  endtask

endclass
