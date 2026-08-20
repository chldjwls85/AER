`timescale 1ns/1ps
`include "aer_config.vh"

module aer_top (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [`AER_NUM_PIXELS-1:0]        pixel_req_async,
    input  wire [`AER_NUM_PIXELS-1:0]        pixel_polarity_async,
    output wire [`AER_NUM_PIXELS-1:0]        pixel_ack,
    output wire [`AER_PACKET_W-1:0]          event_data,
    output wire                              event_valid,
    input  wire                              event_ready,
    output wire [`AER_ALL_TILE_LEVEL_W-1:0] tile_fifo_levels
);

    wire [`AER_TIME_W-1:0] time_now;
    wire [255:0] fabric_req_async;
    wire [255:0] fabric_polarity_async;
    wire [255:0] fabric_ack;

    aer_timebase #(
        .TIME_WIDTH(`AER_TIME_W)
    ) timebase_i (
        .clk      (clk),
        .rst_n    (rst_n),
        .time_now (time_now)
    );

    // Convert the external row-major pixel order into bank-major, tile-major order.
    genvar bank_y;
    genvar bank_x;
    genvar tile_y;
    genvar tile_x;
    genvar pixel_y;
    genvar pixel_x;
    generate
        for (bank_y = 0; bank_y < 2; bank_y = bank_y + 1) begin : gen_bank_y
            for (bank_x = 0; bank_x < 2; bank_x = bank_x + 1) begin : gen_bank_x
                for (tile_y = 0; tile_y < 2; tile_y = tile_y + 1) begin : gen_tile_y
                    for (tile_x = 0; tile_x < 2; tile_x = tile_x + 1) begin : gen_tile_x
                        for (pixel_y = 0; pixel_y < 4; pixel_y = pixel_y + 1) begin : gen_pixel_y
                            for (pixel_x = 0; pixel_x < 4; pixel_x = pixel_x + 1) begin : gen_pixel_x
                                localparam integer BANK_NUMBER = bank_y * 2 + bank_x;
                                localparam integer TILE_NUMBER = tile_y * 2 + tile_x;
                                localparam integer LOCAL_PIXEL = pixel_y * 4 + pixel_x;
                                localparam integer FABRIC_INDEX =
                                    (BANK_NUMBER * 4 + TILE_NUMBER) * 16 + LOCAL_PIXEL;
                                localparam integer SENSOR_INDEX =
                                    (bank_y * 8 + tile_y * 4 + pixel_y) * 16 +
                                    (bank_x * 8 + tile_x * 4 + pixel_x);

                                assign fabric_req_async[FABRIC_INDEX] =
                                    pixel_req_async[SENSOR_INDEX];
                                assign fabric_polarity_async[FABRIC_INDEX] =
                                    pixel_polarity_async[SENSOR_INDEX];
                                assign pixel_ack[SENSOR_INDEX] = fabric_ack[FABRIC_INDEX];
                            end
                        end
                    end
                end
            end
        end
    endgenerate

    aer_fabric #(
        .FIFO_DEPTH(`AER_TILE_FIFO_DEPTH),
        .FIFO_ADDR_WIDTH(`AER_TILE_FIFO_ADDR_W)
    ) fabric_i (
        .clk                 (clk),
        .rst_n               (rst_n),
        .bank_req_async      (fabric_req_async),
        .bank_polarity_async (fabric_polarity_async),
        .bank_ack            (fabric_ack),
        .time_now            (time_now),
        .out_data            (event_data),
        .out_valid           (event_valid),
        .out_ready           (event_ready),
        .tile_fifo_levels    (tile_fifo_levels)
    );

endmodule
