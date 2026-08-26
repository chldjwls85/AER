`timescale 1ns/1ps

// One or two event slots per sensor pixel.  Events are kept in arrival order
// until their 2x2 tile is accepted by the readout hierarchy.  A tile handshake
// pops one head event from every active pixel in that tile.
module aer_pixel_pending_array #(
    parameter integer SENSOR_ROWS = 128,
    parameter integer SENSOR_COLS = 128,
    parameter integer PIXEL_FIFO_DEPTH = 1
) (
    input  wire                                    clk,
    input  wire                                    rst_n,
    input  wire [SENSOR_ROWS*SENSOR_COLS-1:0]     event_on,
    input  wire [SENSOR_ROWS*SENSOR_COLS-1:0]     event_off,
    output wire [(SENSOR_ROWS/2)*(SENSOR_COLS/2)-1:0] tile_valid,
    output wire [(SENSOR_ROWS/2)*(SENSOR_COLS/2)*4-1:0] tile_on_flat,
    output wire [(SENSOR_ROWS/2)*(SENSOR_COLS/2)*4-1:0] tile_off_flat,
    input  wire [(SENSOR_ROWS/2)*(SENSOR_COLS/2)-1:0] tile_ready,
    output reg  [31:0]                             accepted_event_count,
    output reg  [31:0]                             ignored_event_count,
    output reg  [31:0]                             readout_event_count
);

    localparam integer PIXEL_COUNT = SENSOR_ROWS * SENSOR_COLS;
    localparam integer TILE_COLS = SENSOR_COLS / 2;
    localparam integer BANK_COLS = SENSOR_COLS / 8;

    reg [PIXEL_COUNT-1:0] head_valid;
    reg [PIXEL_COUNT-1:0] head_polarity;
    reg [PIXEL_COUNT-1:0] tail_valid;
    reg [PIXEL_COUNT-1:0] tail_polarity;
    wire [PIXEL_COUNT-1:0] clear_pixel;
    wire [PIXEL_COUNT-1:0] pop_pixel;

    reg [PIXEL_COUNT-1:0] accept_event;

    integer pixel_index;
    integer new_events_this_cycle;
    integer ignored_this_cycle;
    integer readout_this_cycle;

    genvar pixel_y;
    genvar pixel_x;
    generate
        for (pixel_y = 0; pixel_y < SENSOR_ROWS; pixel_y = pixel_y + 1) begin : gen_y
            for (pixel_x = 0; pixel_x < SENSOR_COLS; pixel_x = pixel_x + 1) begin : gen_x
                localparam integer PIXEL = pixel_y * SENSOR_COLS + pixel_x;
                localparam integer TILE_X = pixel_x / 2;
                localparam integer TILE_Y = pixel_y / 2;
                localparam integer BANK_ID = (TILE_Y / 4) * BANK_COLS + (TILE_X / 4);
                localparam integer LOCAL_TILE = (TILE_Y % 4) * 4 + (TILE_X % 4);
                localparam integer TILE = BANK_ID * 16 + LOCAL_TILE;
                localparam integer BIT = (pixel_y % 2) * 2 + (pixel_x % 2);

                assign tile_on_flat[TILE*4 + BIT] =
                    head_valid[PIXEL] && head_polarity[PIXEL];
                assign tile_off_flat[TILE*4 + BIT] =
                    head_valid[PIXEL] && !head_polarity[PIXEL];
                assign clear_pixel[PIXEL] = tile_valid[TILE] && tile_ready[TILE];
                assign pop_pixel[PIXEL] = clear_pixel[PIXEL] && head_valid[PIXEL];
            end
        end
    endgenerate

    genvar tile_y;
    genvar tile_x;
    generate
        for (tile_y = 0; tile_y < SENSOR_ROWS/2; tile_y = tile_y + 1) begin : gen_tile_y
            for (tile_x = 0; tile_x < SENSOR_COLS/2; tile_x = tile_x + 1) begin : gen_tile_x
                localparam integer BANK_ID = (tile_y / 4) * BANK_COLS + (tile_x / 4);
                localparam integer LOCAL_TILE = (tile_y % 4) * 4 + (tile_x % 4);
                localparam integer TILE = BANK_ID * 16 + LOCAL_TILE;
                assign tile_valid[TILE] =
                    |tile_on_flat[TILE*4 +: 4] | |tile_off_flat[TILE*4 +: 4];
            end
        end
    endgenerate

    always @* begin
        new_events_this_cycle = 0;
        ignored_this_cycle = 0;
        readout_this_cycle = 0;
        accept_event = {PIXEL_COUNT{1'b0}};
        for (pixel_index = 0; pixel_index < PIXEL_COUNT;
             pixel_index = pixel_index + 1) begin
            if (pop_pixel[pixel_index])
                readout_this_cycle = readout_this_cycle + 1;
            if (event_on[pixel_index] || event_off[pixel_index]) begin
                if (((PIXEL_FIFO_DEPTH == 1) &&
                     (!head_valid[pixel_index] || pop_pixel[pixel_index])) ||
                    ((PIXEL_FIFO_DEPTH == 2) &&
                     (!tail_valid[pixel_index] || pop_pixel[pixel_index]))) begin
                    accept_event[pixel_index] = 1'b1;
                    new_events_this_cycle = new_events_this_cycle + 1;
                    if (event_on[pixel_index] && event_off[pixel_index])
                        ignored_this_cycle = ignored_this_cycle + 1;
                end else begin
                    if (event_on[pixel_index])
                        ignored_this_cycle = ignored_this_cycle + 1;
                    if (event_off[pixel_index])
                        ignored_this_cycle = ignored_this_cycle + 1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            head_valid           <= {PIXEL_COUNT{1'b0}};
            head_polarity        <= {PIXEL_COUNT{1'b0}};
            tail_valid           <= {PIXEL_COUNT{1'b0}};
            tail_polarity        <= {PIXEL_COUNT{1'b0}};
            accepted_event_count <= 32'd0;
            ignored_event_count  <= 32'd0;
            readout_event_count  <= 32'd0;
        end else begin
            accepted_event_count <= accepted_event_count + new_events_this_cycle;
            ignored_event_count  <= ignored_event_count + ignored_this_cycle;
            readout_event_count  <= readout_event_count + readout_this_cycle;
            for (pixel_index = 0; pixel_index < PIXEL_COUNT;
                 pixel_index = pixel_index + 1) begin
                if (PIXEL_FIFO_DEPTH == 1) begin
                    if (pop_pixel[pixel_index])
                        head_valid[pixel_index] <= 1'b0;
                    if (accept_event[pixel_index]) begin
                        head_valid[pixel_index] <= 1'b1;
                        // ON wins an unorderable simultaneous ON/OFF conflict.
                        head_polarity[pixel_index] <= event_on[pixel_index];
                    end
                    tail_valid[pixel_index] <= 1'b0;
                end else begin
                    case ({pop_pixel[pixel_index], accept_event[pixel_index]})
                        2'b01: begin
                            if (!head_valid[pixel_index]) begin
                                head_valid[pixel_index] <= 1'b1;
                                head_polarity[pixel_index] <= event_on[pixel_index];
                            end else begin
                                tail_valid[pixel_index] <= 1'b1;
                                tail_polarity[pixel_index] <= event_on[pixel_index];
                            end
                        end
                        2'b10: begin
                            if (tail_valid[pixel_index]) begin
                                head_valid[pixel_index] <= 1'b1;
                                head_polarity[pixel_index] <= tail_polarity[pixel_index];
                                tail_valid[pixel_index] <= 1'b0;
                            end else begin
                                head_valid[pixel_index] <= 1'b0;
                            end
                        end
                        2'b11: begin
                            if (tail_valid[pixel_index]) begin
                                head_valid[pixel_index] <= 1'b1;
                                head_polarity[pixel_index] <= tail_polarity[pixel_index];
                                tail_valid[pixel_index] <= 1'b1;
                                tail_polarity[pixel_index] <= event_on[pixel_index];
                            end else begin
                                head_valid[pixel_index] <= 1'b1;
                                head_polarity[pixel_index] <= event_on[pixel_index];
                                tail_valid[pixel_index] <= 1'b0;
                            end
                        end
                        default: begin
                        end
                    endcase
                end
            end
        end
    end

    initial begin
        if ((SENSOR_ROWS % 8) != 0 || (SENSOR_COLS % 8) != 0) begin
            $display("AER_PIXEL_PENDING_BAD_SENSOR_SIZE rows=%0d cols=%0d",
                SENSOR_ROWS, SENSOR_COLS);
            $fatal(1);
        end
        if (TILE_COLS != SENSOR_COLS/2) begin
            $display("AER_PIXEL_PENDING_INTERNAL_GEOMETRY_FAIL");
            $fatal(1);
        end
        if ((PIXEL_FIFO_DEPTH != 1) && (PIXEL_FIFO_DEPTH != 2)) begin
            $display("AER_PIXEL_PENDING_BAD_DEPTH depth=%0d", PIXEL_FIFO_DEPTH);
            $fatal(1);
        end
    end

endmodule
