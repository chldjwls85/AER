`timescale 1ns/1ps

// Sensor-size-parameterized AER v1 hierarchy.  The leaf geometry remains a
// 2x2-pixel tile and a 4x4-tile bank; sensor dimensions determine the bank
// array and the balanced selector tree determines its own minimum depth.
module aer_v1_top #(
    parameter integer SENSOR_ROWS      = 128,
    parameter integer SENSOR_COLS      = 128,
    parameter integer REGION_BANK_ROWS = 4,
    parameter integer REGION_BANK_COLS = 4,
    parameter integer ENABLE_BINNING   = 1,
    parameter integer ENABLE_ROW_FUSION = 0,
    parameter integer ENABLE_BANK_FUSION = 0,
    parameter integer ENABLE_LOSSY_BINNING = 0,
    parameter integer ENABLE_SPARSE = 0,
    parameter integer EXTERNAL_RX_TIMESTAMP = 0
) (
    input  wire                                                   clk,
    input  wire                                                   rst_n,
    input  wire [(SENSOR_ROWS/2)*(SENSOR_COLS/2)-1:0]            tile_in_valid,
    input  wire [(SENSOR_ROWS/2)*(SENSOR_COLS/2)*4-1:0]          tile_on_flat,
    input  wire [(SENSOR_ROWS/2)*(SENSOR_COLS/2)*4-1:0]          tile_off_flat,
    output wire [(SENSOR_ROWS/2)*(SENSOR_COLS/2)-1:0]            tile_in_ready,
    output wire [15:0]                                            out_data,
    output wire                                                   out_valid,
    input  wire                                                   out_ready,
    output wire                                                   out_last
);

    localparam integer BANK_ROWS = SENSOR_ROWS / 8;
    localparam integer BANK_COLS = SENSOR_COLS / 8;
    localparam integer BANK_COUNT = BANK_ROWS * BANK_COLS;
    localparam integer TILE_COUNT = BANK_COUNT * 16;
    localparam integer USE_EXTENDED_BANK_ID = (BANK_COUNT > 256) ? 1 : 0;

    wire [15:0] time_now;
    wire [BANK_COUNT*16-1:0] bank_data_flat;
    wire [BANK_COUNT-1:0]    bank_valid;
    wire [BANK_COUNT-1:0]    bank_last;
    wire [BANK_COUNT-1:0]    bank_ready;

    aer_timebase #(
        .TIME_WIDTH(16)
    ) timebase_i (
        .clk      (clk),
        .rst_n    (rst_n),
        .time_now (time_now)
    );

    genvar bank_gen;
    generate
        for (bank_gen = 0; bank_gen < BANK_COUNT; bank_gen = bank_gen + 1) begin : gen_bank
            wire [15:0] unused_pending;

            if ((ENABLE_BINNING != 0) &&
                (ENABLE_ROW_FUSION == 0) &&
                (ENABLE_BANK_FUSION != 0) &&
                (ENABLE_LOSSY_BINNING != 0) &&
                (ENABLE_SPARSE != 0) &&
                (EXTERNAL_RX_TIMESTAMP != 0) &&
                (USE_EXTENDED_BANK_ID == 0)) begin : gen_combined_opt
                aer_bank_row_reader_combined_opt #(
                    .BANK_ID(bank_gen)
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
            end else begin : gen_legacy
                aer_bank_row_reader #(
                    .BANK_ID(bank_gen),
                    .EXTENDED_BANK_ID(USE_EXTENDED_BANK_ID),
                    .ENABLE_BINNING(ENABLE_BINNING),
                    .ENABLE_ROW_FUSION(ENABLE_ROW_FUSION),
                    .ENABLE_BANK_FUSION(ENABLE_BANK_FUSION),
                    .ENABLE_LOSSY_BINNING(ENABLE_LOSSY_BINNING),
                    .ENABLE_SPARSE(ENABLE_SPARSE),
                    .EXTERNAL_RX_TIMESTAMP(EXTERNAL_RX_TIMESTAMP)
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
        end
    endgenerate

    aer_global_bank_selector #(
        .BANK_ROWS(BANK_ROWS),
        .BANK_COLS(BANK_COLS),
        .REGION_ROWS(REGION_BANK_ROWS),
        .REGION_COLS(REGION_BANK_COLS)
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

    initial begin
        if ((SENSOR_ROWS < 8) || (SENSOR_COLS < 8) ||
            ((SENSOR_ROWS % 8) != 0) || ((SENSOR_COLS % 8) != 0)) begin
            $display("AER_V1_BAD_SENSOR_SIZE rows=%0d cols=%0d",
                SENSOR_ROWS, SENSOR_COLS);
            $fatal(1);
        end
        if ((TILE_COUNT != (SENSOR_ROWS/2)*(SENSOR_COLS/2)) ||
            (BANK_COUNT > 65536)) begin
            $display("AER_V1_UNSUPPORTED_CONFIGURATION banks=%0d tiles=%0d",
                BANK_COUNT, TILE_COUNT);
            $fatal(1);
        end
    end

endmodule

// Source-compatible wrapper for the original fixed-size top.
module aer_v1_top_128 #(
    parameter integer ENABLE_BINNING = 1,
    parameter integer ENABLE_ROW_FUSION = 0,
    parameter integer ENABLE_BANK_FUSION = 0,
    parameter integer ENABLE_LOSSY_BINNING = 0,
    parameter integer ENABLE_SPARSE = 0,
    parameter integer EXTERNAL_RX_TIMESTAMP = 0
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

    aer_v1_top #(
        .SENSOR_ROWS(128),
        .SENSOR_COLS(128),
        .REGION_BANK_ROWS(4),
        .REGION_BANK_COLS(4),
        .ENABLE_BINNING(ENABLE_BINNING),
        .ENABLE_ROW_FUSION(ENABLE_ROW_FUSION),
        .ENABLE_BANK_FUSION(ENABLE_BANK_FUSION),
        .ENABLE_LOSSY_BINNING(ENABLE_LOSSY_BINNING),
        .ENABLE_SPARSE(ENABLE_SPARSE),
        .EXTERNAL_RX_TIMESTAMP(EXTERNAL_RX_TIMESTAMP)
    ) parameterized_top_i (
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
