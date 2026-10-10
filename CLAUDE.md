# VLIW architecture development guide in SystemVerilog

## Build Commands
- Compile SystemVerilog files `make`

## Code Style Guidelines
- SystemVerilog: use snake case for variables

## Architecture
- VLIW with a 128 bit bundle
- The processor has 4 slots, each fixed to a specific functional unit
- Each functional unit has its own opcode, so the opcode for an ALU instruction can be the same for a LSU instruction. Therefore they require their own decoder