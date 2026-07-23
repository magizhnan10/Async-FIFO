// =============================================================================
// read_driver.sv
//
// Mirror of write_driver for the read side. Same separation-of-concerns
// rule applies: this class drives r_en for exactly one cycle per
// transaction and does not check rempty correctness or rdata content --
// that's the read_monitor + scoreboard's job.
//
// PHASE 5 FIX: mirror of write_driver.sv's rst_n check -- see that file's
// header for the full explanation. Without this, a transaction dequeued
// (or mid-delay_cy) right as env::reset() asserts rst_n would still get
// driven, sneaking a spurious read past the reset boundary and desyncing
// rptr from the scoreboard's reference queue by one entry.
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
      repeat (t.delay_cy) @(posedge vif.rclk);

      // PHASE 5 FIX: drop rather than drive if reset is asserted -- see
      // write_driver.sv's header comment for the full rationale.
      if (!vif.rst_n) begin
        vif.r_en <= 1'b0;
        continue;
      end

      vif.r_en <= 1'b1;
      @(posedge vif.rclk);
      vif.r_en <= 1'b0;
    end
  endtask

endclass