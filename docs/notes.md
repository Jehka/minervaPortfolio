# RV32I Pipeline — Design Notes

Stage-by-stage notes written during the build. These cover the key concepts, design decisions, and things that trip people up for each module.

---

## ALU — `alu.sv`

### What an ALU actually is

An ALU is purely **combinational logic** — no clock, no state, no memory. Given inputs A, B, and a control signal (`alu_sel`), it produces a result within one propagation delay. In a pipelined CPU it lives entirely in the EX stage. The pipeline registers on either side make it synchronous from the system's perspective — but the ALU itself is just wires and gates.

The ALU doesn't decide what operation to run — it only executes it. The decision was made back in the ID stage by the control unit and `alu_decoder`. By the time `alu_sel` arrives at the ALU input, the instruction has already been decoded. The ALU is the muscle, not the brain.

### alu_sel encoding

| `alu_sel` | Operation | Notes |
|---|---|---|
| `4'b0000` | ADD | R-type add, loads, stores, AUIPC |
| `4'b0001` | SUB | R-type sub, also used for BEQ |
| `4'b0010` | AND | |
| `4'b0011` | OR | |
| `4'b0100` | XOR | |
| `4'b0101` | SLT | signed less-than |
| `4'b0110` | SLTU | unsigned less-than |
| `4'b0111` | SLL | shift left logical |
| `4'b1000` | SRL | shift right logical |
| `4'b1001` | SRA | shift right arithmetic |
| `4'b1010` | LUI pass-B | passes B through — used for LUI |

`alu_decoder.sv` takes `{funct7[5], funct3, alu_op[1:0]}` and produces this 4-bit select. The ALU itself has no idea what instruction is running.

### Three things to understand

**Why does `SRA` use `$signed(a) >>> b[4:0]` but `SRL` uses `a >> b[4:0]`?**
`>>>` on a signed value preserves the sign bit during shift. `>>` on an unsigned value fills with zeros. The instruction encoding uses `funct7[5]` to distinguish the two — same `funct3`, different `funct7`.

**Why does SUB reuse the ADD hardware with `~b + 1`?**
Two's complement. Negation is bitwise invert plus one. So `A - B = A + (-B) = A + (~B + 1)`. The carry_in of 1 handles the `+1`. Real synthesis tools collapse this into a single adder with a subtract mode.

**Why is `b[4:0]` used for shifts instead of all 32 bits?**
RV32I only has 32 registers, so the maximum meaningful shift is 31 bits. The spec says only the low 5 bits are used. Using all 32 bits could allow a shift of `0x80000000` which is meaningless.

### SLT vs SLTU — the interview trap

`0xFFFFFFFF` vs `0x00000001`:
- SLT returns 1 — because −1 is less than 1 signed
- SLTU returns 0 — because 4,294,967,295 is not less than 1 unsigned

If both return the same value, you're missing the `$signed()` cast on SLT.

---

## Register file — `regfile.sv`

### Async reads vs sync write

| Port | Clocked? | Why |
|---|---|---|
| Read port 1 (rs1) | No — combinational | ID stage needs the value this cycle |
| Read port 2 (rs2) | No — combinational | Same reason |
| Write port (rd) | Yes — on posedge clk | WB stage writes at end of cycle |

If reads were synchronous, you'd need an extra pipeline stage just to get register data out. Async reads let ID and WB happen in the same cycle.

### Write-first forwarding

When WB writes to `rd` at the same time ID reads that same register, the register file returns the new write data immediately — before the clock edge. This is write-first behavior.

Priority chain on read ports:
1. x0 check — always return 0
2. Write-first forwarding — if `we && rd == rs1`, return `wd`
3. Array read — normal case

If you put the array read first you'll get stale data on a same-cycle collision.

### x0 hardwired to zero

Enforce on the **read side**, not the write side. Blocking the write to x0 is fine but the critical thing is the read port returning zero when `rs1 == 0`. If you only block the write, a simulation that pre-initializes `regs[0]` to something nonzero would still break.

