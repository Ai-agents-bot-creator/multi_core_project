# Network Interface Controller

`NIC.sv` is the canonical NIC implementation. It contains the packet FIFO, transmit/receive controllers, and the shared 32-bit flit pack/unpack format.

## Canonical flit layout

| Bits | Field |
|---|---|
| `[31:30]` | destination tile ID (low 2 bits) |
| `[29:28]` | source tile ID (low 2 bits) |
| `[27:24]` | `l2_nic_msg_t` message type |
| `[23]` | write enable |
| `[22]` | exclusive response flag |
| `[21:14]` | address |
| `[13:6]` | data |
| `[5:0]` | reserved, zero |

The router currently routes using only `[31:30]`; message-type inspection and virtual channels remain future work, not implemented behavior.
