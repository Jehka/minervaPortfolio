# Heterogeneous CDC Arbiter & Timestamp Engine

A production-style FPGA subsystem that arbitrates multiple heterogeneous AXI4-Stream sensor sources, captures deterministic acquisition timestamps, and safely transfers sensor packets across asynchronous clock domains using a formally-safe CDC architecture.

The design targets mixed-signal acquisition pipelines where multiple sensors operate concurrently and data must be transferred into a high-speed processing or DMA domain without introducing timestamp drift, starvation, or clock-domain crossing failures.

---

## Key Features

### Strict Round-Robin Arbitration

The arbiter services multiple sensor channels using a strict round-robin scheduling algorithm.

Unlike fixed-priority arbiters, every requesting source is guaranteed access to the shared output path, preventing starvation and ensuring deterministic bandwidth allocation across channels.

### Hardware Acquisition Timestamping

Each sensor source receives a hardware timestamp captured on the rising edge of its `tvalid` signal.

This ensures timestamps represent the actual acquisition event rather than the later arbitration or transmission time.

### Asynchronous Clock Domain Crossing

Sensor acquisition and system processing often operate on independent clocks.

The design safely transfers packets between clock domains through a Xilinx XPM asynchronous FIFO utilizing Gray-coded synchronization and configurable synchronization stages.

### Packetized DMA Streaming

The module automatically generates AXI-style packet boundaries using programmable beat counters and asserts `TLAST` after a configurable number of successful transfers.

This enables direct integration with AXI DMA engines and downstream packet processors.

### Embedded Protocol Assertions

SystemVerilog Assertions (SVA) continuously verify critical protocol assumptions during simulation.

Assertions check:

* Valid requests exist before arbitration
* Granted channels actually requested service
* Internal AXI handshake behavior remains legal

---

## System Architecture

```text
                   WRITE DOMAIN (wclk)
 ┌────────────────────────────────────────────────────┐

 Sensor 0 ─┐
 Sensor 1 ─┼─────► Round Robin Arbiter ─────┐
 Sensor 2 ─┤                               │
 Sensor N ─┘                               │

                 Timestamp Capture Engine
                           │
                           ▼
               {TLAST, TS, ID, DATA}
                           │
                           ▼
                 XPM Async FIFO (CDC)
                           │

 └────────────────────────────────────────────────────┘


                    READ DOMAIN (rclk)

                           │
                           ▼

                AXI-Stream DMA Interface

                m_tvalid
                m_tdata
                m_tid
                m_tuser
                m_tlast
```

---

## Data Packet Format

Each transaction written into the CDC FIFO contains:

```text
+-----------------------------------------------------+
| TLAST | TIMESTAMP | SOURCE_ID | SENSOR_DATA |
+-----------------------------------------------------+
```

| Field       | Description                       |
| ----------- | --------------------------------- |
| TLAST       | Packet boundary indicator         |
| TIMESTAMP   | Acquisition timestamp             |
| SOURCE_ID   | Channel that generated the sample |
| SENSOR_DATA | Original sensor payload           |

---

## Timestamp Engine

A free-running hardware counter increments every write-domain clock cycle.

When a sensor asserts `s_tvalid`:

```verilog
if (s_tvalid[i] && !s_tvalid_q[i])
    capture_ts[i] <= current_time;
```

The timestamp is captured immediately and stored until arbitration occurs.

This prevents arbitration latency from corrupting acquisition timing information.

---

## Arbitration Strategy

The arbiter maintains a record of the last granted source.

For every successful transfer:

1. Search begins at the next source index.
2. The first requesting source is selected.
3. The grant pointer advances.
4. Fairness is preserved.

Example:

```text
Sources requesting:

0 1 2 3

Grant sequence:

0 → 1 → 2 → 3 → 0 → 1 ...
```

No source can permanently monopolize the output channel.

---

## Clock Domain Crossing

The CDC boundary is implemented using:

```verilog
xpm_fifo_async
```

Configuration:

* Block RAM implementation
* First Word Fall Through (FWFT)
* Two-stage synchronizers
* Independent read/write clocks

Benefits:

* Metastability protection
* Independent clock frequencies
* High throughput
* Vendor-validated implementation

---

## TLAST Packet Generation

Packet boundaries are generated using successful write handshakes.

```verilog
if (beat_count == PACKET_BEATS - 1)
```

This approach ensures packet length remains correct even under FIFO backpressure conditions.

Default:

```text
PACKET_BEATS = 256
```

Result:

```text
Beat 255 -> TLAST asserted
Beat 256 -> Counter resets
```

---

## Verification Strategy

The design includes a self-checking SystemVerilog testbench.

### Test Configuration

| Parameter     | Value   |
| ------------- | ------- |
| Sources       | 8       |
| Data Width    | 64      |
| Packet Length | 16      |
| Write Clock   | 100 MHz |
| Read Clock    | 25 MHz  |

### Verification Coverage

* Multi-source arbitration
* Timestamp propagation
* CDC FIFO operation
* Packet boundary generation
* Backpressure behavior
* Data integrity checking

The testbench automatically:

1. Records every accepted input transaction.
2. Tracks expected packet boundaries.
3. Compares FIFO outputs against expected values.
4. Reports mismatches.
5. Generates pass/fail status.

---

## Simulation Results

Successful execution produces:

```text
[INFO] Processed Pack ID X | Time: Y | TLAST: Z
```

Final output: 

```text
SIMULATION COMPLETE

Items Processed: 17

[PASSED] Full Pipeline is bulletproof!
```

---

## Parameters

| Parameter    | Description               |
| ------------ | ------------------------- |
| NUM_SOURCES  | Number of sensor channels |
| DATA_WIDTH   | Width of sensor payload   |
| TS_WIDTH     | Timestamp width           |
| FIFO_DEPTH   | Async FIFO depth          |
| PACKET_BEATS | TLAST interval            |

---

## Directory Structure

```text
HETEROGENEOUSCDCARBITER/
│
├── src/
│   └── sensor_acquisition_master.sv
│
├── tb/
│   └── tb_sensor_acquisition_top.sv
│
└── README.md
```

---

## Applications

Typical deployment targets include:

* Multi-sensor FPGA acquisition systems
* Industrial monitoring platforms
* FPGA-based DAQ systems
* High-speed telemetry systems
* Software Defined Radio front ends
* DMA-driven embedded processing pipelines

---

## Future Enhancements

* Weighted round-robin scheduling
* AXI4-Stream sideband support
* Dynamic packet sizing
* CRC insertion
* Multi-FIFO virtual channels
* Performance counters
* Formal proof suite

---
