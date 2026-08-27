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

    reg [REQUESTS-1:0] scan_request;
    reg [INDEX_WIDTH-1:0] scan_pointer;
    reg [INDEX_WIDTH-1:0] next_pointer;

    wire                  candidate_valid;
    wire [INDEX_WIDTH-1:0] candidate_index;

    // Candidate search is allowed to end only at the registered grant state.
    // It never bypasses into the data selector or ready path.
    always @* begin
        if (selected_index == REQUESTS - 1)
            next_pointer = {INDEX_WIDTH{1'b0}};
        else
            next_pointer = selected_index + 1'b1;

        scan_pointer = pointer;
        scan_request = request;
    end

    // The common 16-input case is encoded as four groups of four requests.
    // This avoids a single 16-decision candidate_valid dependency chain.  The
    // generic path remains available for the smaller parameterized arbiters.
    generate
        if (REQUESTS == 16) begin : gen_rr16_tree
            wire [31:0] duplicated_request;
            wire [31:0] shifted_request;
            wire [15:0] rotated_request;
            reg         tree_valid;
            reg [1:0]   group_index;
            reg [1:0]   lane_index;
            reg [4:0]   absolute_index;

            assign duplicated_request = {scan_request, scan_request};
            assign shifted_request = duplicated_request >> scan_pointer;
            assign rotated_request = shifted_request[15:0];

            always @* begin
                tree_valid = |rotated_request;
                group_index = 2'd0;
                lane_index = 2'd0;

                if (|rotated_request[3:0])
                    group_index = 2'd0;
                else if (|rotated_request[7:4])
                    group_index = 2'd1;
                else if (|rotated_request[11:8])
                    group_index = 2'd2;
                else if (|rotated_request[15:12])
                    group_index = 2'd3;

                case (group_index)
                    2'd0: begin
                        if (rotated_request[0]) lane_index = 2'd0;
                        else if (rotated_request[1]) lane_index = 2'd1;
                        else if (rotated_request[2]) lane_index = 2'd2;
                        else lane_index = 2'd3;
                    end
                    2'd1: begin
                        if (rotated_request[4]) lane_index = 2'd0;
                        else if (rotated_request[5]) lane_index = 2'd1;
                        else if (rotated_request[6]) lane_index = 2'd2;
                        else lane_index = 2'd3;
                    end
                    2'd2: begin
                        if (rotated_request[8]) lane_index = 2'd0;
                        else if (rotated_request[9]) lane_index = 2'd1;
                        else if (rotated_request[10]) lane_index = 2'd2;
                        else lane_index = 2'd3;
                    end
                    default: begin
                        if (rotated_request[12]) lane_index = 2'd0;
                        else if (rotated_request[13]) lane_index = 2'd1;
                        else if (rotated_request[14]) lane_index = 2'd2;
                        else lane_index = 2'd3;
                    end
                endcase

                absolute_index = scan_pointer + {group_index, lane_index};
                if (absolute_index >= 16)
                    absolute_index = absolute_index - 16;
            end

            assign candidate_valid = tree_valid;
            assign candidate_index = absolute_index[INDEX_WIDTH-1:0];
        end else begin : gen_rr_generic
            integer offset;
            integer candidate;
            reg generic_valid;
            reg [INDEX_WIDTH-1:0] generic_index;

            always @* begin
                generic_valid = 1'b0;
                generic_index = {INDEX_WIDTH{1'b0}};
                candidate = 0;

                for (offset = 0; offset < REQUESTS;
                     offset = offset + 1) begin
                    candidate = scan_pointer + offset;
                    if (candidate >= REQUESTS)
                        candidate = candidate - REQUESTS;

                    if (!generic_valid && scan_request[candidate]) begin
                        generic_valid = 1'b1;
                        generic_index = candidate[INDEX_WIDTH-1:0];
                    end
                end
            end

            assign candidate_valid = generic_valid;
            assign candidate_index = generic_index;
        end
    endgenerate

    // Grant only from registered state.  The old first-word look-ahead path
    // connected the RR scan, wide selector and downstream ready decode in one
    // cycle.  Registering the decision makes selected_index the timing cut.
    always @* begin
        grant       = {REQUESTS{1'b0}};
        grant_valid = locked;
        grant_index = selected_index;
        if (grant_valid)
            grant[grant_index] = 1'b1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pointer        <= {INDEX_WIDTH{1'b0}};
            selected_index <= {INDEX_WIDTH{1'b0}};
            locked         <= 1'b0;
        end else begin
            if (!locked && candidate_valid) begin
                selected_index <= candidate_index;
                locked <= 1'b1;
            end else if (locked && advance) begin
                pointer <= next_pointer;
                locked <= 1'b0;
            end
        end
    end

endmodule