---

## Immediate generator — `imm_gen.sv`

### The 5 immediate formats

| Format | Used by | Bits scrambled? |
|---|---|---|
| I-type | ADDI, LW, JALR | No — bits contiguous |
| S-type | SW, SH, SB | Yes — rd field reused for imm[4:0] |
| B-type | BEQ, BNE, BLT | Yes — bit 0 always 0, bits scattered |
| U-type | LUI, AUIPC | No — upper 20 bits, lower 12 zeroed |
| J-type | JAL | Yes — most scrambled of all |

### Why the bits are scrambled

The hardware keeps `rs1` at `[19:15]`, `rs2` at `[24:20]`, and `funct3` at `[14:12]` fixed across all formats so the register file can be read before the instruction is fully decoded. The immediate bits fill whatever's left over.

The sign bit `instr[31]` always maps to the MSB of the immediate — sign extension is always just replicate `instr[31]`.

### B-type bit extraction

```
imm[12]   = instr[31]
imm[11]   = instr[7]     ← the odd one — bit position vacated by rd field
imm[10:5] = instr[30:25]
imm[4:1]  = instr[11:8]
imm[0]    = 0            ← always — branches are 2-byte aligned
```

### J-type bit extraction

```
imm[20]    = instr[31]
imm[19:12] = instr[19:12]  ← contiguous, not scrambled
imm[11]    = instr[20]
imm[10:1]  = instr[30:21]
imm[0]     = 0             ← always — jumps are 2-byte aligned
```

### Pattern to remember

Bit 31 is always the sign bit. `imm[0]` is always 0 for B and J types. The scrambling never touches rs1/rs2/rd positions.

---

## ALU decoder — `alu_decoder.sv`

### Two-level decode

```
opcode → alu_op[1:0]                       (main control — coarse)
{alu_op, funct3, funct7[5]} → alu_sel[3:0] (alu_decoder — fine)
```

| `alu_op` | Meaning | Instructions |
|---|---|---|
| `2'b00` | Always ADD | Loads, stores, AUIPC |
| `2'b01` | Always SUB | Branches |
| `2'b10` | Look at funct3/funct7 | R-type, I-type ALU ops |
| `2'b11` | Pass B | LUI |

`alu_op=2'b10` is the interesting case — every R-type and I-type ALU instruction goes through here, and `funct7[5]` is what distinguishes ADD from SUB, SRL from SRA.

### The ADD/SUB disambiguation

```systemverilog
// SUB only if R-type (op_bit5=1) AND funct7[5]=1
(funct7_5 & op_bit5) ? ALU_SUB : ALU_ADD
```

`instr[5]` is 1 for R-type opcodes and 0 for I-type opcodes. For `ADDI x1, x2, -1`, the immediate is all 1s — so `funct7_5` (which is `instr[30]`) will be 1. Without `op_bit5` gating it, `alu_decoder` would decode `ADDI` as `SUB`. Silent bug — no error, wrong answer.

### funct7[5] works the same for I-type shifts

The RV32I spec deliberately reserved `instr[30]` as the arithmetic bit for both R-type and I-type shift instructions. `SLLI` encodes as `funct7=0000000`, `SRAI` encodes as `funct7=0100000` — same bit position, same meaning. No special case needed.

---

## IF stage — `if_stage.sv`

### What IF does each cycle

1. Drives the PC to instruction memory as the read address
2. Computes PC+4 — next sequential instruction address
3. Selects next PC — either PC+4 or branch target

The PC is the only register in IF stage. Everything else — instruction memory, the adder, the mux — is combinational. The pipeline register (IF/ID) lives in the top-level wiring.

### PC indexing

```systemverilog
assign instr = imem[pc_reg[11:2]];
```

