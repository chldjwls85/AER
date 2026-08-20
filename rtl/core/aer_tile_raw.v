`timescale 1ns/1ps

module aer_tile_raw #(
    parameter integer BASE_X          = 0,
    parameter integer BASE_Y          = 0,
    parameter integer FIFO_DEPTH      = 8,
    parameter integer FIFO_ADDR_WIDTH = 3
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire [15:0]                  pixel_req_async,
    input  wire [15:0]                  pixel_polarity_async,
    output wire [15:0]                  pixel_ack,
    input  wire [7:0]                   time_now,
    output wire [31:0]                  out_data,
    output wire                         out_valid,
    input  wire                         out_ready,
    output wire [FIFO_ADDR_WIDTH:0]     fifo_level
);

    wire [15:0]  pending;
    wire [15:0]  stored_polarity;
    wire [127:0] stored_time_flat;
    wire [15:0]  consume;

    wire [15:0] grant;
    wire        grant_valid;
    wire [3:0]  grant_index;
    wire        event_accept;

    wire        selected_polarity;
    wire [7:0]  selected_time;
    wire [9:0]  selected_x;
    wire [9:0]  selected_y;
    wire [31:0] selected_packet;
    wire        fifo_in_ready;

    genvar pixel;
    generate
        for (pixel = 0; pixel < 16; pixel = pixel + 1) begin : gen_event_capture
            aer_event_capture #(
                .TIME_WIDTH(8)
            ) capture_i (
                .clk              (clk),
                .rst_n            (rst_n),
                .req_async        (pixel_req_async[pixel]),
                .polarity_async   (pixel_polarity_async[pixel]),
                .time_now         (time_now),
                .consume          (consume[pixel]),
                .pending          (pending[pixel]),
                .stored_polarity  (stored_polarity[pixel]),
                .stored_time      (stored_time_flat[pixel*8 +: 8]),
                .ack              (pixel_ack[pixel])
            );
        end
    endgenerate

    aer_rr_arbiter #(
        .REQUESTS(16),
        .INDEX_WIDTH(4)
    ) local_arbiter_i (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (pending),
        .advance     (event_accept),
        .grant       (grant),
        .grant_valid (grant_valid),
        .grant_index (grant_index)
    );

    assign selected_polarity = stored_polarity[grant_index];
    assign selected_time     = stored_time_flat[grant_index*8 +: 8];
    assign selected_x        = BASE_X + {{8{1'b0}}, grant_index[1:0]};
    assign selected_y        = BASE_Y + {{8{1'b0}}, grant_index[3:2]};

    aer_raw_packetizer packetizer_i (
        .coordinate_x (selected_x),
        .coordinate_y (selected_y),
        .polarity     (selected_polarity),
        .event_time   (selected_time),
        .status_flag  (1'b0),
        .packet       (selected_packet)
    );

    assign event_accept = grant_valid && fifo_in_ready;
    assign consume      = grant & {16{event_accept}};

    aer_sync_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) tile_fifo_i (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_data   (selected_packet),
        .in_valid  (grant_valid),
        .in_ready  (fifo_in_ready),
        .out_data  (out_data),
        .out_valid (out_valid),
        .out_ready (out_ready),
        .level     (fifo_level)
    );

endmodule
