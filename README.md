# Tiled Multi-Core Cache-Coherence RTL

This repository implements and verifies a two-tile multicore cache-coherence prototype in SystemVerilog. Each tile has a private two-way L1 cache, a four-way banked L2 cache with directory metadata, a mux, a packet NIC, a memory tap, and a bidirectional-ring router. The L2 banks are physically distributed but logically shared; the home bank is selected directly from the address.

## Current status

The repository has been cleaned and repaired.

| Check | Result |
|---|---:|
| Integrated two-tile coherence regression | **7/7 PASS** |
| Standalone router regression | **PASS** |
| Standalone L1 regression | **PASS** |
| Verilator lint exit code | **0** |
| `MULTIDRIVEN` warnings | **0** |
| `LATCH` warnings | **0** |
| Bounded L2 directory-policy proof | **PASS**, 20 steps with Z3 |

The exact verification boundary is documented in [`Project_Report.md`](Project_Report.md): the RTL is simulated and linted directly, while the current formal proof is an abstraction because the installed Yosys frontend cannot parse the project’s interface/modport declarations directly.

## Read the documentation

| Document | Use it for |
|---|---|
| [`Project_Report.md`](Project_Report.md) | Full technical report, architecture, protocols, diagrams, simulations, formal result, limitations, and reproducibility |
| [`Changes.md`](Changes.md) | Original flaws, cleanup decisions, repair mechanisms, justification, and evidence |
| [`Cheat_sheet.md`](Cheat_sheet.md) | Start-from-zero project guide, address map, state/message quick reference, debug flow, and commands |
| [`verification_report.md`](verification_report.md) | Concise verification summary |
| [`architecture.png`](architecture.png) | Main tile/interconnect architecture image |
| [`verification_evidence.svg`](verification_evidence.svg) | Embedded-style simulation and formal evidence panel |

## Architecture at a glance

```text
Tile 0: Core → L1 → Mux → L2 bank 0 → NIC → Router 0 ┐
                                                       ├─ bidirectional ring
Tile 1: Core → L1 → Mux → L2 bank 1 → NIC → Router 1 ┘
                         │
                       Memory tap / packetized memory service
```

![Architecture](architecture.png)

The structural source files are [`architecture.mmd`](architecture.mmd), [`module_hierarchy.mmd`](module_hierarchy.mmd), [`transaction_sequence.mmd`](transaction_sequence.mmd), and [`address_mapping.mmd`](address_mapping.mmd). Rendered assets are kept beside the sources.

## Address map

For an 8-bit address:

```text
L1: Addr[7:4] = tag, Addr[3:2] = set
L2: Addr[7:6] = set, Addr[5:4] = home bank, Addr[3:0] = tag
```

The current prototype uses 8-bit data and four sets. L1 has two ways; each L2 bank has four ways.

## Source map

- `tile.sv` — complete tile integration.
- `Tile_2tb.sv` — final two-tile testbench, stimulus, monitors, dumps, and fatal final checks.
- `cache_controller.sv` — L1 controller.
- `cache_storage.sv`, `cache_lru.sv` — L1 storage and replacement.
- `L2_cache_controller.sv` — L2 directory controller.
- `L2_cache_storage.sv` — L2 storage.
- `cache_interface.sv`, `L2_cache_interface.sv` — SystemVerilog interfaces/modports.
- `L1_cache_mem.sv`, `l2_cache_pkg.sv` — package types, state enums, and messages.
- `Mux.sv`, `NIC.sv`, `Router.sv`, `mem.sv` — tile transport and memory endpoint.
- `formal/l2_directory_formal.sv` — bounded formal abstraction of directory invariants.

## Reproduce the integrated simulation

The commands below assume Verilator is installed:

```bash
mkdir -p build/final_obj
verilator --binary --timing --trace --assert --Wno-fatal \
  --language 1800-2012 --top-module tile_tb_stable \
  L1_cache_mem.sv l2_cache_pkg.sv cache_interface.sv cache_controller.sv \
  cache_storage.sv cache_lru.sv L2_cache_interface.sv L2_cache_controller.sv \
  L2_cache_storage.sv NIC.sv Router.sv Mux_interface.sv Mux.sv mem.sv tile.sv Tile_2tb.sv \
  -Mdir build/final_obj -o tile_tb_final
build/final_obj/tile_tb_final
```

Expected output contains seven `PASS:` lines and ends with `$finish`.

## Reproduce lint

```bash
verilator --lint-only --timing --language 1800-2012 --Wall --Wno-fatal \
  --top-module tile_tb_stable \
  L1_cache_mem.sv l2_cache_pkg.sv cache_interface.sv cache_controller.sv \
  cache_storage.sv cache_lru.sv L2_cache_interface.sv L2_cache_controller.sv \
  L2_cache_storage.sv NIC.sv Router.sv Mux_interface.sv Mux.sv mem.sv tile.sv Tile_2tb.sv
```

## Reproduce the bounded formal check

```bash
yosys -ql build/formal/yosys.log build/formal/l2_directory.ys
yosys-smtbmc -s z3 -t 20 build/formal/l2_directory.smt2
```

Expected result: `Status: PASSED`.

## Verification artifacts

- [`build/tile_tb_final.log`](build/tile_tb_final.log) — final integrated run.
- [`build/tile_tb_final.vcd`](build/tile_tb_final.vcd) — final waveform.
- [`build/router_tb.log`](build/router_tb.log) — router regression.
- [`build/l1_tb.log`](build/l1_tb.log) — L1 regression.
- [`build/final_lint.log`](build/final_lint.log) — final lint output.
- [`build/formal/smtbmc.log`](build/formal/smtbmc.log) — formal proof output.

## Scope and limitations

This is an educational two-tile RTL prototype. It is not yet a production cache controller or a fully synthesized FPGA deliverable. Current limitations include simplified ready/valid behavior, small 8-bit data/line modeling, two-tile sizing, remaining nonfatal style warnings, and the lack of direct full-RTL formalization through the installed Yosys interface parser. Future work is listed in [`Project_Report.md`](Project_Report.md).
