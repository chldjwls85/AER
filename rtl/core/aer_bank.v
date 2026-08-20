`timescale 1ns/1ps

module aer_bank #(
    parameter integer BASE_X          = 0,
    parameter integer BASE_Y          = 0,
    parameter integer FIFO_DEPTH      = 8,
    parameter integer FIFO_ADDR_WIDTH = 3
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [63:0]                       tile_req_async,
    input  wire [63:0]                       tile_polarity_async,
    output wire [63:0]                       tile_ack,
    input  wire [7:0]                        time_now,
    output wire [31:0]                       out_data,
    output wire                              out_valid,
    input  wire                              out_ready,
    output wire [4*(FIFO_ADDR_WIDTH+1)-1:0] tile_fifo_levels
);

    wire [127:0] tile_data_flat;
    wire [3:0]   tile_valid;
    wire [3:0]   tile_ready;
    wire [3:0]   grant;
    wire         grant_valid;
    wire [1:0]   grant_index;
    wire [31:0]  selected_data;
    wire         selected_accept;
    wire         stage_in_ready;

    genvar tile;
    generate
        for (tile = 0; tile < 4; tile = tile + 1) begin : gen_tile
            localparam integer TILE_BASE_X = BASE_X + (tile % 2) * 4;
            localparam integer TILE_BASE_Y = BASE_Y + (tile / 2) * 4;

            aer_tile_raw #(
                .BASE_X(TILE_BASE_X),
                .BASE_Y(TILE_BASE_Y),
                .FIFO_DEPTH(FIFO_DEPTH),
                .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH)
            ) tile_i (
                .clk                  (clk),
                .rst_n                (rst_n),
                .pixel_req_async      (tile_req_async[tile*16 +: 16]),
                .pixel_polarity_async (tile_polarity_async[tile*16 +: 16]),
                .pixel_ack            (tile_ack[tile*16 +: 16]),
                .time_now             (time_now),
                .out_data             (tile_data_flat[tile*32 +: 32]),
                .out_valid            (tile_valid[tile]),
                .out_ready            (tile_ready[tile]),
                .fifo_level           (tile_fifo_levels[tile*(FIFO_ADDR_WIDTH+1) +: (FIFO_ADDR_WIDTH+1)])
            );
        end
    endgenerate

    aer_rr_arbiter #(
        .REQUESTS(4),
        .INDEX_WIDTH(2)
    ) bank_arbiter_i (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (tile_valid),
        .advance     (selected_accept),
        .grant       (grant),
        .grant_valid (grant_valid),
        .grant_index (grant_index)
    );

    assign selected_data   = tile_data_flat[grant_index*32 +: 32];
    assign selected_accept = grant_valid && stage_in_ready;
    assign tile_ready      = grant & {4{selected_accept}};

    aer_stream_reg #(
        .DATA_WIDTH(32)
    ) bank_output_register_i (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_data   (selected_data),
        .in_valid  (grant_valid),
        .in_ready  (stage_in_ready),
        .out_data  (out_data),
        .out_valid (out_valid),
        .out_ready (out_ready)
    );

endmodule
