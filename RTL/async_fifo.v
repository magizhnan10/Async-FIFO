`timescale 1ns / 1ps

module async_fifo #(
    parameter W          = 8,
    parameter N          = 4,
    parameter A_FULL_TH  = 2,
    parameter A_EMPTY_TH = 2
) (
    // Clocks and reset
    input  wire           wclk,
    input  wire           rclk,
    input  wire           arst_n,

    // Write interface
    input  wire           w_en, 
    input  wire [W-1:0]   wdata,
    output wire           wfull,
    output wire           awfull,

    // Read interface
    input  wire           r_en,
    output wire [W-1:0]   rdata,
    output wire           rempty,
    output wire           arempty
);

    //  Domain-local synchronized resets
    wire wrst_n;
    wire rrst_n;
    
    //  Write domain intermediate signals
    wire [N:0]   wptr_gray;         // Gray write ptr  -> sync_w2r
    wire [N-1:0] waddr;             // write address   -> fifo_mem
    wire         wen;               // qualified w_en  -> fifo_mem
    
    //  Read domain intermediate signals
    wire [N:0]   rptr_gray;         // Gray read ptr   -> sync_r2w
    wire [N-1:0] raddr;             // read address    -> fifo_mem
    
    //  Synchronized pointer crossing signals
    wire [N:0]   wptr_gray_sync;    // wptr_gray synced into rclk
    wire [N:0]   rptr_gray_sync;    // rptr_gray synced into wclk
    
    //  Reset synchronizers
    rst_sync rst_sync_w (
        .clk   (wclk),
        .arst_n(arst_n),
        .rst_n (wrst_n)
    );

    rst_sync rst_sync_r (
        .clk   (rclk),
        .arst_n(arst_n),
        .rst_n (rrst_n)
    );

   
    //  Dual-port memory array
    fifo_mem #(
        .W(W),
        .N(N)
    ) u_fifo_mem (
        .wclk (wclk),
        .wen  (wen),
        .waddr(waddr),
        .wdata(wdata),
        .rclk (rclk),
        .raddr(raddr),
        .rdata(rdata)
    );

    
    //  Write pointer and full flag logic
    wptr_full #(
        .N        (N),
        .A_FULL_TH(A_FULL_TH)
    ) u_wptr_full (
        .wclk         (wclk),
        .wrst_n       (wrst_n),
        .w_en         (w_en),
        .rptr_gray_sync(rptr_gray_sync),
        .wptr_gray    (wptr_gray),
        .waddr        (waddr),
        .wen          (wen),
        .wfull        (wfull),
        .awfull       (awfull)
    );

    //  Read pointer and empty flag logic
    rptr_empty #(
        .N         (N),
        .A_EMPTY_TH(A_EMPTY_TH)
    ) u_rptr_empty (
        .rclk         (rclk),
        .rrst_n       (rrst_n),
        .r_en         (r_en),
        .wptr_gray_sync(wptr_gray_sync),
        .rptr_gray    (rptr_gray),
        .raddr        (raddr),
        .rempty       (rempty),
        .arempty      (arempty)
    );

    
    //  Write-to-read synchronizer    
    sync_2ff #(
        .W(N+1)
    ) sync_w2r (
        .clk  (rclk),
        .rst_n(rrst_n),
        .d    (wptr_gray),
        .q    (wptr_gray_sync)
    );


    //  Read-to-write synchronizer
    sync_2ff #(
        .W(N+1)
    ) sync_r2w (
        .clk  (wclk),
        .rst_n(wrst_n),
        .d    (rptr_gray),
        .q    (rptr_gray_sync)
    );

endmodule