The PC is a byte address. Instructions are 4 bytes wide — consecutive instructions are at addresses 0, 4, 8, 12. Bits [1:0] are always zero (word-aligned). Bits [11:2] give the word index into a 1024-entry array. Using `[9:0]` would treat the address as a word address already and jump by 4 instructions per cycle.

### Stall behavior

When the hazard unit asserts `pc_write=0`, the PC must not update. A stall means freeze IF and ID in place — PC holds its value, IF/ID register holds its value. The instruction in EX gets a NOP bubble inserted.

Active-high enable (`pc_write=1` normally, drops to 0 on stall) is easier to read than active-low stall.

### Reset vector

On reset, PC goes to `32'h0000_0000`. Program loads at address 0.

---

## ID stage — `id_stage.sv`

### What ID does

1. Decodes the instruction — reads opcode, funct3, funct7, rs1, rs2, rd
2. Reads the register file — two async reads simultaneously
3. Sign-extends the immediate — calls imm_gen
4. Generates control signals — combinational block on opcode

ID is the only stage that looks at the full instruction. Every stage after it operates purely on control signals and data values — they never see the instruction word again.

### Control signals

| Signal | Width | Meaning |
|---|---|---|
| `reg_write` | 1 | WB stage writes to rd |
| `mem_to_reg` | 1 | WB mux: 0=ALU result, 1=memory data |
| `mem_read` | 1 | DMEM read enable |
| `mem_write` | 1 | DMEM write enable |
| `branch` | 1 | Instruction is a branch |
| `alu_src` | 1 | ALU B input: 0=rs2, 1=immediate |
| `alu_op` | 2 | Coarse ALU operation select |
| `jump` | 1 | JAL or JALR |

These signals travel in the pipeline registers alongside the data. By the time they reach MEM or WB stage, the instruction is long gone.

### Opcode → control signal table

| Instruction | `reg_write` | `mem_to_reg` | `mem_read` | `mem_write` | `branch` | `alu_src` | `alu_op` | `jump` |
|---|---|---|---|---|---|---|---|---|
| R-type | 1 | 0 | 0 | 0 | 0 | 0 | 10 | 0 |
| I-ALU | 1 | 0 | 0 | 0 | 0 | 1 | 10 | 0 |
| Load | 1 | 1 | 1 | 0 | 0 | 1 | 00 | 0 |
| Store | 0 | 0 | 0 | 1 | 0 | 1 | 00 | 0 |
| Branch | 0 | 0 | 0 | 0 | 1 | 0 | 01 | 0 |
| LUI | 1 | 0 | 0 | 0 | 0 | 1 | 11 | 0 |
| AUIPC | 1 | 0 | 0 | 0 | 0 | 1 | 00 | 0 |
| JAL | 1 | 0 | 0 | 0 | 0 | 0 | 00 | 1 |
| JALR | 1 | 0 | 0 | 0 | 0 | 1 | 00 | 1 |

### Defaults before the case statement

`always_comb` with no defaults on every branch infers latches. Setting everything to 0 at the top means every unspecified signal is safely 0, and synthesis sees a clean combinational block with no latches.

### WB write into regfile from ID

The regfile sits in ID stage but its write port is driven by WB stage signals. WB writes and ID reads happen in the same cycle — the regfile returns the new value immediately if addresses match (write-first).

### AUIPC vs LUI

AUIPC uses `alu_op=2'b00` (ADD) because it computes `PC + immediate`. LUI uses `alu_op=2'b11` (pass B) because it just loads the immediate into rd — no addition needed.

---

## EX stage — `ex_stage.sv`

### Four jobs

1. Selects ALU operands — forwarding muxes override register file values with fresher data
2. Runs the ALU — instantiates `alu.sv` and `alu_decoder.sv`
3. Computes branch target — `PC + imm` via a separate adder
4. Resolves branch decision — funct3 and ALU flags decide if branch is taken

### Forwarding mux priority

