`timescale 1ns / 1ps

// =============================================================================
// wptr_full_sva.sv
//
// Bind-attached assertion module for wptr_full.v. Never modifies
// wptr_full.v itself -- it's already been through a careful fix-and-verify
// cycle (DEF-001: stale look-ahead comparison; DEF-002: ungated wptr+1
// breaking the full pattern) and shouldn't be touched again just to add
// checking logic. Connected via `bind` at the bottom of this file, added
// to the simulation fileset directly (this is a plain module + bind
// statement, NOT a class -- unlike random_fifo_txn.sv, it does NOT go
// through the `include` mechanism in fifo_tb_pkg.sv).
// =============================================================================

module wptr_full_sva #(
    parameter N         = 4,
    parameter A_FULL_TH = 2
) (
    input  wire         wclk,
    input  wire         wrst_n,
    input  wire         w_en,
    input  wire [N:0]   rptr_gray_sync,
    input  wire [N:0]   wptr_gray,
    input  wire [N-1:0] waddr,
    input  wire         wen,
    input  wire         wfull,
    input  wire         awfull
);

  // ---------------------------------------------------------------------
  // Property 1: direct re-assertion of DEF-001's invariant.
  //
  // wptr_full.v registers wfull one cycle ahead of when wptr_gray becomes
  // visible, both driven from the SAME wgray_next look-ahead value and
  // the SAME snapshot of rptr_gray_sync taken that cycle. Because
  // rptr_gray_sync itself keeps updating every cycle (it's a live
  // synchronizer output, not gated), checking wfull against the CURRENT
  // cycle's wptr_gray and CURRENT cycle's rptr_gray_sync would produce
  // spurious mismatches during any cycle the read side's sync value is
  // actively moving -- a false failure, not a caught bug. $past() aligns
  // the comparison with the actual snapshot the RTL used, which is what
  // makes this assertion unconditionally true when the DUT is correct,
  // and immediately false if DEF-001's staleness bug is reintroduced.
  // ---------------------------------------------------------------------
  property p_wfull_invariant;
    @(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n))
    wfull == (wptr_gray == {~$past(rptr_gray_sync[N:N-1]), $past(rptr_gray_sync[N-2:0])});
  endproperty
  a_wfull_invariant: assert property (p_wfull_invariant)
    else $error("DEF-001 REGRESSION: wfull does not match wptr_gray vs prior-cycle rptr_gray_sync");

  // ---------------------------------------------------------------------
  // Property 2: structural Gray-code correctness, independent of the
  // full-flag logic entirely -- catches a broken encoder even if the
  // full/empty comparison above happened to still pass.
  // ---------------------------------------------------------------------
  property p_wptr_gray_one_bit;
    @(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n))
    $countones(wptr_gray ^ $past(wptr_gray)) <= 1;
  endproperty
  a_wptr_gray_one_bit: assert property (p_wptr_gray_one_bit)
    else $error("wptr_gray changed by more than one bit in a single cycle");

  // ---------------------------------------------------------------------
  // Property 3: overflow safety net. Deliberately independent of the
  // RTL's own `assign wen = w_en & ~wfull` -- restates the safety
  // OUTCOME directly rather than re-deriving the same line it would be
  // checking, so it's a genuinely separate statement of intent.
  // ---------------------------------------------------------------------
  property p_no_write_while_full;
    @(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n))
    !(wen && wfull);
  endproperty
  a_no_write_while_full: assert property (p_no_write_while_full)
    else $error("wen asserted while wfull is high -- overflow safety violated");

  // ---------------------------------------------------------------------
  // Property 4: reset recovery. Closes part of the reset gap flagged
  // earlier -- confirms defined state is reached, not just "no error was
  // thrown during reset".
  // ---------------------------------------------------------------------
  property p_reset_recovery;
    @(posedge wclk) $rose(wrst_n) |-> (wptr_gray == '0 && wfull == 1'b0 && awfull == 1'b0);
  endproperty
  a_reset_recovery: assert property (p_reset_recovery)
    else $error("wptr_gray/wfull/awfull not in defined state immediately after wrst_n release");

  // ---------------------------------------------------------------------
  // Property 5: X-propagation insurance.
  // ---------------------------------------------------------------------
  a_no_x_wfull: assert property (@(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n)) !$isunknown(wfull))
    else $error("wfull is X/Z");
  a_no_x_awfull: assert property (@(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n)) !$isunknown(awfull))
    else $error("awfull is X/Z");
  a_no_x_waddr: assert property (@(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n)) wen |-> !$isunknown(waddr))
    else $error("waddr is X/Z during a qualified write");

  // ---------------------------------------------------------------------
  // Coverage: proves the assertions above actually had the opportunity
  // to fire during a run -- an assertion that's never been exercised in
  // either direction is not evidence of correctness.
  // ---------------------------------------------------------------------
  c_wfull_seen_high:  cover property (@(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n)) wfull);
  c_wfull_seen_low:   cover property (@(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n)) !wfull);
  c_awfull_seen_high: cover property (@(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n)) awfull);
  c_awfull_seen_low:  cover property (@(posedge wclk) disable iff (!wrst_n || $isunknown(wrst_n)) !awfull);

endmodule

bind wptr_full wptr_full_sva #(.N(N), .A_FULL_TH(A_FULL_TH)) u_wptr_full_sva (.*);