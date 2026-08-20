`timescale 1ns/1ps

module aer_global_bank_selector #(
    parameter integer BANK_ROWS       = 16,
    parameter integer BANK_COLS       = 16,
    parameter integer ROW_INDEX_WIDTH = 4,
    parameter integer COL_INDEX_WIDTH = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [BANK_ROWS*BANK_COLS*16-1:0] bank_data_flat,
    input  wire [BANK_ROWS*BANK_COLS-1:0]    bank_valid,
    input  wire [BANK_ROWS*BANK_COLS-1:0]    bank_last,
    output reg  [BANK_ROWS*BANK_COLS-1:0]    bank_ready,
    output reg  [15:0]                       out_data,
    output reg                               out_valid,
    input  wire                              out_ready,
    output reg                               out_last
);

    localparam integer BANK_COUNT = BANK_ROWS * BANK_COLS;

    localparam integer BANK_INDEX_WIDTH = ROW_INDEX_WIDTH + COL_INDEX_WIDTH;

    wire [BANK_COUNT-1:0] grant;
    wire                  grant_valid;
    wire [BANK_INDEX_WIDTH-1:0] grant_index;
    wire advance;
    integer selected_bank_index;

    // Banks are flattened in row-major order:
    // bank_index = bank_row * BANK_COLS + bank_col.
    // The locked RR encoder searches from the current pointer and therefore
    // skips every empty bank without spending a clock on it.
    aer_locked_rr_arbiter #(
        .REQUESTS(BANK_COUNT),
        .INDEX_WIDTH(BANK_INDEX_WIDTH)
    ) bank_arbiter_i (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (bank_valid),
        .advance     (advance),
        .grant       (grant),
        .grant_valid (grant_valid),
        .grant_index (grant_index)
    );

    always @* begin
        selected_bank_index = grant_index;
        bank_ready = {BANK_COUNT{1'b0}};
        out_data   = 16'b0;
        out_valid  = 1'b0;
        out_last   = 1'b0;

        if (grant_valid) begin
            out_data  = bank_data_flat[selected_bank_index*16 +: 16];
            out_valid = bank_valid[selected_bank_index];
            out_last  = bank_last[selected_bank_index];
            bank_ready[selected_bank_index] = out_ready;
        end
    end

    assign advance = out_valid && out_ready && out_last;

endmodule