```
ForwardA/B = 2'b10  →  EX/MEM.alu_result  (newest, highest priority)
ForwardA/B = 2'b01  →  MEM/WB.wb_data
ForwardA/B = 2'b00  →  register file output (no hazard)
```

The else-if in the forwarding unit matters. If both EX/MEM and MEM/WB write to the same rd, EX/MEM wins — it's newer data.

### Why rs2_out bypasses the ALU B mux

For store instructions, the ALU computes the memory address (`rs1 + imm`) — `alu_src=1` so the ALU B input is the immediate, not `rs2`. But you still need the forwarded `rs2` value to write to memory. `rs2_out` carries it forward in the EX/MEM register alongside `alu_result`.

### Branch resolution — funct3 table

| `funct3` | Instruction | Condition |
|---|---|---|
| `3'b000` | BEQ | `zero == 1` |
| `3'b001` | BNE | `zero == 0` |
| `3'b100` | BLT | `result[31] ^ overflow` |
| `3'b101` | BGE | `~(result[31] ^ overflow)` |
| `3'b110` | BLTU | unsigned compare |
| `3'b111` | BGEU | unsigned compare |

All branch comparisons reduce to subtraction. BEQ checks `zero`, BNE checks `~zero`, BLT checks the sign bit of the result. The ALU always subtracts — the EX stage interprets the flags.

### BLT/BGE need overflow flag

Signed subtraction can overflow. `result[31] XOR overflow` gives the true sign of the subtraction regardless of overflow:
- No overflow → `result[31]` is the true sign
- Overflow → `~result[31]` is the true sign

This is why the ALU exports the overflow flag.

### JALR clears bit 0

```systemverilog
branch_target = {alu_result[31:1], 1'b0};  // JALR
```

The RISC-V spec says JALR must set the LSB of the computed address to 0. This ensures the target is always 2-byte aligned even if `rs1 + imm` is odd. JAL and branches don't need this because `imm[0]` is always 0 from imm_gen.

### Branch target is a separate adder

The ALU is busy computing `rs1 - rs2` for the branch comparison. A separate adder computes `PC + imm` for the target. These cannot share the same hardware in a single-cycle EX stage.

---

## MEM stage — `mem_stage.sv`

### Byte enables

| `funct3` | Instruction | Operation |
|---|---|---|
| `3'b000` | LB/SB | 1 byte |
| `3'b001` | LH/SH | 2 bytes |
| `3'b010` | LW/SW | 4 bytes |
| `3'b100` | LBU | 1 byte unsigned |
| `3'b101` | LHU | 2 bytes unsigned |

Byte and halfword loads need sign extension on the way out. LBU/LHU are unsigned — zero extend instead. The address low bits `[1:0]` tell you which byte lane to read.

### Address indexing

```systemverilog
raw_word = dmem[alu_result[11:2]];
```

Same principle as IMEM — byte address divided by 4 gives the word index. Bits [1:0] select the byte lane within the word.

### Harvard architecture

IMEM and DMEM are completely separate memories. The bubble sort array must be initialized in `dmem`, not `imem`. `lw/sw` instructions go to `dmem`. `imem` is instruction fetch only.

---

## WB stage — `wb_stage.sv`

WB is almost just wires. One mux selects between ALU result and memory load data:

```systemverilog
assign wb_data = mem_to_reg ? mem_data : alu_result;
```

The output goes back to the register file write port in `id_stage` and to the forwarding unit. `mem_to_reg=0` for all ALU instructions, `mem_to_reg=1` for loads.

---

## Hazard detection unit — `hazard_unit.sv`

### Two independent hazard types

**Load-use hazard — stall:**
```
if (ID_EX.mem_read &&
   (ID_EX.rd == IF_ID.rs1 || ID_EX.rd == IF_ID.rs2))
    → pc_write=0, if_id_write=0, id_ex_flush=1
```

One bubble required. Forwarding cannot help here — the load data isn't available until the end of MEM stage, which is too late for EX in the same cycle.

