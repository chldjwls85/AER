`timescale 1ns/1ps

// Fair no-binning baseline for aer_v1_top_128.
// The hierarchy, buffering, arbitration, timestamp contract, packet width,
// and output handshake are shared with the adaptive mode. Only the tile
// encoder is forced to lossless RAW8 for every non-empty 2x2 snapshot.
module aer_v1_raw_top_128 (
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

    aer_v1_top_128 #(
        .ENABLE_BINNING(0)
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
