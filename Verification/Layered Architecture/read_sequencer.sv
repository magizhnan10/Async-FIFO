// =============================================================================
// read_sequencer.sv
//
// Mirror of write_sequencer for the read side. Kept as a separate class
// (not templated/shared) because write and read sequencing will diverge
// once randomization and independent clocking are introduced -- forcing
// them through one shared class now would just mean un-sharing them later.
// =============================================================================

class read_sequencer;

  mailbox #(fifo_transaction) trans_mbx;

  function new();
    trans_mbx = new();
  endfunction

  task put(fifo_transaction t);
    trans_mbx.put(t);
  endtask

endclass