**Branch flush:**
```
if (branch_taken)
    → if_id_flush=1
```

### Stall vs flush — different operations

A **stall** freezes the front of the pipeline and inserts a bubble behind the stalled instruction. The PC holds, IF/ID holds, a NOP propagates into ID/EX.

A **flush** discards instructions that entered the pipeline after a taken branch — they're from the wrong path. IF/ID and ID/EX are overwritten with NOPs.

### Active-high enable convention

`pc_write=1` normally, drops to 0 on stall. This is easier to read than active-low stall signals throughout the pipeline.

---

## Forwarding unit — `forwarding_unit.sv`

### All four forwarding cases

```
// EX-EX forward to A (highest priority)
if (EX_MEM.reg_write && EX_MEM.rd != 0
    && EX_MEM.rd == ID_EX.rs1)
    ForwardA = 2'b10

// MEM-WB forward to A
else if (MEM_WB.reg_write && MEM_WB.rd != 0
    && MEM_WB.rd == ID_EX.rs1)
    ForwardA = 2'b01

else
    ForwardA = 2'b00  // no forwarding

// same logic for ForwardB using ID_EX.rs2
```

### Why the else-if matters

If both EX/MEM and MEM/WB write to the same `rd`, EX/MEM wins — it's newer. Without the else, MEM/WB could clobber the fresher value from EX/MEM.

### Why rd != 0 check

Forwarding to rs1 or rs2 when `rd=0` would forward a value into x0, which must always be 0. The check prevents this.

---

## Top level — `riscv_cpu.sv`

### Pipeline registers

The pipeline registers live in `riscv_cpu.sv`, not inside the stage modules. Each is an `always_ff` block that:
- Resets to 0 / NOP on `rst`
- Flushes to NOP when flush signal asserted
- Holds value when stall asserted (IF/ID only)
- Otherwise latches stage outputs on posedge clk

### NOP encoding

```systemverilog
32'h0000_0013  // ADDI x0, x0, 0 — the canonical RV32I NOP
```

This is used to fill pipeline registers on flush and stall. All control signals decode to 0, rd=0, no side effects.

### debug_out

```systemverilog
assign debug_out = u_id.u_regfile.regs[10];
```

Exposes register `a0` directly for FPGA observation via AXI GPIO. After bubble sort, `a0` holds the sorted minimum.

---

## FPGA bring-up notes

### Zynq PS UART — no custom TX needed

Rather than implementing a UART TX in PL, `debug_out` is wired via AXI GPIO to the Zynq PS. The PS reads it via a Vitis bare-metal C application and transmits over its hardened UART peripheral. Same infrastructure as P1.

### Vivado 2025.1 — known issue

`$readmemh` works in simulation but the file path can fail at synthesis if the hex file isn't added to sources explicitly. Fix: hardcode the program directly in `if_stage.sv` using `initial begin imem[N] = 32'h...` — no external file dependency.

### IMEM vs DMEM initialization

The bubble sort array must be in `dmem` (initialized in `mem_stage.sv`). `lw/sw` go to data memory. If you initialize the array in `imem` by mistake, the CPU fetches it as instructions and crashes. The array lives at word address `0x80` = byte address `0x200`.

### Simulation before FPGA — always

Run behavioral simulation first. 500 cycles is enough for bubble sort on 10 elements. Confirm `debug_out = 0` in the Tcl console before touching hardware.

---

## Reference

- Patterson & Hennessy — *Computer Organization and Design RISC-V Edition*, Chapter 4 (pipeline), Appendix A (RV32I ISA)
- Harris & Harris — *Digital Design and Computer Architecture RISC-V Edition*, Chapter 7 (microarchitecture)
- RISC-V ISA Specification — [riscv.org/specifications](https://riscv.org/specifications)
- Venus RISC-V simulator — [venus.cs61c.org](https://venus.cs61c.org)
