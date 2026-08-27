`timescale 1ns/1ps

// Minimal classifier for the fixed CARE-AER combined mode.
//
// Unlike aer_tile_bitmap_encoder, this block does not build a second payload
// copy.  The optimized bank reader stores RAW8 once and keeps only the masks
// needed by the SPARSE/lossy policy.
module aer_tile_combined_classifier (
    input  wire [3:0] on_bitmap,
    input  wire [3:0] off_bitmap,
    output wire       has_event,
    output wire       bin_candidate,
    output wire       lossy_candidate,
    output wire       bin_polarity,
    output reg        sparse_candidate,
    output reg  [2:0] sparse_payload
);

    wire conflict;
    wire no_on;
    wire no_off;
    wire on_full;
    wire off_full;
    wire on_group3;
    wire off_group3;

    reg [1:0] sparse_pixel;

    assign has_event = |on_bitmap || |off_bitmap;
    assign conflict  = |(on_bitmap & off_bitmap);
    assign no_on     = !(|on_bitmap);
    assign no_off    = !(|off_bitmap);
    assign on_full   = (&on_bitmap) && no_off;
    assign off_full  = (&off_bitmap) && no_on;

    assign on_group3 = no_off && (
        (on_bitmap == 4'b1110) ||
        (on_bitmap == 4'b1101) ||
        (on_bitmap == 4'b1011) ||
        (on_bitmap == 4'b0111)
    );

    assign off_group3 = no_on && (
        (off_bitmap == 4'b1110) ||
        (off_bitmap == 4'b1101) ||
        (off_bitmap == 4'b1011) ||
        (off_bitmap == 4'b0111)
    );

    assign bin_candidate = !conflict &&
                           (on_full || off_full || on_group3 || off_group3);
    assign lossy_candidate = !conflict && (on_group3 || off_group3);
    assign bin_polarity  = on_full || on_group3;

    always @* begin
        sparse_candidate = 1'b0;
        sparse_payload = 3'b0;
        sparse_pixel = 2'b0;

        case (on_bitmap)
            4'b0001: sparse_pixel = 2'd0;
            4'b0010: sparse_pixel = 2'd1;
            4'b0100: sparse_pixel = 2'd2;
            4'b1000: sparse_pixel = 2'd3;
            default: sparse_pixel = 2'd0;
        endcase

        if (!conflict && no_off &&
            ((on_bitmap == 4'b0001) ||
             (on_bitmap == 4'b0010) ||
             (on_bitmap == 4'b0100) ||
             (on_bitmap == 4'b1000))) begin
            sparse_candidate = 1'b1;
            sparse_payload = {sparse_pixel, 1'b1};
        end else begin
            case (off_bitmap)
                4'b0001: sparse_pixel = 2'd0;
                4'b0010: sparse_pixel = 2'd1;
                4'b0100: sparse_pixel = 2'd2;
                4'b1000: sparse_pixel = 2'd3;
                default: sparse_pixel = 2'd0;
            endcase

            if (!conflict && no_on &&
                ((off_bitmap == 4'b0001) ||
                 (off_bitmap == 4'b0010) ||
                 (off_bitmap == 4'b0100) ||
                 (off_bitmap == 4'b1000))) begin
                sparse_candidate = 1'b1;
                sparse_payload = {sparse_pixel, 1'b0};
            end
        end
    end

endmodule
