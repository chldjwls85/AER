`timescale 1ns/1ps

module aer_raw_packetizer (
    input  wire [9:0]  coordinate_x,
    input  wire [9:0]  coordinate_y,
    input  wire        polarity,
    input  wire [7:0]  event_time,
    input  wire        status_flag,
    output wire [31:0] packet
);

    // [31:30] type, [29:20] x, [19:10] y, [9] polarity,
    // [8:1] time modulo 256, [0] reserved status flag.
    assign packet = {
        2'b00,
        coordinate_x,
        coordinate_y,
        polarity,
        event_time,
        status_flag
    };

endmodule
