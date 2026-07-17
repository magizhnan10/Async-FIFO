`timescale 1ns / 1ps

module wptr_full #(
    parameter N         = 4,
    parameter A_FULL_TH = 2
) (
    input  wire           wclk,
    input  wire           wrst_n,
    input  wire           w_en,
    input  wire [N:0]     rptr_gray_sync,   // from sync_r2w

    output reg  [N:0]     wptr_gray,        // to sync_w2r
    output wire [N-1:0]   waddr,            // to fifo_mem
    output wire           wen,              // to fifo_mem
    output reg            wfull,
    output reg            awfull
);

    //  Binary write pointer
    reg [N:0] wptr;

    //  Memory address and qualified write enable
    assign waddr = wptr[N-1:0];
    assign wen   = w_en & ~wfull;

    //  Combinational look-ahead pointer/gray value -- gated by `wen`,
    //  the SAME qualified enable that actually advances wptr below, so
    //  wptr_next always equals exactly what wptr_gray is about to
    //  become on this edge (holds steady, self-consistently, when no
    //  write occurs -- including when blocked by wfull itself).
    //  BUG FIX #1: the original compared the already-registered
    //  wptr_gray (one cycle stale relative to the wptr_gray update in
    //  the same always block below), so wfull asserted one full cycle
    //  after the FIFO was actually full, letting one extra write
    //  through and corrupting mem[0].
    //  BUG FIX #2 (caught in simulation while verifying fix #1): an
    //  earlier version of this fix used an UNGATED "wptr + 1" here.
    //  That runs ahead even while writes are blocked, so the cycle
    //  after the FIFO fills, wgray_next no longer matches the full
    //  pattern and wfull incorrectly self-clears even though nothing
    //  was actually written. Gating by `wen` fixes that.
    wire [N:0] wptr_next  = wen ? (wptr + 1'b1) : wptr;
    wire [N:0] wgray_next = (wptr_next >> 1) ^ wptr_next;

    //  Pointer increment and Gray encoding
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wptr      <= {(N+1){1'b0}};
            wptr_gray <= {(N+1){1'b0}};
        end else begin
            if (wen) begin
                wptr      <= wptr_next;
                wptr_gray <= wgray_next;
            end
        end
    end

    //  Full condition (Gray domain comparison) -- compares the
    //  look-ahead wgray_next, so this register updates in lockstep with
    //  wptr_gray above instead of lagging it by one cycle. Also
    //  re-evaluated every cycle (not just on writes) so wfull correctly
    //  deasserts as soon as rptr_gray_sync moves, even with no write.
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wfull <= 1'b0;
        end else begin
            wfull <= (wgray_next == {~rptr_gray_sync[N:N-1],
                                      rptr_gray_sync[N-2:0]});
        end
    end
    
    //  Almost-full condition
    integer i;
    reg [N:0] rptr_bin_sync;

    always @(*) begin
        rptr_bin_sync[N] = rptr_gray_sync[N];
        for (i = N-1; i >= 0; i = i - 1)
            rptr_bin_sync[i] = rptr_bin_sync[i+1] ^ rptr_gray_sync[i];
    end

    //  Almost-full condition. Same sized-intermediate-wire fix as
    //  arempty in rptr_empty.v: forces N+1-bit modular arithmetic
    //  instead of letting the unsized A_FULL_TH/(1<<N) parameters
    //  promote the subtraction to 32-bit context and break wraparound.
    wire [N:0] full_diff = wptr_next - rptr_bin_sync;

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            awfull <= 1'b0;
        end else begin
            awfull <= (full_diff >= ((1 << N) - A_FULL_TH));
        end
    end

endmodule