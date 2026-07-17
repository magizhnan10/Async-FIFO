// =============================================================================
// fifo_tb_pkg.sv
//
// Wraps every testbench class file in one package so Vivado's file-by-file
// compile order stops mattering. Global Include didn't work for this because
// it's built for macro/header-style content, not for making class
// declarations visible across independently-analyzed files -- a package
// with `include is the correct mechanism for a class library like this one.
//
// Order INSIDE this file still matters (SystemVerilog classes still need
// their dependencies declared first within the same compilation), but that's
// now the only place order matters -- everything outside this file just
// needs "fifo_tb_pkg.sv compiles before tb_top.sv", full stop.
//
// fifo_if.sv is deliberately NOT included here. It's a SystemVerilog
// `interface`, not a class, and interfaces are compilation-unit-scoped
// constructs (like modules) rather than package-scoped ones. Keep it as a
// normal, separate simulation source that compiles before this package.
// =============================================================================

package fifo_tb_pkg;

  `include "monitor_pkt.sv"
  `include "fifo_transaction.sv"
  `include "random_fifo_txn.sv"

  `include "write_sequencer.sv"
  `include "write_driver.sv"
  `include "write_monitor.sv"
  `include "write_agent.sv"

  `include "read_sequencer.sv"
  `include "read_driver.sv"
  `include "read_monitor.sv"
  `include "read_agent.sv"

  `include "scoreboard.sv"
  `include "env.sv"

  `include "../Tests/fifo_sanity_test.sv"
  `include "../Tests/test_boundary_backtoback.sv"
  `include "../Tests/test_wraparound.sv"
  `include "../Tests/test_concurrent_rw.sv"
  `include "../Tests/test_full_boundary.sv"
  `include "../Tests/test_empty_boundary.sv"
  `include "../Tests/test_threshold_flags.sv"

endpackage