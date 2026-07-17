// =============================================================================
// monitor_pkt.sv
//
// Why this file exists:
//   An earlier version of this testbench reported "accepted write data" and
//   "flag values" via two SEPARATE mailboxes, consumed by two separate
//   forever-loops inside the scoreboard. That's a real race: both mailboxes
//   get written in the same simulation timestep (right after the monitor's
//   post-edge settle delay), but SystemVerilog gives no ordering guarantee
//   about which of two independent processes drains its mailbox first.
//   Concretely, the flag-checking process could read scoreboard.fill_level
//   BEFORE the data-integrity process has incremented it for this cycle's
//   write, producing a spurious flag mismatch that has nothing to do with
//   the DUT.
//
//   The fix: bundle "did a write/read happen this cycle, with what data"
//   and "what flags resulted this cycle" into ONE struct, sent through ONE
//   mailbox, consumed by ONE process. There is then no cross-process
//   ordering question -- the scoreboard updates fill_level and checks
//   flags from the same packet, in the same procedural block, atomically
//   with respect to other scoreboard activity.
// =============================================================================

typedef struct packed {
  bit       accepted;   // was a write actually consumed this cycle?
  bit [7:0] data;       // data consumed (valid only if accepted)
  bit       wfull;
  bit       awfull;
} wmon_pkt_t;

typedef struct packed {
  bit       accepted;   // was a read actually consumed this cycle?
  bit [7:0] data;       // data produced (valid only if accepted)
  bit       rempty;
  bit       arempty;
} rmon_pkt_t;
