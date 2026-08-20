`timescale 1ns/1ps

module aer_rr_arbiter #(
    parameter integer REQUESTS    = 4,
    parameter integer INDEX_WIDTH = 2
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [REQUESTS-1:0]       request,
    input  wire                      advance,
    output reg  [REQUESTS-1:0]       grant,
    output reg                       grant_valid,
    output reg  [INDEX_WIDTH-1:0]    grant_index
);

    reg [INDEX_WIDTH-1:0] pointer;
    integer offset;
    integer candidate;
    reg found;

    always @* begin
        grant       = {REQUESTS{1'b0}};
        grant_valid = 1'b0;
        grant_index = {INDEX_WIDTH{1'b0}};
        found       = 1'b0;
        candidate   = 0;

        for (offset = 0; offset < REQUESTS; offset = offset + 1) begin
            candidate = pointer + offset;
            if (candidate >= REQUESTS)
                candidate = candidate - REQUESTS;

            if (!found && request[candidate]) begin
                grant[candidate] = 1'b1;
                grant_index      = candidate[INDEX_WIDTH-1:0];
                grant_valid      = 1'b1;
                found            = 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pointer <= {INDEX_WIDTH{1'b0}};
        end else if (advance && grant_valid) begin
            if (grant_index == REQUESTS - 1)
                pointer <= {INDEX_WIDTH{1'b0}};
            else
                pointer <= grant_index + {{(INDEX_WIDTH-1){1'b0}}, 1'b1};
        end
    end

endmodule
