// =============================================================================
// write_monitor.sv
//
// New class with no direct equivalent in the directed testbench -- there,
// one task both drove pins and judged correctness inline. Here the monitor
// only observes and reports; acceptance is judged from DUT pin state
// (w_en && !wfull going into the edge), not from driver intent.
//
// Sampling discipline:
//   wfull/w_en must be sampled at the value they hold GOING INTO a posedge,
//   not the value they settle to immediately after -- sampling exactly at
//   posedge races against the DUT's own posedge-triggered updates. We
//   sample at the negedge immediately before each posedge instead: with a
//   50% duty clock this is the stable midpoint of the cycle, strictly
//   before the next posedge, so there's no race against the DUT.
//
// Reporting discipline:
//   Accept-status, data, and flags for a given cycle are bundled into a
//   single wmon_pkt_t and sent through ONE mailbox -- see monitor_pkt.sv
//   for why this matters (avoids a separate race on the scoreboard side).
// =============================================================================

class write_monitor;

  virtual fifo_if #(.W(8)) vif;
  mailbox #(wmon_pkt_t) pkt_mbx;

  function new(virtual fifo_if #(.W(8)) vif_);
    vif     = vif_;
    pkt_mbx = new();
  endfunction

  task run();
    bit       pre_wfull;
    bit       pre_w_en;
    bit [7:0] pre_wdata;
    wmon_pkt_t pkt;

    forever begin
      // Stable pre-edge sample point.
      @(negedge vif.clk);
      pre_wfull = vif.wfull;
      pre_w_en  = vif.w_en;
      pre_wdata = vif.wdata;

      // Edge that actually applies this state.
      @(posedge vif.clk);
      #1; // allow post-edge flag updates to settle

      pkt.accepted = pre_w_en && !pre_wfull;
      pkt.data     = pre_wdata;
      pkt.wfull    = vif.wfull;
      pkt.awfull   = vif.awfull;

      pkt_mbx.put(pkt);
    end
  endtask

endclass
