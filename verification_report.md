# Multi-Core Cache Repair and Verification Report

## Repairs completed

### L1 controller

- Consolidated L1 registered state into one clocked process with asynchronous reset.
- Removed multiple procedural drivers for `done`, `hit`, `miss`, `write_back`, `fill_pending`, and all pending request fields.
- Added complete combinational defaults for `C_NS`, `lru_id`, and `update_lru`.
- Preserved the L1 FSM state register as a separate, single-owner state process.

### L2 controller

- Consolidated L2 request, snoop, fill, eviction, FIFO, and response state into one clocked process with asynchronous reset.
- Removed multiple procedural drivers for request metadata, pending directory state, snoop/fill flags, memory request flags, eviction data, and `fifo_ptr`.
- Reworked the compare decision temporaries so they are block-level signals with explicit combinational defaults.
- The L2 state machine now progresses correctly through:
  - `L2_IDLE → L2_COMPARE → L2_ALLOCATE → L2_DONE` for memory fills.
  - Remote cross-tile cold fill through the NIC/router path.
  - Correct directory allocation and requester ownership.

### Integrated testbench

- Replaced fixed two-clock request pulses with clock-aware request handshakes. Requests remain asserted through the controller’s first `COMPARE` processing edge and are then released safely.
- Corrected the contradictory final check that expected T0 address `0x01` to be both `EXCLUSIVE` and `MODIFIED`. After the final store, `MODIFIED` is the correct state.
- Added `$fatal` calls to failed final checks so the simulator exits nonzero if a coherence assertion fails.

## Final integrated simulation

Command: Verilator timing simulation with `--assert` and VCD tracing.

Result: **PASS — all 7 coherence checks passed.**

| Check | Result |
|---|---:|
| T0 L1 `0x01` final state is `MODIFIED` | PASS |
| T1 L1 `0x15` is `EXCLUSIVE` | PASS |
| T0 L1 `0x40` is `MODIFIED` | PASS |
| T0 L2 set 1 directory for `0x40` is `DIR_M`, owner T0 | PASS |
| T1 L1 `0x80` is `EXCLUSIVE` after remote fill | PASS |
| T0 L2 set 2 directory for `0x80` is `DIR_E`, owner T1 | PASS |
| T0 L1 `0x01` remains `MODIFIED` after local upgrade | PASS |

The final simulation reaches `$finish` with exit code 0 and produces a VCD covering the complete transaction sequence.

## Standalone tests

- Router testbench `tb_router`: **PASS**, exit code 0, including local, clockwise, counter-clockwise, and multiple-input routing cases.
- Standalone L1 testbench `cache_L1_top`: **PASS**, exit code 0; it completes its scripted load/store/snoop sequence.

## Verilator lint

The final integrated RTL lint completed successfully:

- `MULTIDRIVEN` warnings: **0**
- `LATCH` warnings: **0**
- Verilator lint exit code: **0**

Other nonfunctional style warnings may remain, such as filename/module naming and intentionally empty connections, but the requested procedural-driver and latch classes are resolved.

## Formal verification

A solver-backed bounded proof was run with Yosys, `yosys-smtbmc`, and Z3 for 20 clock steps over the repaired L2 directory transition policy. The formal model covers unconstrained sequences of `GETS` and `GETM` requests from four requester IDs and proves:

- Invalid directory entries cannot advertise valid state or sharers.
- `DIR_E` and `DIR_M` always have exactly one owner sharer.
- `DIR_S` always has a nonzero sharer mask.
- Reset returns the directory to `DIR_I`, invalid, with no sharers.
- GETS/GETM transitions preserve those invariants for all bounded input sequences.

Formal result: **PASSED through step 19 / 20-step bound.**

Important limitation: the current project uses SystemVerilog `interface`/`modport` ports, which the installed Yosys frontend cannot parse directly. Therefore this is a **solver-backed abstraction proof of the L2 directory policy**, not a full formal proof of the interface-heavy RTL implementation. The RTL itself is validated with the integrated simulation, standalone tests, Verilator assertions, and zero-driver/zero-latch lint results.

## Artifacts

- `build/tile_tb_final.log`: final integrated simulation log.
- `build/tile_tb_final.vcd`: final integrated waveform.
- `build/router_tb.log`: standalone router test output.
- `build/l1_tb.log`: standalone L1 test output.
- `build/final_lint.log`: final Verilator lint output.
- `build/formal/smtbmc.log`: bounded formal proof result.
- `formal/l2_directory_formal.sv`: formal directory-policy model.
