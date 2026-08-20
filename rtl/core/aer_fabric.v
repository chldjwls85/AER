`timescale 1ns/1ps

module aer_fabric #(
    parameter integer FIFO_DEPTH      = 8,
    parameter integer FIFO_ADDR_WIDTH = 3
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [255:0]                      bank_req_async,
    input  wire [255:0]                      bank_polarity_async,
    output wire [255:0]                      bank_ack,
    input  wire [7:0]                        time_now,
    output wire [31:0]                       out_data,
    output wire                              out_valid,
    input  wire                              out_ready,
    output wire [16*(FIFO_ADDR_WIDTH+1)-1:0] tile_fifo_levels
);

    wire [127:0] bank_data_flat;
    wire [3:0]   bank_valid;
    wire [3:0]   bank_ready;
    wire [3:0]   grant;
    wire         grant_valid;
    wire [1:0]   grant_index;
    wire [31:0]  selected_data;
    wire         selected_accept;
    wire         stage_in_ready;

    genvar bank;
    generate
        for (bank = 0; bank < 4; bank = bank + 1) begin : gen_bank
            localparam integer BANK_BASE_X = (bank % 2) * 8;
            localparam integer BANK_BASE_Y = (bank / 2) * 8;

            aer_bank #(
                .BASE_X(BANK_BASE_X),
                .BASE_Y(BANK_BASE_Y),
                .FIFO_DEPTH(FIFO_DEPTH),
                .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH)
            ) bank_i (
                .clk                 (clk),
                .rst_n               (rst_n),
                .tile_req_async      (bank_req_async[bank*64 +: 64]),
                .tile_polarity_async (bank_polarity_async[bank*64 +: 64]),
                .tile_ack            (bank_ack[bank*64 +: 64]),
                .time_now            (time_now),
                .out_data            (bank_data_flat[bank*32 +: 32]),
                .out_valid           (bank_valid[bank]),
                .out_ready           (bank_ready[bank]),
                .tile_fifo_levels    (tile_fifo_levels[bank*4*(FIFO_ADDR_WIDTH+1) +: 4*(FIFO_ADDR_WIDTH+1)])
            );
        end
    endgenerate

    aer_rr_arbiter #(
        .REQUESTS(4),
        .INDEX_WIDTH(2)
    ) global_arbiter_i (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (bank_valid),
        .advance     (selected_accept),
        .grant       (grant),
        .grant_valid (grant_valid),
        .grant_index (grant_index)
    );

    assign selected_data   = bank_data_flat[grant_index*32 +: 32];
    assign selected_accept = grant_valid && stage_in_ready;
    assign bank_ready      = grant & {4{selected_accept}};

    aer_stream_reg #(
        .DATA_WIDTH(32)
    ) global_output_register_i (
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
