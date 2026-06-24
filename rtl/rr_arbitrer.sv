`timescale 1ns / 1ps
`default_nettype none

module rr_arbiter #(
    parameter int NUM_SOURCES = 4,
    parameter int DATA_WIDTH  = 64,
    parameter int ID_W        = $clog2(NUM_SOURCES > 1 ? NUM_SOURCES : 2)
)(
    input  wire                     clk, rst_n,
    input  wire [NUM_SOURCES-1:0]   s_tvalid,
    input  wire [DATA_WIDTH-1:0]    s_tdata  [NUM_SOURCES],
    output logic [NUM_SOURCES-1:0]  s_tready,
    // To FIFO bundler
    output logic                    arb_tvalid,
    output logic [DATA_WIDTH-1:0]   arb_tdata,
    output logic [ID_W-1:0]         arb_tid,
    input  wire                     arb_tready
);

    logic [ID_W-1:0] last_grant_id, next_grant_id;
    logic            any_req;

    assign any_req = |s_tvalid;

    // Synthesizable priority scan - no break
    always_comb begin
        next_grant_id = last_grant_id;
        if (any_req) begin
            logic found;
            found = 1'b0;
            for (int i = 1; i <= NUM_SOURCES; i++) begin
                int idx;
                idx = (last_grant_id + i) >= NUM_SOURCES
                    ? (last_grant_id + i - NUM_SOURCES)
                    : (last_grant_id + i);
                if (!found && s_tvalid[idx]) begin
                    next_grant_id = idx[ID_W-1:0];
                    found = 1'b1;
                end
            end
        end
    end

    wire handshake = arb_tvalid && arb_tready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) last_grant_id <= '0;
        else if (handshake) last_grant_id <= next_grant_id; 
    end

    assign arb_tvalid = any_req;
    assign arb_tid    = next_grant_id;
    assign arb_tdata  = s_tdata[next_grant_id];

    always_comb begin
        for (int i = 0; i < NUM_SOURCES; i++)
            s_tready[i] = (next_grant_id == i[ID_W-1:0]) ? arb_tready : 1'b0;
    end

endmodule