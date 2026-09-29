# 8051 RTL

Synthesizable SystemVerilog baseline for an MCS-51-compatible microcontroller.
Instruction fetches and external `MOVX` accesses use an AXI4-Lite master.
Internal data RAM and SFRs remain on-chip, as on a classic 8051.

Implemented baseline:

* 8-bit accumulator, DPTR, PC, 128-byte internal RAM, four PSW-selected
  R0--R7 register banks, and core SFRs
* NOP, `INC A`, `CLR A`, `MOV A,#imm`, `MOV direct,#imm`, `MOV A,direct`,
  `MOV direct,A`, `SJMP`, `LJMP`, `MOVX A,@DPTR`, `MOVX @DPTR,A`, and `RETI`
* Timer 0/1 modes 0 (13-bit), 1 (16-bit) and 2 (auto reload), with timer/counter
  and GATE operation; timer interrupts
* INT0/INT1 edge- and level-triggered interrupts, two-level `IP` priorities,
  classic vectors `0003h`, `000Bh`, `0013h`, and `001Bh`
* P0--P3 GPIO SFR banks with quasi-bidirectional pin enables (P0 open drain)
* AXI4-Lite byte-addressed instruction/data master (single outstanding request)

Run the regression after installing Cocotb:

```sh
python -m pip install -r requirements.txt
make test
```

This is deliberately a foundation rather than a claim of full 8051 opcode
coverage. Add opcodes in `rtl/mcs51_core.sv`, retaining the instruction-boundary
interrupt check and bus request handshake.
