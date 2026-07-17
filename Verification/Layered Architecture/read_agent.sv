// =============================================================================
// read_agent.sv
//
// Mirror of write_agent for the read side.
// =============================================================================

class read_agent;

  read_sequencer seqr;
  read_driver    drv;
  read_monitor   mon;

  function new(virtual fifo_if #(.W(8)) vif);
    seqr = new();
    drv  = new(vif, seqr);
    mon  = new(vif);
  endfunction

  task run();
    fork
      drv.run();
      mon.run();
    join_none
  endtask

endclass
