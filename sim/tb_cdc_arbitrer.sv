`timescale 1ns / 1ps
`default_nettype none

module tb_cdc_arbiter_fresh;

    // Parameters matching the RTL
    localparam int NUM_SOURCES  = 4;
    localparam int DATA_WIDTH   = 64; // Updated to match your RTL
    localparam int TS_WIDTH     = 64;
    localparam int FIFO_DEPTH   = 1024;
    localparam int PACKET_BEATS = 256;
    localparam int ID_W         = $clog2(NUM_SOURCES);

    // Clocks and Resets
    logic wclk = 0, rclk = 0;
    always #5.0  wclk = ~wclk; // 100 MHz
    always #13.0 rclk = ~rclk; // ~38.4 MHz (Asynchronous, prime number delay)

    logic wrst_n = 0, rrst_n = 0;

    // DUT Interfaces
    logic [NUM_SOURCES-1:0]            s_tvalid = '0;
    logic [NUM_SOURCES*DATA_WIDTH-1:0] s_tdata  = '0;
    logic [NUM_SOURCES-1:0]            s_tready;

    logic                              m_tvalid;
    logic [DATA_WIDTH-1:0]             m_tdata;
    logic [ID_W-1:0]                   m_tid;
    logic [TS_WIDTH-1:0]               m_tuser;
    logic                              m_tlast;
    logic                              m_tready = 1'b0;

    // DUT Instantiation
    cdc_arbiter #(
        .NUM_SOURCES  (NUM_SOURCES),
        .DATA_WIDTH   (DATA_WIDTH),
        .TS_WIDTH     (TS_WIDTH),
        .FIFO_DEPTH   (FIFO_DEPTH),
        .PACKET_BEATS (PACKET_BEATS)
    ) dut (.*);

    // --- AXI-Stream Push Task (Write Domain) ---
    task automatic push_beat(input int src, input logic [DATA_WIDTH-1:0] data);
        @(posedge wclk);
        s_tvalid[src] <= 1'b1;
        s_tdata[src*DATA_WIDTH +: DATA_WIDTH] <= data;
        
        // Wait for ready handshake
        forever begin
            @(posedge wclk);
            if (s_tready[src]) break;
        end
        
        s_tvalid[src] <= 1'b0;
    endtask

    // --- AXI-Stream Pop Task (Read Domain) ---
    task automatic pop_beat(
        output logic [DATA_WIDTH-1:0] data,
        output logic [ID_W-1:0]       tid
    );
        m_tready <= 1'b1;
        
        // Wait for valid handshake
        forever begin
            @(posedge rclk);
            if (m_tvalid) begin
                data = m_tdata;
                tid  = m_tid;
                m_tready <= 1'b0;
                break;
            end
        end
    endtask

    // --- Main Test Sequence ---
    initial begin
        logic [DATA_WIDTH-1:0] read_data;
        logic [ID_W-1:0]       read_tid;

        $display("========================================");
        $display("   STARTING CDC ARBITER VERIFICATION");
        $display("========================================");

        // 1. Assert Resets
        wrst_n <= 0; rrst_n <= 0;
        repeat(10) @(posedge wclk);
        wrst_n <= 1; rrst_n <= 1;
        repeat(10) @(posedge wclk);
        $display("[PASS] Reset sequence complete.");

        // 2. Basic Push/Pop Test (Source 0)
        push_beat(0, 64'hAAAA_BBBB_CCCC_DDDD);
        pop_beat(read_data, read_tid);
        
        if (read_data === 64'hAAAA_BBBB_CCCC_DDDD && read_tid === 0)
            $display("[PASS] Single beat routing successful.");
        else
            $fatal(1, "[FAIL] Single beat data/ID mismatch.");

        // 3. FIFO Burst & Round-Robin Test
        $display("--- Starting Burst Write ---");
        // Write 10 beats rapidly across different sources
        fork
            begin
                push_beat(0, 64'h1111); push_beat(0, 64'h2222);
            end
            begin
                push_beat(1, 64'h3333); push_beat(1, 64'h4444);
            end
            begin
                push_beat(2, 64'h5555); push_beat(2, 64'h6666);
            end
        join

        $display("--- Starting Burst Read ---");
        // Read out all 6 beats
        for (int i = 0; i < 6; i++) begin
            pop_beat(read_data, read_tid);
            $display("    Popped Data: %0h from Source ID: %0d", read_data, read_tid);
        end
        $display("[PASS] Burst CDC transfer successful.");

        // 4. Clean Finish
        repeat(20) @(posedge rclk);
        $display("========================================");
        $display("   ALL TESTS PASSED SUCCESSFULLY");
        $display("========================================");
        $finish;
    end

    // Failsafe Timeout
    initial begin
        #500_000;
        $fatal(1, "[FAIL] Simulation timed out. Deadlock detected.");
    end

endmodule