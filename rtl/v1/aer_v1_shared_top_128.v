`timescale 1ns/1ps

// 128x128 v1 architecture with one packet engine shared by each 4x4-bank
// region.  There are 256 capture banks but only 16 classifier/packer engines.
module aer_v1_shared_top_128 #(
    parameter integer ENABLE_COMPRESSION = 1
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

    localparam integer BANK_ROWS = 16;
    localparam integer BANK_COLS = 16;
    localparam integer BANK_COUNT = 256;
    localparam integer REGION_ROWS = 4;
    localparam integer REGION_COLS = 4;
    localparam integer REGION_COUNT = 16;
    localparam integer BANKS_PER_REGION = 16;
    localparam integer SNAPSHOT_WIDTH = 152;

    wire [BANK_COUNT-1:0] bank_snapshot_valid;
    wire [BANK_COUNT-1:0] bank_snapshot_ready;
    wire [BANK_COUNT*16-1:0] bank_snapshot_mask_flat;
    wire [BANK_COUNT*128-1:0] bank_snapshot_raw_flat;

    wire [REGION_COUNT*16-1:0] region_data_flat;
    wire [REGION_COUNT-1:0] region_valid;
    wire [REGION_COUNT-1:0] region_ready;
    wire [REGION_COUNT-1:0] region_last;

    genvar bank_gen;
    generate
        for (bank_gen = 0; bank_gen < BANK_COUNT;
             bank_gen = bank_gen + 1) begin : gen_capture_bank
            wire [15:0] unused_pending;
            aer_bank_snapshot_buffer capture_i (
                .clk               (clk),
                .rst_n             (rst_n),
                .tile_in_valid     (tile_in_valid[bank_gen*16 +: 16]),
                .tile_on_flat      (tile_on_flat[bank_gen*64 +: 64]),
                .tile_off_flat     (tile_off_flat[bank_gen*64 +: 64]),
                .tile_in_ready     (tile_in_ready[bank_gen*16 +: 16]),
                .snapshot_valid    (bank_snapshot_valid[bank_gen]),
                .snapshot_ready    (bank_snapshot_ready[bank_gen]),
                .snapshot_mask     (bank_snapshot_mask_flat[
                                       bank_gen*16 +: 16]),
                .snapshot_raw_flat (bank_snapshot_raw_flat[
                                       bank_gen*128 +: 128]),
                .pending_debug     (unused_pending)
            );
        end
    endgenerate

    genvar region_gen;
    generate
        for (region_gen = 0; region_gen < REGION_COUNT;
             region_gen = region_gen + 1) begin : gen_region
            localparam integer REGION_ROW = region_gen / REGION_COLS;
            localparam integer REGION_COL = region_gen % REGION_COLS;

            wire [BANKS_PER_REGION*SNAPSHOT_WIDTH-1:0]
                selector_snapshot_flat;
            wire [BANKS_PER_REGION-1:0] selector_valid;
            wire [BANKS_PER_REGION-1:0] selector_ready;
            wire [SNAPSHOT_WIDTH-1:0] selected_snapshot;
            wire selected_valid;
            wire selected_ready;
            wire selected_last;

            wire [SNAPSHOT_WIDTH-1:0] queued_snapshot;
            wire queued_valid;
            wire queued_ready;
            wire queued_last;
            wire unused_busy;
            wire [1:0] snapshot_fifo_level;
            wire region_congestion_high;
            wire region_congestion_critical;

            genvar local_bank;
            for (local_bank = 0; local_bank < BANKS_PER_REGION;
                 local_bank = local_bank + 1) begin : gen_region_bank_map
                localparam integer LOCAL_ROW = local_bank / 4;
                localparam integer LOCAL_COL = local_bank % 4;
                localparam integer GLOBAL_ROW = REGION_ROW * 4 + LOCAL_ROW;
                localparam integer GLOBAL_COL = REGION_COL * 4 + LOCAL_COL;
                localparam integer GLOBAL_BANK =
                    GLOBAL_ROW * BANK_COLS + GLOBAL_COL;

                assign selector_snapshot_flat[
                    local_bank*SNAPSHOT_WIDTH +: SNAPSHOT_WIDTH] = {
                        GLOBAL_BANK[7:0],
                        bank_snapshot_mask_flat[GLOBAL_BANK*16 +: 16],
                        bank_snapshot_raw_flat[GLOBAL_BANK*128 +: 128]
                    };
                assign selector_valid[local_bank] =
                    bank_snapshot_valid[GLOBAL_BANK];
                assign bank_snapshot_ready[GLOBAL_BANK] =
                    selector_ready[local_bank];
            end

            // The flattened local-bank index is row-major.  The locked RR
            // pointer therefore scans row-by-row and skips empty banks.
            aer_packet_selector #(
                .STREAMS(BANKS_PER_REGION),
                .DATA_WIDTH(SNAPSHOT_WIDTH),
                .INDEX_WIDTH(4)
            ) snapshot_selector_i (
                .clk          (clk),
                .rst_n        (rst_n),
                .in_data_flat (selector_snapshot_flat),
                .in_valid     (selector_valid),
                .in_last      ({BANKS_PER_REGION{1'b1}}),
                .in_ready     (selector_ready),
                .out_data     (selected_snapshot),
                .out_valid    (selected_valid),
                .out_ready    (selected_ready),
                .out_last     (selected_last)
            );

            // Two snapshots let capture continue while the shared engine is
            // classifying or waiting for output backpressure.
            aer_stream_fifo2 #(
                .DATA_WIDTH(SNAPSHOT_WIDTH)
            ) snapshot_fifo_i (
                .clk       (clk),
                .rst_n     (rst_n),
                .in_data   (selected_snapshot),
                .in_valid  (selected_valid),
                .in_ready  (selected_ready),
                .in_last   (selected_last),
                .out_data  (queued_snapshot),
                .out_valid (queued_valid),
                .out_ready (queued_ready),
                .out_last  (queued_last),
                .level     (snapshot_fifo_level)
            );

            assign region_congestion_high =
                (snapshot_fifo_level == 2) ||
                (selected_valid && !selected_ready);
            assign region_congestion_critical =
                (snapshot_fifo_level == 2) && (&selector_valid);

            aer_shared_packet_engine #(
                .ENABLE_COMPRESSION(ENABLE_COMPRESSION)
            ) packet_engine_i (
                .clk               (clk),
                .rst_n             (rst_n),
                .snapshot_bank_id  (queued_snapshot[151:144]),
                .snapshot_mask     (queued_snapshot[143:128]),
                .snapshot_raw_flat (queued_snapshot[127:0]),
                .snapshot_valid    (queued_valid),
                .snapshot_ready    (queued_ready),
                .congestion_high   (region_congestion_high),
                .congestion_critical(region_congestion_critical),
                .out_data          (region_data_flat[region_gen*16 +: 16]),
                .out_valid         (region_valid[region_gen]),
                .out_ready         (region_ready[region_gen]),
                .out_last          (region_last[region_gen]),
                .busy_debug        (unused_busy)
            );
        end
    endgenerate

    aer_global_bank_selector #(
        .BANK_ROWS(REGION_ROWS),
        .BANK_COLS(REGION_COLS),
        .REGION_ROWS(REGION_ROWS),
        .REGION_COLS(REGION_COLS)
    ) region_selector_i (
        .clk            (clk),
        .rst_n          (rst_n),
        .bank_data_flat (region_data_flat),
        .bank_valid     (region_valid),
        .bank_last      (region_last),
        .bank_ready     (region_ready),
        .out_data       (out_data),
        .out_valid      (out_valid),
        .out_ready      (out_ready),
        .out_last       (out_last)
    );

endmodule

module aer_v1_care_top_128 (
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
    aer_v1_shared_top_128 #(
        .ENABLE_COMPRESSION(1)
    ) core_i (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat), .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .out_data(out_data), .out_valid(out_valid),
        .out_ready(out_ready), .out_last(out_last)
    );
endmodule
