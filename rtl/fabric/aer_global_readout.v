`timescale 1ns/1ps

// Two-stage spatial readout for up to 16x16 banks.
// Stage 1: each 4x4 bank region is packet-arbitrated and buffered.
// Stage 2: up to 4x4 region streams are packet-arbitrated to one root link.
module aer_global_readout #(
    parameter integer BANK_ROWS  = 16,
    parameter integer BANK_COLS  = 16,
    parameter integer DATA_WIDTH = 16
) (
    input  wire [BANK_ROWS*BANK_COLS*DATA_WIDTH-1:0] bank_data_flat,
    input  wire [BANK_ROWS*BANK_COLS-1:0]            bank_valid,
    input  wire [BANK_ROWS*BANK_COLS-1:0]            bank_last,
    output wire [BANK_ROWS*BANK_COLS-1:0]            bank_ready,
    input  wire                                        clk,
    input  wire                                        rst_n,
    output wire [DATA_WIDTH-1:0]                       out_data,
    output wire                                        out_valid,
    input  wire                                        out_ready,
    output wire                                        out_last
);
    localparam integer BANK_COUNT   = BANK_ROWS * BANK_COLS;
    localparam integer REGION_ROWS  = (BANK_ROWS + 3) / 4;
    localparam integer REGION_COLS  = (BANK_COLS + 3) / 4;
    localparam integer REGION_COUNT = REGION_ROWS * REGION_COLS;

    wire [16*DATA_WIDTH-1:0] root_data_flat;
    wire [15:0] root_valid;
    wire [15:0] root_last;
    wire [15:0] root_ready;

    genvar region_gen;
    genvar slot_gen;
    generate
        for (region_gen = 0; region_gen < 16; region_gen = region_gen + 1) begin : gen_region
            if (region_gen < REGION_COUNT) begin : gen_live_region
                localparam integer REGION_ROW = region_gen / REGION_COLS;
                localparam integer REGION_COL = region_gen % REGION_COLS;
                wire [16*DATA_WIDTH-1:0] group_data_flat;
                wire [15:0] group_valid;
                wire [15:0] group_last;
                wire [15:0] group_ready;
                wire [DATA_WIDTH-1:0] selected_data;
                wire selected_valid;
                wire selected_ready;
                wire selected_last;

                for (slot_gen = 0; slot_gen < 16; slot_gen = slot_gen + 1) begin : gen_slot
                    localparam integer LOCAL_ROW = slot_gen / 4;
                    localparam integer LOCAL_COL = slot_gen % 4;
                    localparam integer BANK_ROW = REGION_ROW * 4 + LOCAL_ROW;
                    localparam integer BANK_COL = REGION_COL * 4 + LOCAL_COL;
                    if ((BANK_ROW < BANK_ROWS) && (BANK_COL < BANK_COLS)) begin : gen_live_bank
                        localparam integer BANK_INDEX = BANK_ROW * BANK_COLS + BANK_COL;
                        assign group_data_flat[slot_gen*DATA_WIDTH +: DATA_WIDTH] =
                            bank_data_flat[BANK_INDEX*DATA_WIDTH +: DATA_WIDTH];
                        assign group_valid[slot_gen] = bank_valid[BANK_INDEX];
                        assign group_last[slot_gen] = bank_last[BANK_INDEX];
                        assign bank_ready[BANK_INDEX] = group_ready[slot_gen];
                    end else begin : gen_padding_bank
                        assign group_data_flat[slot_gen*DATA_WIDTH +: DATA_WIDTH] =
                            {DATA_WIDTH{1'b0}};
                        assign group_valid[slot_gen] = 1'b0;
                        assign group_last[slot_gen] = 1'b0;
                    end
                end

                aer_packet_mux #(
                    .STREAMS(16), .DATA_WIDTH(DATA_WIDTH), .INDEX_WIDTH(4)
                ) region_mux_i (
                    .clk(clk), .rst_n(rst_n),
                    .in_data_flat(group_data_flat),
                    .in_valid(group_valid), .in_last(group_last),
                    .in_ready(group_ready),
                    .out_data(selected_data), .out_valid(selected_valid),
                    .out_ready(selected_ready), .out_last(selected_last)
                );

                aer_stream_buffer2 #(.DATA_WIDTH(DATA_WIDTH)) region_buffer_i (
                    .clk(clk), .rst_n(rst_n),
                    .in_data(selected_data), .in_valid(selected_valid),
                    .in_ready(selected_ready), .in_last(selected_last),
                    .out_data(root_data_flat[region_gen*DATA_WIDTH +: DATA_WIDTH]),
                    .out_valid(root_valid[region_gen]),
                    .out_ready(root_ready[region_gen]),
                    .out_last(root_last[region_gen])
                );
            end else begin : gen_unused_region
                assign root_data_flat[region_gen*DATA_WIDTH +: DATA_WIDTH] =
                    {DATA_WIDTH{1'b0}};
                assign root_valid[region_gen] = 1'b0;
                assign root_last[region_gen] = 1'b0;
            end
        end
    endgenerate

    aer_packet_mux #(
        .STREAMS(16), .DATA_WIDTH(DATA_WIDTH), .INDEX_WIDTH(4)
    ) root_mux_i (
        .clk(clk), .rst_n(rst_n),
        .in_data_flat(root_data_flat),
        .in_valid(root_valid), .in_last(root_last),
        .in_ready(root_ready),
        .out_data(out_data), .out_valid(out_valid),
        .out_ready(out_ready), .out_last(out_last)
    );

    initial begin
        if ((BANK_ROWS < 1) || (BANK_COLS < 1) ||
            (BANK_ROWS > 16) || (BANK_COLS > 16)) begin
            $display("AER_READOUT_BAD_BANK_ARRAY rows=%0d cols=%0d", BANK_ROWS, BANK_COLS);
            $fatal(1);
        end
    end
endmodule
