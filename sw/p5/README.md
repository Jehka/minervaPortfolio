# P5 fault-injection campaign

| File | What it is |
|---|---|
| `p5_campaign.c` | Vitis app. Exhaustive single-bit sweeps over the workload's 33 instruction words and 8 input data words. 1312 runs. |
| `p5_imm_probe.c` | Diagnostic app: sweeps the immediate field of two instructions with dmem 0x200/0x400 poisoned. Used to rule out an immediate-decode bug. |
| `workload.S` | Source of the CPU image embedded in both apps. Rebuild instructions in its header. |
| `w.bin` | Assembled image. Input to `model.py`. |
| `model.py` | Reference model: RV32I ISS plus the P4 memory system (write-back cache, uncached fetch, crossbar map). Writes `predicted.csv`. |
| `compare.py` | Diffs a UART log against `predicted.csv`. |
| `campaign_run.log` | The final campaign run. |

## Result

imem, 1056 injections: SDC 517 (49.0%), no-result 315 (29.8%), masked 224 (21.2%).
dmem, 256 injections: SDC 256 (100%). INJFAIL 0, golden runs clean before and after.

Model vs hardware: 1256 of 1256 classified injections agree. The other 56 are the
model's UNCERTAIN class -- a known opcode with an undefined funct3/funct7, where
`alu_decoder` behaviour was not modelled.

## Design behaviours the campaign characterised

- Unknown opcodes execute as NOPs (`id_stage.sv` default). No illegal-instruction
  trap exists, so there is no "detected" class.
- An unmapped address hangs the master: the crossbar's decode returns -1 and no
  DECERR response is generated. Recovered by the per-run reset.
- Word loads ignore `addr[1:0]` rather than trapping a misaligned access.
- Bits 0-6 (opcode) are the most lethal. Bit 31 (immediate sign) is the worst
  single bit at 27/33 no-result. Bit 14 (funct3) is the most benign at 21/33 masked.
- Faults in the final spin instruction are 32/32 masked: after the last
  architectural store nothing can change the outcome.

## Two bugs this work found

1. **Reset domain split.** The CPU-side AXI BRAM controllers sat on the PS
   peripheral reset while the CPU, crossbar and FI master sat on the GPIO reset.
   A hold landing mid-fetch deadlocked the controller against the crossbar,
   roughly 1 run in 6. Fixed by exporting `fabric_aresetn` from `p4_top`; see
   `scripts/bd_reset_domain_fix.tcl`.
2. **Harness state leak.** Only the output words were cleared between runs, so a
   faulted run's stray stores could let a later run's redirected load read
   valid-looking data. Four rows classified MASKED that should have been SDC.
   Fixed by clearing all of dmem each run.

Never read the FI registers while the CPU hold is asserted. The FI master's slave
port is in that reset domain, and a read there hangs the ARM with no timeout and
no error.
