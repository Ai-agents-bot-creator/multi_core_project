# Router Design for Bidirectional Ring Network-on-Chip (NoC)
## Design

**Megha R**

M.Sc. Applied Physics (VLSI Specialization)

**Contribution:** RTL Design and Verification of the Router module for the Bidirectional Ring Network-on-Chip (NoC).
## Overview

This repository contains the RTL implementation of the Router used in a Bidirectional Ring Network-on-Chip (NoC). The router is responsible for receiving flits from neighboring routers or the local Network Interface Controller (NIC), determining the appropriate forwarding direction, resolving output contention, and transmitting data efficiently across the network.

The design follows a modular architecture implemented in System Verilog, making it scalable, reusable, and easy to integrate into larger NoC systems.

---

## My Contribution

As part of the NoC project, my responsibilities included:

- Designing the complete router architecture
- Implementing input FIFO buffers
- Developing deterministic routing logic
- Designing the arbitration mechanism
- Implementing the crossbar switch
- Integrating all router modules into a top-level router
- Functional verification through System Verilog testbenches

---

## Router Architecture

The router consists of the following functional blocks:

- Input FIFOs – Buffer incoming flits from all input ports.
- Routing Logic – Determines the forwarding direction based on the destination address.
- Arbiter – Resolves conflicts when multiple inputs request the same output.
- Crossbar Switch – Connects the selected input to the appropriate output port.
- Router Top – Integrates all router components into a complete routing unit.

---

## Features

- Bidirectional Ring NoC support
- Modular System Verilog design
- Three-port communication (Local, Clockwise, Counter-Clockwise)
- Deterministic shortest-path routing
- FIFO-based buffering
- Arbitration for contention resolution
- Crossbar-based switching
- Scalable architecture
- Functional verification using dedicated testbenches


## Verification

The router was functionally verified using System Verilog testbenches covering:

- FIFO operations
- Routing decisions
- Arbitration
- Crossbar functionality
- End-to-end flit forwarding

---

## Technologies Used

- System Verilog
- RTL Design
- Digital Design
- Network-on-Chip (NoC)

---

## Project Context

This router was developed as my contribution to a collaborative academic project on the design and verification of a Bidirectional Ring Network-on-Chip (NoC). It is intended to operate with a Network Interface Controller (NIC) and other routers to enable packet communication between processing elements in a ring topology.
