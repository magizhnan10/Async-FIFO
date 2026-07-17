// =============================================================================
// write_agent.sv
//
// Bundles write_sequencer + write_driver + write_monitor, per the layered
// architecture table (an "agent" = sequencer + driver + monitor for one
// interface side). The env instantiates one write_agent and one
// read_agent rather than wiring 6 separate classes together itself --
// this is what keeps env.sv readable as complexity grows later.
// =============================================================================

class write_agent;

  write_sequencer seqr;
  write_driver    drv;
  write_monitor   mon;

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
