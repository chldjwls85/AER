`timescale 1ns/1ps

// Fair RAW baseline for the region-shared CARE architecture.
// Capture banks, two-entry regional snapshot FIFOs, arbitration, pipeline
// latency, packet width, and output handshake are identical.  Only the packet
// engine is restricted to lossless RAW8.
module aer_v1_raw_top_128 #(
    parameter integer EXTERNAL_RX_TIMESTAMP = 0
) (
    input  wire           clk,
    input  wire           rst_n,
    input  wire [4095:0]  tile_in_valid,
    input  wire [16383:0] tile_on_flat,
    input  wire [16383:0] tile_off_flat,
    output wire [4095:0]  tile_in_ready,
    output wire [15:0]    out_data,
    output wire           out_valid,
    input  wire           out_ready,
    output wire           out_last
);

    wire unused_external_timestamp;
    assign unused_external_timestamp = EXTERNAL_RX_TIMESTAMP;

    aer_v1_shared_top_128 #(
        .ENABLE_COMPRESSION(0)
    ) shared_core_i (
        .clk           (clk),
        .rst_n         (rst_n),
        .tile_in_valid (tile_in_valid),
        .tile_on_flat  (tile_on_flat),
        .tile_off_flat (tile_off_flat),
        .tile_in_ready (tile_in_ready),
        .out_data      (out_data),
        .out_valid     (out_valid),
        .out_ready     (out_ready),
        .out_last      (out_last)
    );

endmodule
