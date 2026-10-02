# Changes, Original Flaws, and Repair Rationale

This file records what changed during repository cleanup and controller repair. It is a defect-to-solution record: what was wrong, where it occurred, why it mattered, how it was corrected, and what evidence supports the correction.

## 1. Baseline and cleanup decisions

The original checkout contained competing implementations and experimental files with overlapping names. The cleanup established one canonical source for each architectural function and removed redundant variants from the deliverable.

| Original redundancy | Canonical result | Reason |
|---|---|---|
| `NIC.sv` versus `nic_lowercase.sv` | `NIC.sv` | One canonical NIC module and packet format |
| `Router.sv` versus `router_lowercase.sv` and `gitrouter.sv` | `Router.sv` | Avoid conflicting router definitions and ambiguous top modules |
| `Mux.sv` versus `mux_v1.sv` | `Mux.sv` | One canonical mux implementation |
| `tbmini router.sv` | `Router.sv` testbench boundary | Keep router regression associated with the canonical router source |
| Repeated package declarations | `L1_cache_mem.sv`, `l2_cache_pkg.sv` | One package owner per type namespace |
| Generated object directories and temporary backups | Excluded from final ZIP | Keep the repository source-focused and reproducible |

The cleanup also normalized the design around the current packetized memory path. L2 memory traffic uses `NMSG_MEM_REQ` and `NMSG_MEM_DATA` through the NIC rather than stale standalone memory ports.

## 2. Defect summary

| ID | Area | Original defect | Impact | Resolution |
|---|---|---|---|---|
| F-01 | L1 sequential logic | Registers were written from more than one procedural block | `MULTIDRIVEN` warnings and ambiguous ownership | Consolidated L1 state/data/output registers into one reset-aware clocked process |
| F-02 | L2 sequential logic | Request, snoop, fill, FIFO, and eviction registers had multiple owners | Race-prone behavior and `MULTIDRIVEN` warnings | Consolidated L2 registered state into one clocked process |
| F-03 | L1 next-state logic | `C_NS` was incompletely assigned | Inferred latch and stale state retention | Defaulted `C_NS = C_PS` and retained explicit state transitions |
| F-04 | L1 output combinational logic | `lru_id` and `update_lru` were not assigned on all paths | Inferred latches on replacement-control outputs | Added deterministic combinational defaults |
| F-05 | L2 compare progression | Request capture and compare decision were not separated reliably | Transactions could stall before fill/response processing | Added `compare_settled` plus explicit wait/finish decisions |
| F-06 | L2 temporaries | Automatic block-local compare variables were latch-prone in lint | Unclear synthesis intent and latch warnings | Declared compare signals at module scope with defaults |
| F-07 | L2 interface | Interface referenced memory signals that no longer existed | Compile errors and architectural ambiguity | Removed obsolete ports and documented packetized memory traffic |
| F-08 | Testbench handshake | Requests were released using fixed timing | A request could disappear before the controller accepted it | Hold requests through `COMPARE`, then release after a clock edge and `IDLE` |
| F-09 | Testbench expectation | T0 `0x01` was checked as both `EXCLUSIVE` and `MODIFIED` after a later store | Correct behavior was reported as a failure | Expect `MODIFIED` after the final store |
| F-10 | Testbench enforcement | Failed checks only printed text and still allowed exit 0 | Regressions could look successful to automation | Added `$fatal` to each failed final assertion |
| F-11 | Verification scope | Existing checks were mostly final-state checks | A transaction could hang or be mis-sampled without a clear failure | Added state monitors, ring-traffic prints, clock-aware tasks, VCD tracing, lint, and formal policy checks |
| F-12 | Documentation | Multiple README-like files and no single repair record | New users could not determine canonical behavior | Added `README.md`, `Project_Report.md`, `Changes.md`, and `Cheat_sheet.md` |

## 3. L1 multiple-driver repair

### Original condition

