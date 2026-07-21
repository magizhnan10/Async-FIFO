// =============================================================================
// read_monitor.sv
//
// Mirrors write_monitor's structure, sampling discipline, and single-packet
// reporting (see monitor_pkt.sv for why bundling matters). One asymmetry:
// rdata is a registered DUT OUTPUT that updates as a *result* of the read,
// so unlike wdata (an input the driver holds steady through the cycle),
// rdata is sampled AFTER the edge, not before. r_en/rempty are still
// sampled pre-edge since they govern whether the read is accepted at all.
// =============================================================================

class read_monitor;

  virtual fifo_if #(.W(8)) vif;
  mailbox #(rmon_pkt_t) pkt_mbx;

  function new(virtual fifo_if #(.W(8)) vif_);
    vif     = vif_;
    pkt_mbx = new();
  endfunction

  task run();
    bit pre_rempty;
    bit pre_r_en;
    rmon_pkt_t pkt;

    forever begin
      @(negedge vif.rclk);
      pre_rempty = vif.rempty;
      pre_r_en   = vif.r_en;

      @(posedge vif.rclk);
      #1; // allow rdata/flags to settle post-edge

      pkt.accepted = pre_r_en && !pre_rempty;
      pkt.data     = vif.rdata;
      pkt.rempty   = vif.rempty;
      pkt.arempty  = vif.arempty;

      pkt_mbx.put(pkt);
    end
  endtask

endclass