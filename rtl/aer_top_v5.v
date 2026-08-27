`timescale 1ns/1ps

// V5 lightweight SPARSE/ROW AER readout with regional timebases.
module aer_top_v5 #(
    parameter integer SENSOR_ROWS = 128,
    parameter integer SENSOR_COLS = 128,
    parameter integer MAX_BANK_DELTA = 31
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
    localparam integer BANK_ROWS   = SENSOR_ROWS / 8;
    localparam integer BANK_COLS   = SENSOR_COLS / 8;
    localparam integer BANK_COUNT  = BANK_ROWS * BANK_COLS;
    localparam integer TILE_COUNT  = BANK_COUNT * 16;
    localparam integer REGION_COLS = (BANK_COLS + 3) / 4;

    wire [16*16-1:0] regional_time_flat;
    wire [BANK_COUNT*16-1:0] bank_data_flat;
    wire [BANK_COUNT-1:0] bank_valid;
    wire [BANK_COUNT-1:0] bank_last;
    wire [BANK_COUNT-1:0] bank_ready;

    genvar timebase_gen;
    generate
        for (timebase_gen = 0; timebase_gen < 16;
             timebase_gen = timebase_gen + 1) begin : gen_regional_timebase
            aer_timebase #(.TIME_WIDTH(16)) regional_timebase_i (
                .clk(clk),
                .rst_n(rst_n),
                .time_now(regional_time_flat[timebase_gen*16 +: 16])
            );
        end
    endgenerate

    genvar bank_gen;
    generate
        for (bank_gen = 0; bank_gen < BANK_COUNT;
             bank_gen = bank_gen + 1) begin : gen_bank
            localparam integer BANK_ROW = bank_gen / BANK_COLS;
            localparam integer BANK_COL = bank_gen % BANK_COLS;
            localparam integer REGION_ROW = BANK_ROW / 4;
            localparam integer REGION_COL = BANK_COL / 4;
            localparam integer REGION_ID = REGION_ROW * REGION_COLS + REGION_COL;
            wire [15:0] unused_pending;

            aer_bank_packetizer_v4 #(
                .BANK_ID(bank_gen),
                .MAX_BANK_DELTA(MAX_BANK_DELTA)
            ) bank_packetizer_i (
                .clk(clk),
                .rst_n(rst_n),
                .tile_in_valid(tile_in_valid[bank_gen*16 +: 16]),
                .tile_on_flat(tile_on_flat[bank_gen*64 +: 64]),
                .tile_off_flat(tile_off_flat[bank_gen*64 +: 64]),
                .tile_in_ready(tile_in_ready[bank_gen*16 +: 16]),
                .time_now(regional_time_flat[REGION_ID*16 +: 16]),
                .out_data(bank_data_flat[bank_gen*16 +: 16]),
                .out_valid(bank_valid[bank_gen]),
                .out_ready(bank_ready[bank_gen]),
                .out_last(bank_last[bank_gen]),
                .pending_debug(unused_pending)
            );
        end
    endgenerate

    aer_global_readout #(
        .BANK_ROWS(BANK_ROWS),
        .BANK_COLS(BANK_COLS),
        .DATA_WIDTH(16)
    ) readout_i (
        .bank_data_flat(bank_data_flat),
        .bank_valid(bank_valid),
        .bank_last(bank_last),
        .bank_ready(bank_ready),
        .clk(clk),
        .rst_n(rst_n),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_last(out_last)
    );

    initial begin
        if ((SENSOR_ROWS < 8) || (SENSOR_COLS < 8) ||
            ((SENSOR_ROWS % 8) != 0) || ((SENSOR_COLS % 8) != 0)) begin
            $display("AER_V5_BAD_SENSOR_SIZE rows=%0d cols=%0d",
                     SENSOR_ROWS, SENSOR_COLS);
            $fatal(1);
        end
        if ((BANK_ROWS > 16) || (BANK_COLS > 16)) begin
            $display("AER_V5_BANK_ARRAY_TOO_LARGE rows=%0d cols=%0d",
                     BANK_ROWS, BANK_COLS);
            $fatal(1);
        end
        if (TILE_COUNT != (SENSOR_ROWS/2)*(SENSOR_COLS/2)) begin
            $display("AER_V5_TILE_COUNT_MISMATCH");
            $fatal(1);
        end
    end
endmodule

module aer_top_v5_128 (
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
    aer_top_v5 #(
        .SENSOR_ROWS(128),
        .SENSOR_COLS(128),
        .MAX_BANK_DELTA(31)
    ) top_i (
        .clk(clk),
        .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat),
        .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_last(out_last)
    );
endmodule