`cache_controller.sv` contained an asynchronous-reset/state process and another clocked process that also assigned operational registers. Signals such as `hit`, `miss`, `done`, `write_back`, `fill_pending`, `pending_state`, `pending_set`, `pending_way`, and pending request fields were therefore seen from multiple procedural drivers. Some output fields were also assigned from reset and operational blocks without a single clear owner.

### Why this was dangerous

A register must have one unambiguous sequential owner. Multiple drivers can simulate differently between tools, create non-synthesizable behavior, or produce priority semantics that are not obvious from the source. In a coherence controller, a stale `fill_pending` or `done` bit can change the next state and either lose a response or retire a request too early.

### Repair

The state register `C_PS` remains in a dedicated reset-aware process. All other L1 sequential state and interface outputs are initialized and updated in one clocked process. The operational process now has a clear reset branch and a normal-operation branch. Combinational decision logic does not own those registers.

### Why the repair is better

The ownership model is now reviewable: one process owns the FSM state and one process owns the L1 transaction registers. This is easier to synthesize, easier to lint, easier to formalize, and less sensitive to simulator scheduling. The final integrated lint reports zero `MULTIDRIVEN` diagnostics.

## 4. L2 multiple-driver repair

### Original condition

`L2_cache_controller.sv` distributed assignments to request metadata, pending directory state, snoop flags, memory request flags, eviction data, response fields, and FIFO pointers across incompatible procedural contexts. The L2 controller also had temporary compare variables inside combinational blocks that Verilator treated as latch-prone.

### Why this was dangerous

The L2 is the serialization point for each home block. If `req_addr`, `req_src`, `pending_owner`, or `pending_ack` is written by more than one process, a response can be associated with the wrong requester or a directory update can occur before all invalidation acknowledgements arrive. A `fifo_ptr` with multiple ownership is especially dangerous because packet order and packet identity can be corrupted.

### Repair

All L2 registered state is initialized in one reset-aware sequential process and updated in that same process. The L2 FSM state register remains separately owned. Compare decision signals are declared explicitly, defaulted in `always_comb`, and consumed by next-state logic. The design now has a visible distinction between combinational decision, sequential state capture, and storage write enable.

### Why the repair is better

The L2 controller now has a deterministic temporal contract: capture a request, spend a clock settling the lookup, calculate a decision, issue any required packet, wait in the appropriate transient state, and retire only after the matching response. The repair addresses the behavior behind the warning instead of suppressing the warning.

## 5. Missing L2 compare/fill progression

### Original condition

A request could enter L2 compare while the cache lookup and request capture were still changing. The state machine did not reliably distinguish “compare has just been entered” from “the compare result is stable and can drive allocation or completion.” This caused the corrected testbench to stall in long-running simulations and exposed failures in snoop/fill progression.

### Repair mechanism

`compare_settled` is registered. It becomes true after the controller has spent the required clock in `L2_COMPARE`. The combinational logic then calculates:

- whether a matching way exists;
- which way matched;
- which requester should be considered the owner;
- whether the directory action is hit, forward, upgrade/invalidate, or miss;
- whether the FSM should finish or enter allocation.

The `L2_ALLOCATE` completion logic separately checks memory data, forwarded data, and invalidation acknowledgements. The state machine uses `compare_will_wait`, `compare_will_finish`, `allocate_will_finish`, and `snoop_will_finish` rather than relying on an accidental same-edge value.

### Observed result

The two-tile simulation now reaches all scripted transaction completions. The cross-tile `0x80` load reaches the memory-fill path, returns through the NIC/ring, allocates T1’s L1 line as `EXCLUSIVE`, and records T1 as the owner in T0’s directory.

## 6. Testbench repairs

The original fixed-duration request pulses were not an adequate handshake. A controller can only accept a request if its state machine sees the instruction at the relevant clock edge. The repaired tasks assert an instruction on a clock boundary, wait until the DUT reaches `COMPARE`, wait through a processing edge, release the instruction, and then wait for `IDLE`.

