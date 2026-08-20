`timescale 1ns/1ps

module aer_locked_rr_arbiter #(
    parameter integer REQUESTS    = 4,
    parameter integer INDEX_WIDTH = 2
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [REQUESTS-1:0]    request,
    input  wire                   advance,
    output reg  [REQUESTS-1:0]    grant,
    output reg                    grant_valid,
    output reg  [INDEX_WIDTH-1:0] grant_index
);

    reg [INDEX_WIDTH-1:0] pointer;
    reg [INDEX_WIDTH-1:0] selected_index;
    reg                   locked;

    integer offset;
    integer candidate;
    reg     candidate_valid;
    reg [INDEX_WIDTH-1:0] candidate_index;

    always @* begin
        candidate_valid = 1'b0;
        candidate_index = {INDEX_WIDTH{1'b0}};
        candidate       = 0;

        for (offset = 0; offset < REQUESTS; offset = offset + 1) begin
            candidate = pointer + offset;
            if (candidate >= REQUESTS)
                candidate = candidate - REQUESTS;

            if (!candidate_valid && request[candidate]) begin
                candidate_valid = 1'b1;
                candidate_index = candidate[INDEX_WIDTH-1:0];
            end
        end
    end

    always @* begin
        grant       = {REQUESTS{1'b0}};
        grant_valid = locked;
        grant_index = selected_index;
        if (locked)
            grant[selected_index] = 1'b1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pointer        <= {INDEX_WIDTH{1'b0}};
            selected_index <= {INDEX_WIDTH{1'b0}};
            locked         <= 1'b0;
        end else begin
            if (!locked && candidate_valid) begin
                selected_index <= candidate_index;
                locked         <= 1'b1;
            end else if (locked && advance) begin
                if (selected_index == REQUESTS - 1)
                    pointer <= {INDEX_WIDTH{1'b0}};
                else
                    pointer <= selected_index + 1'b1;
                locked <= 1'b0;
            end
        end
    end

endmodule
