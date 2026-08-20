`timescale 1ns/1ps

// Spatially-balanced global readout wrapper.  REGION_ROWS x REGION_COLS limits
// the request encoder and data MUX fan-in at every stage; the tree adds only as
// many registered levels as the configured bank array needs.
module aer_global_bank_selector #(
    parameter integer BANK_ROWS       = 16,
    parameter integer BANK_COLS       = 16,
    parameter integer ROW_INDEX_WIDTH = 4,
    parameter integer COL_INDEX_WIDTH = 4,
    parameter integer REGION_ROWS     = 4,
    parameter integer REGION_COLS     = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [BANK_ROWS*BANK_COLS*16-1:0] bank_data_flat,
    input  wire [BANK_ROWS*BANK_COLS-1:0]    bank_valid,
    input  wire [BANK_ROWS*BANK_COLS-1:0]    bank_last,
    output wire [BANK_ROWS*BANK_COLS-1:0]    bank_ready,
    output wire [15:0]                       out_data,
    output wire                              out_valid,
    input  wire                              out_ready,
    output wire                              out_last
);

    // ROW_INDEX_WIDTH and COL_INDEX_WIDTH remain in the interface for source
    // compatibility.  Tree dimensions now come directly from BANK_ROWS/COLS.
    aer_balanced_selector_tree #(
        .INPUT_ROWS(BANK_ROWS),
        .INPUT_COLS(BANK_COLS),
        .GROUP_ROWS(REGION_ROWS),
        .GROUP_COLS(REGION_COLS),
        .DATA_WIDTH(16)
    ) selector_tree_i (
        .clk          (clk),
        .rst_n        (rst_n),
        .in_data_flat (bank_data_flat),
        .in_valid     (bank_valid),
        .in_last      (bank_last),
        .in_ready     (bank_ready),
        .out_data     (out_data),
        .out_valid    (out_valid),
        .out_ready    (out_ready),
        .out_last     (out_last)
    );

endmodule