The testbench now also produces a VCD, prints controller states, prints ring traffic, dumps all L1/L2 entries at checkpoints, and converts failed final checks into fatal simulation errors. This improves both correctness and diagnosability.

The contradictory check was a testbench defect rather than an RTL defect. T0 first loads `0x01`, then later stores `0x01`. An exclusive clean copy is expected after the load, but a modified copy is expected after the store. The final checks execute after all transactions, so expecting `EXCLUSIVE` at that point was incorrect. The check was corrected to `MODIFIED`.

## 7. Interface and package repair

The project originally contained stale interface references for a separate memory port even though the implemented architecture routed memory over the NIC. The final `L2_cache_interface.sv` now exposes local L1 traffic, NIC request/response traffic, and L2 storage control only. The source comments state the design choice so a future maintainer does not reintroduce removed ports accidentally.

Packages were consolidated so L1 types are defined by `L1_cache_mem.sv` and L2 types by `l2_cache_pkg.sv`. This removes repeated declarations and avoids a different definition being selected depending on compile order.

## 8. Verification evidence for the changes

| Evidence | Result |
|---|---|
| Integrated Verilator lint | Exit 0 |
| `MULTIDRIVEN` diagnostics | 0 |
| `LATCH` diagnostics | 0 |
| Integrated two-tile coherence checks | 7/7 PASS |
| Router standalone testbench | PASS, `ROUTER TEST COMPLETED` |
| L1 standalone testbench | PASS, reaches `$finish` |
| Bounded L2 policy proof | PASS, Z3 steps 0–19 |
| Integrated VCD | Generated at `build/tile_tb_final.vcd` |

The exact logs are retained in `build/`. The visual summary is [`verification_evidence.svg`](verification_evidence.svg), while the reproducible technical explanation is [`Project_Report.md`](Project_Report.md).

## 9. Remaining warnings and why they were not silently hidden

The final lint is clean for the two requested structural defect classes, but it still reports nonfatal style warnings. These include incomplete case coverage, blocking assignments in some sequential/testbench contexts, nonblocking assignments in older combinational L1 decision code, and a reset-net mixed-use warning in the testbench. They are not claimed as fixed by this repair because changing them would be a separate behavioral refactor requiring another regression pass.

The correct next step is to normalize combinational assignments to blocking assignments, add explicit `default` branches where appropriate, separate testbench reset semantics from DUT reset semantics, and rerun synthesis-oriented lint. Suppressing the warnings would be inferior to documenting them.

## 10. Formal-proof boundary

Direct Yosys parsing of the actual interface-heavy RTL fails at the SystemVerilog interface declaration. The repository therefore includes a solver-backed abstraction model in `formal/l2_directory_formal.sv`. It models the repaired directory policy with unconstrained request sequences and proves the stable directory invariants for 20 bounded steps.

This is stronger than a prose argument but narrower than a full RTL proof. The distinction is intentional. The simulation and lint results apply to the actual RTL; the formal result applies to the extracted directory policy model. Future work should flatten the interfaces or use a SystemVerilog formal tool that supports the current interface/modport structure, then connect the same assertions to the real controllers.

## 11. Files changed or added

- Repaired: `cache_controller.sv`.
- Repaired: `L2_cache_controller.sv`.
- Repaired: `Tile_2tb.sv`.
- Normalized: `L2_cache_interface.sv`, package organization, canonical module set.
- Added: `Project_Report.md`, `Changes.md`, `Cheat_sheet.md`.
- Updated: `README.md`.
- Added diagrams: `module_hierarchy.mmd`, `transaction_sequence.mmd`, `address_mapping.mmd` and rendered assets.
- Added evidence visuals: `verification_evidence.svg`, `waveform_timeline.svg`.
- Added formal model: `formal/l2_directory_formal.sv`.
