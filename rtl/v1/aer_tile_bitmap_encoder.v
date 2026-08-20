`timescale 1ns/1ps

module aer_tile_bitmap_encoder (
    input  wire [3:0] on_bitmap,
    input  wire [3:0] off_bitmap,
    output wire       has_event,
    output reg  [1:0] format,
    output reg  [7:0] payload,
    output reg  [1:0] flags
);

    localparam [1:0] FORMAT_RAW8   = 2'b00;
    localparam [1:0] FORMAT_GROUP3 = 2'b01;
    localparam [1:0] FORMAT_BIN4   = 2'b10;

    wire conflict;
    wire no_on;
    wire no_off;
    wire on_full;
    wire off_full;
    wire on_group3;
    wire off_group3;

    reg [1:0] missing_pixel;
    reg [3:0] active_bitmap;

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

    always @* begin
        active_bitmap = on_group3 ? on_bitmap : off_bitmap;
        case (~active_bitmap)
            4'b0001: missing_pixel = 2'd0;
            4'b0010: missing_pixel = 2'd1;
            4'b0100: missing_pixel = 2'd2;
            4'b1000: missing_pixel = 2'd3;
            default: missing_pixel = 2'd0;
        endcase
    end

    always @* begin
        format  = FORMAT_RAW8;
        payload = {on_bitmap, off_bitmap};
        // flags[1] marks an ON/OFF conflict in the same pixel.
        flags   = {conflict, 1'b0};

        if (!conflict && (on_full || off_full)) begin
            format  = FORMAT_BIN4;
            // payload[7]: 1=ON, 0=OFF. Count is implicitly four.
            payload = {on_full, 7'b0};
            flags   = 2'b00;
        end else if (!conflict && (on_group3 || off_group3)) begin
            format  = FORMAT_GROUP3;
            // payload[7]: polarity, payload[6:5]: missing pixel index.
            payload = {on_group3, missing_pixel, 5'b0};
            flags   = 2'b00;
        end
    end

endmodule
