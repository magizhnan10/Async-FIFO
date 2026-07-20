module rptr_empty #(
    parameter N          = 4,
    parameter A_EMPTY_TH = 2
) (
    input  wire           rclk,
    input  wire           rrst_n,
    input  wire           r_en,
    input  wire [N:0]     wptr_gray_sync,   // from sync_w2r

    output reg  [N:0]     rptr_gray,        // to sync_r2w
    output wire [N-1:0]   raddr,            // to fifo_mem
    output reg            rempty,
    output reg            arempty
);

   
    //  Binary read pointer
    reg [N:0] rptr;

    //  Memory address
    assign raddr = rptr[N-1:0];

    //  Pointer increment and Gray encoding
    wire ren = r_en & ~rempty;

    //  Combinational look-ahead pointer/gray value -- gated by `ren`,
    //  mirroring the wptr_next/wgray_next fix in wptr_full.v (see that
    //  file for the two-part bug-fix explanation: staleness fix, then
    //  the enable-gating correction found by simulating the first fix).
    wire [N:0] rptr_next  = ren ? (rptr + 1'b1) : rptr;
    wire [N:0] rgray_next = (rptr_next >> 1) ^ rptr_next;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rptr      <= {(N+1){1'b0}};
            rptr_gray <= {(N+1){1'b0}};
        end else begin
            if (ren) begin
                rptr      <= rptr_next;
                rptr_gray <= rgray_next;
            end
        end
    end

    //  Empty condition (Gray domain comparison) -- compares the
    //  look-ahead rgray_next so this register tracks rptr_gray above
    //  in lockstep instead of lagging it by one cycle. Re-evaluated
    //  every cycle (not just on reads) so rempty correctly asserts as
    //  soon as wptr_gray_sync catches up, even with no read pending.
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rempty <= 1'b1;     // FIFO starts empty
        end else begin
            rempty <= (wptr_gray_sync == rgray_next);
        end
    end
    
    //  Almost-empty condition
    integer i;
    reg [N:0] wptr_bin_sync;

    always @(*) begin
        wptr_bin_sync[N] = wptr_gray_sync[N];
        for (i = N-1; i >= 0; i = i - 1)
            wptr_bin_sync[i] = wptr_bin_sync[i+1] ^ wptr_gray_sync[i];
    end

    //  Almost-empty condition. The subtraction is assigned to a sized
    //  N+1-bit intermediate wire FIRST, forcing it to be evaluated in
    //  N+1-bit modular (wraparound) context. Without this, Verilog's
    //  context-based width propagation promotes the subtraction to
    //  match A_EMPTY_TH's unsized (32-bit) parameter width, which
    //  silently breaks the wraparound arithmetic: e.g. 5'd0 - 5'd30
    //  correctly wraps to 2 in 5-bit context, but computed in 32-bit
    //  context gives a huge value instead, since the small operands get
    //  zero-extended BEFORE the subtraction rather than after. This
    //  only shows up once the pointers have wrapped past 2^(N+1) --
    //  caught via simulation after two full fill/drain cycles.
    wire [N:0] empty_diff = wptr_bin_sync - rptr_next;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            // DEF-003 FIX: was arempty <= 1'b0. An empty FIFO (fill=0) is
            // always within the almost-empty threshold by definition
            // (0 <= A_EMPTY_TH for any sane threshold), exactly mirroring
            // why rempty resets to 1 above. Resetting to 0 left arempty
            // reading incorrectly for several cycles after every reset,
            // until empty_diff's combinational recompute caught up.
            // Found via the scoreboard's Phase 2 restructuring -- the
            // prior mis-nested check silently skipped this exact window
            // (read-side checks gated on write activity, and idle/
            // post-reset cycles have no writes), so this was hidden the
            // entire time the old scoreboard structure was in place.
            arempty <= 1'b1;
        end else begin
            arempty <= (empty_diff <= A_EMPTY_TH);
        end
    end

endmodule