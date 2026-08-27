`timescale 1ns/1ps

// Packet-aware selector used at every node of the spatial hierarchy.
module aer_packet_selector #(
    parameter integer STREAMS     = 16,
    parameter integer DATA_WIDTH  = 16,
    parameter integer INDEX_WIDTH = 4
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire [STREAMS*DATA_WIDTH-1:0] in_data_flat,
    input  wire [STREAMS-1:0]            in_valid,
    input  wire [STREAMS-1:0]            in_last,
    output reg  [STREAMS-1:0]            in_ready,
    output reg  [DATA_WIDTH-1:0]         out_data,
    output reg                           out_valid,
    input  wire                          out_ready,
    output reg                           out_last
);

    wire [STREAMS-1:0] grant;
    wire               grant_valid;
    wire [INDEX_WIDTH-1:0] grant_index;
    wire               advance;
    integer            selected_stream;

    aer_locked_rr_arbiter #(
        .REQUESTS(STREAMS),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) arbiter_i (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (in_valid),
        .advance     (advance),
        .grant       (grant),
        .grant_valid (grant_valid),
        .grant_index (grant_index)
    );

    always @* begin
        selected_stream = grant_index;
        in_ready = {STREAMS{1'b0}};
        out_data  = {DATA_WIDTH{1'b0}};
        out_valid = 1'b0;
        out_last  = 1'b0;

        if (grant_valid) begin
            out_data = in_data_flat[selected_stream*DATA_WIDTH +: DATA_WIDTH];
            out_valid = in_valid[selected_stream];
            out_last = in_last[selected_stream];
            in_ready[selected_stream] = out_ready;
        end
    end

    assign advance = out_valid && out_ready && out_last;

endmodule

// One physical hierarchy level.  Each output node covers a rectangular,
// spatially-local GROUP_ROWS x GROUP_COLS set of child nodes.  Missing children
// on a sensor edge are tied off, so every live path has the same stage count.
module aer_spatial_selector_level #(
    parameter integer INPUT_ROWS  = 16,
    parameter integer INPUT_COLS  = 16,
    parameter integer GROUP_ROWS  = 4,
    parameter integer GROUP_COLS  = 4,
    parameter integer DATA_WIDTH  = 16,
    parameter integer OUTPUT_ROWS = (INPUT_ROWS + GROUP_ROWS - 1) / GROUP_ROWS,
    parameter integer OUTPUT_COLS = (INPUT_COLS + GROUP_COLS - 1) / GROUP_COLS
) (
    input  wire                                      clk,
    input  wire                                      rst_n,
    input  wire [INPUT_ROWS*INPUT_COLS*DATA_WIDTH-1:0] in_data_flat,
    input  wire [INPUT_ROWS*INPUT_COLS-1:0]          in_valid,
    input  wire [INPUT_ROWS*INPUT_COLS-1:0]          in_last,
    output wire [INPUT_ROWS*INPUT_COLS-1:0]          in_ready,
    output wire [OUTPUT_ROWS*OUTPUT_COLS*DATA_WIDTH-1:0] out_data_flat,
    output wire [OUTPUT_ROWS*OUTPUT_COLS-1:0]        out_valid,
    input  wire [OUTPUT_ROWS*OUTPUT_COLS-1:0]        out_ready,
    output wire [OUTPUT_ROWS*OUTPUT_COLS-1:0]        out_last
);

    localparam integer GROUP_INPUTS = GROUP_ROWS * GROUP_COLS;

    function integer index_width;
        input integer count;
        integer value;
        begin
            value = count - 1;
            index_width = 0;
            while (value > 0) begin
                value = value >> 1;
                index_width = index_width + 1;
            end
            if (index_width == 0)
                index_width = 1;
        end
    endfunction

    localparam integer GROUP_INDEX_WIDTH = index_width(GROUP_INPUTS);

    genvar output_node;
    generate
        for (output_node = 0;
             output_node < OUTPUT_ROWS*OUTPUT_COLS;
             output_node = output_node + 1) begin : gen_output_node
            localparam integer OUTPUT_ROW = output_node / OUTPUT_COLS;
            localparam integer OUTPUT_COL = output_node % OUTPUT_COLS;

            wire [GROUP_INPUTS*DATA_WIDTH-1:0] group_data_flat;
            wire [GROUP_INPUTS-1:0]            group_valid;
            wire [GROUP_INPUTS-1:0]            group_last;
            wire [GROUP_INPUTS-1:0]            group_ready;
            wire [DATA_WIDTH-1:0]               selected_data;
            wire                                selected_valid;
            wire                                selected_ready;
            wire                                selected_last;
            wire [1:0]                          unused_fifo_level;

            genvar group_input;
            for (group_input = 0;
                 group_input < GROUP_INPUTS;
                 group_input = group_input + 1) begin : gen_group_input
                localparam integer LOCAL_ROW = group_input / GROUP_COLS;
                localparam integer LOCAL_COL = group_input % GROUP_COLS;
                localparam integer INPUT_ROW = OUTPUT_ROW * GROUP_ROWS + LOCAL_ROW;
                localparam integer INPUT_COL = OUTPUT_COL * GROUP_COLS + LOCAL_COL;

                if ((INPUT_ROW < INPUT_ROWS) && (INPUT_COL < INPUT_COLS)) begin : gen_live_input
                    localparam integer INPUT_INDEX = INPUT_ROW * INPUT_COLS + INPUT_COL;
                    assign group_data_flat[group_input*DATA_WIDTH +: DATA_WIDTH] =
                        in_data_flat[INPUT_INDEX*DATA_WIDTH +: DATA_WIDTH];
                    assign group_valid[group_input] = in_valid[INPUT_INDEX];
                    assign group_last[group_input] = in_last[INPUT_INDEX];
                    assign in_ready[INPUT_INDEX] = group_ready[group_input];
                end else begin : gen_padding_input
                    assign group_data_flat[group_input*DATA_WIDTH +: DATA_WIDTH] =
                        {DATA_WIDTH{1'b0}};
                    assign group_valid[group_input] = 1'b0;
                    assign group_last[group_input] = 1'b0;
                end
            end

            aer_packet_selector #(
                .STREAMS(GROUP_INPUTS),
                .DATA_WIDTH(DATA_WIDTH),
                .INDEX_WIDTH(GROUP_INDEX_WIDTH)
            ) selector_i (
                .clk          (clk),
                .rst_n        (rst_n),
                .in_data_flat (group_data_flat),
                .in_valid     (group_valid),
                .in_last      (group_last),
                .in_ready     (group_ready),
                .out_data     (selected_data),
                .out_valid    (selected_valid),
                .out_ready    (selected_ready),
                .out_last     (selected_last)
            );

            aer_stream_fifo2 #(
                .DATA_WIDTH(DATA_WIDTH)
            ) output_fifo_i (
                .clk       (clk),
                .rst_n     (rst_n),
                .in_data   (selected_data),
                .in_valid  (selected_valid),
                .in_ready  (selected_ready),
                .in_last   (selected_last),
                .out_data  (out_data_flat[output_node*DATA_WIDTH +: DATA_WIDTH]),
                .out_valid (out_valid[output_node]),
                .out_ready (out_ready[output_node]),
                .out_last  (out_last[output_node]),
                .level     (unused_fifo_level)
            );
        end
    endgenerate

endmodule

module aer_balanced_selector_tree #(
    parameter integer INPUT_ROWS = 16,
    parameter integer INPUT_COLS = 16,
    parameter integer GROUP_ROWS = 4,
    parameter integer GROUP_COLS = 4,
    parameter integer DATA_WIDTH = 16
) (
    input  wire                                      clk,
    input  wire                                      rst_n,
    input  wire [INPUT_ROWS*INPUT_COLS*DATA_WIDTH-1:0] in_data_flat,
    input  wire [INPUT_ROWS*INPUT_COLS-1:0]          in_valid,
    input  wire [INPUT_ROWS*INPUT_COLS-1:0]          in_last,
    output wire [INPUT_ROWS*INPUT_COLS-1:0]          in_ready,
    output wire [DATA_WIDTH-1:0]                     out_data,
    output wire                                      out_valid,
    input  wire                                      out_ready,
    output wire                                      out_last
);

    localparam integer L1_ROWS = (INPUT_ROWS + GROUP_ROWS - 1) / GROUP_ROWS;
    localparam integer L1_COLS = (INPUT_COLS + GROUP_COLS - 1) / GROUP_COLS;
    localparam integer L1_COUNT = L1_ROWS * L1_COLS;
    localparam integer L2_ROWS = (L1_ROWS + GROUP_ROWS - 1) / GROUP_ROWS;
    localparam integer L2_COLS = (L1_COLS + GROUP_COLS - 1) / GROUP_COLS;
    localparam integer L2_COUNT = L2_ROWS * L2_COLS;
    localparam integer L3_ROWS = (L2_ROWS + GROUP_ROWS - 1) / GROUP_ROWS;
    localparam integer L3_COLS = (L2_COLS + GROUP_COLS - 1) / GROUP_COLS;
    localparam integer L3_COUNT = L3_ROWS * L3_COLS;
    localparam integer L4_ROWS = (L3_ROWS + GROUP_ROWS - 1) / GROUP_ROWS;
    localparam integer L4_COLS = (L3_COLS + GROUP_COLS - 1) / GROUP_COLS;
    localparam integer L4_COUNT = L4_ROWS * L4_COLS;

    wire [L1_COUNT*DATA_WIDTH-1:0] level1_data;
    wire [L1_COUNT-1:0]            level1_valid;
    wire [L1_COUNT-1:0]            level1_ready;
    wire [L1_COUNT-1:0]            level1_last;

    aer_spatial_selector_level #(
        .INPUT_ROWS(INPUT_ROWS),
        .INPUT_COLS(INPUT_COLS),
        .GROUP_ROWS(GROUP_ROWS),
        .GROUP_COLS(GROUP_COLS),
        .DATA_WIDTH(DATA_WIDTH)
    ) level1_i (
        .clk           (clk),
        .rst_n         (rst_n),
        .in_data_flat  (in_data_flat),
        .in_valid      (in_valid),
        .in_last       (in_last),
        .in_ready      (in_ready),
        .out_data_flat (level1_data),
        .out_valid     (level1_valid),
        .out_ready     (level1_ready),
        .out_last      (level1_last)
    );

    generate
        if (L1_COUNT == 1) begin : gen_root_at_level1
            assign level1_ready[0] = out_ready;
            assign out_data = level1_data[0 +: DATA_WIDTH];
            assign out_valid = level1_valid[0];
            assign out_last = level1_last[0];
        end else begin : gen_level2
            wire [L2_COUNT*DATA_WIDTH-1:0] level2_data;
            wire [L2_COUNT-1:0]            level2_valid;
            wire [L2_COUNT-1:0]            level2_ready;
            wire [L2_COUNT-1:0]            level2_last;

            aer_spatial_selector_level #(
                .INPUT_ROWS(L1_ROWS),
                .INPUT_COLS(L1_COLS),
                .GROUP_ROWS(GROUP_ROWS),
                .GROUP_COLS(GROUP_COLS),
                .DATA_WIDTH(DATA_WIDTH)
            ) level2_i (
                .clk           (clk),
                .rst_n         (rst_n),
                .in_data_flat  (level1_data),
                .in_valid      (level1_valid),
                .in_last       (level1_last),
                .in_ready      (level1_ready),
                .out_data_flat (level2_data),
                .out_valid     (level2_valid),
                .out_ready     (level2_ready),
                .out_last      (level2_last)
            );

            if (L2_COUNT == 1) begin : gen_root_at_level2
                assign level2_ready[0] = out_ready;
                assign out_data = level2_data[0 +: DATA_WIDTH];
                assign out_valid = level2_valid[0];
                assign out_last = level2_last[0];
            end else begin : gen_level3
                wire [L3_COUNT*DATA_WIDTH-1:0] level3_data;
                wire [L3_COUNT-1:0]            level3_valid;
                wire [L3_COUNT-1:0]            level3_ready;
                wire [L3_COUNT-1:0]            level3_last;

                aer_spatial_selector_level #(
                    .INPUT_ROWS(L2_ROWS),
                    .INPUT_COLS(L2_COLS),
                    .GROUP_ROWS(GROUP_ROWS),
                    .GROUP_COLS(GROUP_COLS),
                    .DATA_WIDTH(DATA_WIDTH)
                ) level3_i (
                    .clk           (clk),
                    .rst_n         (rst_n),
                    .in_data_flat  (level2_data),
                    .in_valid      (level2_valid),
                    .in_last       (level2_last),
                    .in_ready      (level2_ready),
                    .out_data_flat (level3_data),
                    .out_valid     (level3_valid),
                    .out_ready     (level3_ready),
                    .out_last      (level3_last)
                );

                if (L3_COUNT == 1) begin : gen_root_at_level3
                    assign level3_ready[0] = out_ready;
                    assign out_data = level3_data[0 +: DATA_WIDTH];
                    assign out_valid = level3_valid[0];
                    assign out_last = level3_last[0];
                end else begin : gen_level4
                    wire [L4_COUNT*DATA_WIDTH-1:0] level4_data;
                    wire [L4_COUNT-1:0]            level4_valid;
                    wire [L4_COUNT-1:0]            level4_ready;
                    wire [L4_COUNT-1:0]            level4_last;

                    aer_spatial_selector_level #(
                        .INPUT_ROWS(L3_ROWS),
                        .INPUT_COLS(L3_COLS),
                        .GROUP_ROWS(GROUP_ROWS),
                        .GROUP_COLS(GROUP_COLS),
                        .DATA_WIDTH(DATA_WIDTH)
                    ) level4_i (
                        .clk           (clk),
                        .rst_n         (rst_n),
                        .in_data_flat  (level3_data),
                        .in_valid      (level3_valid),
                        .in_last       (level3_last),
                        .in_ready      (level3_ready),
                        .out_data_flat (level4_data),
                        .out_valid     (level4_valid),
                        .out_ready     (level4_ready),
                        .out_last      (level4_last)
                    );

                    assign level4_ready[0] = out_ready;
                    assign out_data = level4_data[0 +: DATA_WIDTH];
                    assign out_valid = level4_valid[0];
                    assign out_last = level4_last[0];

                    initial begin
                        if (L4_COUNT != 1) begin
                            $display("AER_SELECTOR_TREE_TOO_LARGE rows=%0d cols=%0d group=%0dx%0d",
                                INPUT_ROWS, INPUT_COLS, GROUP_ROWS, GROUP_COLS);
                            $fatal(1);
                        end
                    end
                end
            end
        end
    endgenerate

    initial begin
        if ((INPUT_ROWS < 1) || (INPUT_COLS < 1) ||
            (GROUP_ROWS < 2) || (GROUP_COLS < 2)) begin
            $display("AER_SELECTOR_TREE_BAD_PARAMETERS");
            $fatal(1);
        end
    end

endmodule
