`timescale 1ns / 1ps
// =============================================================================
// rptr_empty_sva.sv
//
// Bind-attached assertion module for rptr_empty.v. Mirror of
// wptr_full_sva.sv for the read side -- same reasoning throughout, see
// that file's header for the full rationale. Never modifies rptr_empty.v
// itself. Added to the simulation fileset directly (plain module + bind,
// not a class -- does not go through fifo_tb_pkg.sv's `include`
// mechanism).
// =============================================================================

module rptr_empty_sva #(
    parameter N          = 4,
    parameter A_EMPTY_TH = 2
) (
    input  wire         rclk,
    input  wire         rrst_n,
    input  wire         r_en,
    input  wire [N:0]   wptr_gray_sync,
    input  wire [N:0]   rptr_gray,
    input  wire [N-1:0] raddr,
    input  wire         ren,
    input  wire         rempty,
    input  wire         arempty
);

  // ---------------------------------------------------------------------
  // Property 1: direct re-assertion of the empty-side DEF-001 invariant.
  // Same $past() reasoning as the write side: rempty was registered from
  // a snapshot of wptr_gray_sync taken the cycle before rptr_gray became
  // visible, so the correct comparison uses $past(wptr_gray_sync)
  // against the CURRENT rptr_gray -- not both current-cycle, which would
  // spuriously mismatch during any cycle the write side's sync value is
  // actively moving.
  // ---------------------------------------------------------------------
  property p_rempty_invariant;
    @(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n))
    rempty == (rptr_gray == $past(wptr_gray_sync));
  endproperty
  a_rempty_invariant: assert property (p_rempty_invariant)
    else $error("DEF-001 REGRESSION (read side): rempty does not match rptr_gray vs prior-cycle wptr_gray_sync");

  // ---------------------------------------------------------------------
  // Property 2: structural Gray-code correctness, independent of the
  // empty-flag logic.
  // ---------------------------------------------------------------------
  property p_rptr_gray_one_bit;
    @(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n))
    $countones(rptr_gray ^ $past(rptr_gray)) <= 1;
  endproperty
  a_rptr_gray_one_bit: assert property (p_rptr_gray_one_bit)
    else $error("rptr_gray changed by more than one bit in a single cycle");

  // ---------------------------------------------------------------------
  // Property 3: underflow safety net, independent of the RTL's own
  // `wire ren = r_en & ~rempty` line -- states the outcome directly.
  // ---------------------------------------------------------------------
  property p_no_read_while_empty;
    @(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n))
    !(ren && rempty);
  endproperty
  a_no_read_while_empty: assert property (p_no_read_while_empty)
    else $error("ren asserted while rempty is high -- underflow safety violated");

  // ---------------------------------------------------------------------
  // Property 4: reset recovery. Note rempty's defined reset value is 1
  // (FIFO starts empty), not 0 -- mirrors rptr_empty.v's own reset branch.
  // arempty's reset value is also 1 (DEF-003 fix: an empty FIFO is always
  // within the almost-empty threshold by definition) -- this assertion
  // previously still expected the pre-DEF-003 value of 0 here, which no
  // longer matches what rptr_empty.v is deliberately coded to do.
  // ---------------------------------------------------------------------
  property p_reset_recovery;
    @(posedge rclk) $rose(rrst_n) |-> (rptr_gray == '0 && rempty == 1'b1 && arempty == 1'b1);
  endproperty
  a_reset_recovery: assert property (p_reset_recovery)
    else $error("rptr_gray/rempty/arempty not in defined state immediately after rrst_n release");

  // ---------------------------------------------------------------------
  // Property 5: X-propagation insurance.
  // ---------------------------------------------------------------------
  a_no_x_rempty: assert property (@(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n)) !$isunknown(rempty))
    else $error("rempty is X/Z");
  a_no_x_arempty: assert property (@(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n)) !$isunknown(arempty))
    else $error("arempty is X/Z");
  a_no_x_raddr: assert property (@(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n)) ren |-> !$isunknown(raddr))
    else $error("raddr is X/Z during a qualified read");

  // ---------------------------------------------------------------------
  // Coverage.
  // ---------------------------------------------------------------------
  c_rempty_seen_high:  cover property (@(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n)) rempty);
  c_rempty_seen_low:   cover property (@(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n)) !rempty);
  c_arempty_seen_high: cover property (@(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n)) arempty);
  c_arempty_seen_low:  cover property (@(posedge rclk) disable iff (!rrst_n || $isunknown(rrst_n)) !arempty);

endmodule

bind rptr_empty rptr_empty_sva #(.N(N), .A_EMPTY_TH(A_EMPTY_TH)) u_rptr_empty_sva (.*);