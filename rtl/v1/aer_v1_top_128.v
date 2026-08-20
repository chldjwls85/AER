`timescale 1ns/1ps

module aer_v1_top_128 #(
    parameter integer ENABLE_BINNING = 1
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [4095:0] tile_in_valid,
    input  wire [16383:0] tile_on_flat,
    input  wire [16383:0] tile_off_flat,
    output wire [4095:0] tile_in_ready,
    output wire [15:0]   out_data,
    output wire          out_valid,
    input  wire          out_ready,
    output wire          out_last
);

    wire [15:0] time_now;
    wire [4095:0] bank_data_flat;
    wire [255:0] bank_valid;
    wire [255:0] bank_last;
    wire [255:0] bank_ready;

    aer_timebase #(
        .TIME_WIDTH(16)
    ) timebase_i (
        .clk      (clk),
        .rst_n    (rst_n),
        .time_now (time_now)
    );

    genvar bank_gen;
    generate
        for (bank_gen = 0; bank_gen < 256; bank_gen = bank_gen + 1) begin : gen_bank
            wire [15:0] unused_pending;

            aer_bank_row_reader #(
                .BANK_ID(bank_gen),
                .ENABLE_BINNING(ENABLE_BINNING)
            ) bank_i (
                .clk           (clk),
                .rst_n         (rst_n),
                .tile_in_valid (tile_in_valid[bank_gen*16 +: 16]),
                .tile_on_flat  (tile_on_flat[bank_gen*64 +: 64]),
                .tile_off_flat (tile_off_flat[bank_gen*64 +: 64]),
                .tile_in_ready (tile_in_ready[bank_gen*16 +: 16]),
                .time_now      (time_now),
                .out_data      (bank_data_flat[bank_gen*16 +: 16]),
                .out_valid     (bank_valid[bank_gen]),
                .out_ready     (bank_ready[bank_gen]),
                .out_last      (bank_last[bank_gen]),
                .pending_debug (unused_pending)
            );
        end
    endgenerate

    aer_global_bank_selector #(
        .BANK_ROWS(16),
        .BANK_COLS(16),
        .ROW_INDEX_WIDTH(4),
        .COL_INDEX_WIDTH(4)
    ) global_selector_i (
        .clk            (clk),
        .rst_n          (rst_n),
        .bank_data_flat (bank_data_flat),
        .bank_valid     (bank_valid),
        .bank_last      (bank_last),
        .bank_ready     (bank_ready),
        .out_data       (out_data),
        .out_valid      (out_valid),
        .out_ready      (out_ready),
        .out_last       (out_last)
    );

endmodule
