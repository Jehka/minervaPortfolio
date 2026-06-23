`timescale 1ns / 1ps

module tb_cdc_timestamp_arbitrer();

    // Dynamically override parameters for testing
    localparam int TEST_SOURCES = 8;
    localparam int TEST_DATA_W  = 64;
    localparam int TEST_PACKET  = 16; 
    
    logic wclk = 0, rclk = 0;
    logic wrst_n = 0, rrst_n = 0;

    logic [TEST_SOURCES-1:0] s_tvalid;
    logic [TEST_DATA_W-1:0]  s_tdata [TEST_SOURCES];
    logic [TEST_SOURCES-1:0] s_tready;

    logic m_tvalid, m_tready, m_tlast;
    logic [TEST_DATA_W-1:0]          m_tdata;
    logic [$clog2(TEST_SOURCES)-1:0] m_tid;
    logic [63:0]                     m_tuser;

    cdc_timestamp_arbitrer #(
        .NUM_SOURCES(TEST_SOURCES),
        .DATA_WIDTH(TEST_DATA_W),
        .PACKET_BEATS(TEST_PACKET)
    ) uut (.*);

    always #5 wclk = ~wclk;    
    always #20 rclk = ~rclk; 

    int error_count = 0;
    int items_processed = 0;
    
    // Store expected payloads {TLAST, ID, Data}
    logic [1 + $clog2(TEST_SOURCES) + TEST_DATA_W - 1 : 0] expected_queue [$];

    // Auto-Monitor Inputs
    logic [$clog2(TEST_PACKET):0] write_beat_cnt = 0;
    always @(posedge wclk) begin
        for (int i = 0; i < TEST_SOURCES; i++) begin
            if (s_tvalid[i] && s_tready[i]) begin
                logic exp_tlast = (write_beat_cnt == TEST_PACKET - 1);
                expected_queue.push_back({exp_tlast, i[$clog2(TEST_SOURCES)-1:0], s_tdata[i]});
                
                if (exp_tlast) write_beat_cnt = 0;
                else write_beat_cnt++;
            end
        end
    end

    // Auto-Monitor Outputs
    always @(posedge rclk) begin
        if (m_tvalid && m_tready) begin
            logic [1 + $clog2(TEST_SOURCES) + TEST_DATA_W - 1 : 0] expected, actual;
            
            actual = {m_tlast, m_tid, m_tdata};
            expected = expected_queue.pop_front();
            
            if (actual !== expected) begin
                $display("[ERROR] Mismatch! Expected TLAST:%b ID:%0d Data:%h | Got TLAST:%b ID:%0d Data:%h", 
                         expected[$bits(expected)-1], expected[$bits(expected)-2 : TEST_DATA_W], expected[TEST_DATA_W-1:0],
                         actual[$bits(actual)-1], actual[$bits(actual)-2 : TEST_DATA_W], actual[TEST_DATA_W-1:0]);
                error_count++;
            end else begin
                $display("[INFO] Processed Pack ID %0d | Time: %0d | TLAST: %b", m_tid, m_tuser, m_tlast);
                items_processed++;
            end
        end
    end

    initial begin
        $display("========================================");
        $display("   STARTING DYNAMIC SYSTEM SIMULATION   ");
        $display("========================================");

        s_tvalid = '0; m_tready = 0;
        
        // Initialize dynamic array with dummy data based on their index
        for (int i = 0; i < TEST_SOURCES; i++) begin
            s_tdata[i] = (i + 1) * 64'h1111_0000;
        end

        #20 wrst_n = 1; rrst_n = 1; #20;

        // --- TEST: Fire all sources continuously until TLAST fires ---
        @(posedge wclk);
        s_tvalid = '1; // Set all valid bits high
        
        // Wait until 17 write handshakes occur (to guarantee we see the TLAST packet boundary at 16)
        repeat(17) @(posedge wclk);
        s_tvalid = '0;

        #100;

        // Drain the FIFO
        @(posedge rclk);
        m_tready = 1;
        repeat(17) @(posedge rclk);
        m_tready = 0;

        #50;
        $display("========================================");
        $display("   SIMULATION COMPLETE");
        $display("   Items Processed: %0d", items_processed);
        if (error_count == 0 && items_processed == 17) 
             $display("   [PASSED] Full Pipeline is bulletproof!");
        else $display("   [FAILED] Errors: %0d", error_count);
        $display("========================================");
        $finish;
    end

endmodule