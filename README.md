# Asynchronous Dual-Clock FIFO — Class-Based SystemVerilog Verification Environment
 
A layered, non-UVM SystemVerilog testbench for functional sign-off of a parameterized dual-clock async FIFO with Gray-code pointer CDC synchronization.
 
## Overview
 
This project implements and verifies a configurable dual-clock asynchronous FIFO (parameterized width, depth, and programmable almost-full/almost-empty thresholds), targeting robust functional closure through a hand-built, class-based verification environment — no UVM dependency, built from first principles to reinforce methodology fundamentals.
 
The RTL uses the standard Gray-code pointer CDC scheme: write and read pointers are Gray-encoded, synchronized across clock domains via 2-flop synchronizers, and compared combinationally (with look-ahead) to generate full/empty status flags.
 
## RTL Structure
 
| Module | Responsibility |
|---|---|
| `async_fifo.v` | Top-level integration |
| `wptr_full.v` | Write-pointer logic and full-flag generation |
| `rptr_empty.v` | Read-pointer logic and empty-flag generation |
| `fifo_mem.v` | Dual-port memory array |
| `sync_2ff.v` | 2-flop CDC synchronizer |
| `rst_sync.v` | Asynchronous-assert, synchronous-deassert reset synchronizer |
 
## Verification Architecture
 
A layered, package-based testbench (`fifo_tb_pkg.sv`) containing write/read agents, protocol monitors, a transaction-level scoreboard, and directed + constrained-random test classes — consolidated into a single package to work around XSim compile-order sensitivity for plain SystemVerilog class files.
 
Verification proceeds in phases:
 
1. **SVA** — bind-based assertions layered on top of the RTL (non-invasive, added by type-binding rather than source modification) as a parallel safety net
2. **Scoreboard hardening**
3. **Independent-clock CDC verification**
4. **Reset corner cases**
5. **Constrained-random stimulus and closure**
6. **Functional coverage closure and sign-off**
Current scope is explicitly limited to same-clock-domain configurations, with true independent-clock CDC, formal CDC verification, and gate-level simulation tracked as open follow-on items.
  
## Toolchain
 
- **Primary simulator:** Vivado 2025.2 (XSim)
- **Secondary simulator:** Icarus Verilog, used for fast targeted probing of RTL fixes before Vivado confirmation
- **Languages:** SystemVerilog (testbench, SVA), Verilog (RTL)
## Status
 
Active development. SVA layer is being compiled and stabilized; scoreboard hardening, independent-clock CDC verification, reset corner cases, constrained-random closure, and coverage closure are planned next.
