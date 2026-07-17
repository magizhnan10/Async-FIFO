// =============================================================================
// write_sequencer.sv
//
// Stage 3: no randomization, so this is a thin mailbox wrapper. Its job is
// purely structural -- it's the seam between "what to do" (a test method
// filling the mailbox) and "how to do it" (the driver pulling from it).
// When constrained-random is introduced later, only the producer side
// changes (a sequence class randomizes transactions and pushes them here);
// the driver and this sequencer class do not change at all.
// =============================================================================

class write_sequencer;

  mailbox #(fifo_transaction) trans_mbx;

  function new();
    trans_mbx = new();
  endfunction

  // Called by a test/sequence to queue up a transaction for the driver.
  task put(fifo_transaction t);
    trans_mbx.put(t);
  endtask

endclass
