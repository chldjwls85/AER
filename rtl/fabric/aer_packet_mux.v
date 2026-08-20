`timescale 1ns/1ps

// Multiplexes packet streams and holds the chosen input until in_last is sent.
module aer_packet_mux #(
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
    wire grant_valid;
    wire [INDEX_WIDTH-1:0] grant_index;
    wire advance;
    integer selected_stream;

    aer_packet_rr_arbiter #(
        .REQUESTS(STREAMS),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) arbiter_i (
        .clk(clk),
        .rst_n(rst_n),
        .request(in_valid),
        .advance(advance),
        .grant(grant),
        .grant_valid(grant_valid),
        .grant_index(grant_index)
    );

    always @* begin
        selected_stream = grant_index;
        in_ready = {STREAMS{1'b0}};
        out_data = {DATA_WIDTH{1'b0}};
        out_valid = 1'b0;
        out_last = 1'b0;
        if (grant_valid) begin
            out_data = in_data_flat[selected_stream*DATA_WIDTH +: DATA_WIDTH];
            out_valid = in_valid[selected_stream];
            out_last = in_last[selected_stream];
            in_ready[selected_stream] = out_ready;
        end
    end

    assign advance = out_valid && out_ready && out_last;
endmodule
