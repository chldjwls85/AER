`timescale 1ns/1ps

module tb_aer_pixel_pending_array_depth2;
    localparam integer SENSOR_ROWS = 8;
    localparam integer SENSOR_COLS = 8;
    localparam integer PIXEL_COUNT = SENSOR_ROWS * SENSOR_COLS;
    localparam integer TILE_COUNT = (SENSOR_ROWS/2) * (SENSOR_COLS/2);

    reg clk;
    reg rst_n;
    reg [PIXEL_COUNT-1:0] event_on;
    reg [PIXEL_COUNT-1:0] event_off;
    reg [TILE_COUNT-1:0] tile_ready;
    wire [TILE_COUNT-1:0] tile_valid;
    wire [TILE_COUNT*4-1:0] tile_on_flat;
    wire [TILE_COUNT*4-1:0] tile_off_flat;
    wire [31:0] accepted_event_count;
    wire [31:0] ignored_event_count;
    wire [31:0] readout_event_count;

    aer_pixel_pending_array #(
        .SENSOR_ROWS(SENSOR_ROWS),
        .SENSOR_COLS(SENSOR_COLS),
        .PIXEL_FIFO_DEPTH(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .event_on(event_on),
        .event_off(event_off),
        .tile_valid(tile_valid),
        .tile_on_flat(tile_on_flat),
        .tile_off_flat(tile_off_flat),
        .tile_ready(tile_ready),
        .accepted_event_count(accepted_event_count),
        .ignored_event_count(ignored_event_count),
        .readout_event_count(readout_event_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task drive_pixel0;
        input drive_on;
        input drive_off;
        input drive_ready;
        begin
            @(negedge clk);
            event_on = {PIXEL_COUNT{1'b0}};
            event_off = {PIXEL_COUNT{1'b0}};
            tile_ready = {TILE_COUNT{1'b0}};
            event_on[0] = drive_on;
            event_off[0] = drive_off;
            tile_ready[0] = drive_ready;
            @(posedge clk);
            #1;
        end
    endtask

    task expect_state;
        input [31:0] accepted;
        input [31:0] ignored;
        input [31:0] readout;
        input expected_on;
        input expected_off;
        begin
            if ((accepted_event_count !== accepted) ||
                (ignored_event_count !== ignored) ||
                (readout_event_count !== readout) ||
                (tile_on_flat[0] !== expected_on) ||
                (tile_off_flat[0] !== expected_off)) begin
                $display("AER_PIXEL_PENDING_DEPTH2_FAIL accepted=%0d ignored=%0d readout=%0d on=%0b off=%0b",
                    accepted_event_count, ignored_event_count,
                    readout_event_count, tile_on_flat[0], tile_off_flat[0]);
                $fatal(1);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        event_on = {PIXEL_COUNT{1'b0}};
        event_off = {PIXEL_COUNT{1'b0}};
        tile_ready = {TILE_COUNT{1'b0}};
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Head=ON, then Tail=OFF.  A third event is rejected while both slots
        // are occupied.
        drive_pixel0(1'b1, 1'b0, 1'b0);
        expect_state(1, 0, 0, 1'b1, 1'b0);
        drive_pixel0(1'b0, 1'b1, 1'b0);
        expect_state(2, 0, 0, 1'b1, 1'b0);
        drive_pixel0(1'b1, 1'b0, 1'b0);
        expect_state(2, 1, 0, 1'b1, 1'b0);

        // Pop promotes the tail without reordering it.
        drive_pixel0(1'b0, 1'b0, 1'b1);
        expect_state(2, 1, 1, 1'b0, 1'b1);

        // A pop and new arrival in one cycle retain full throughput.
        drive_pixel0(1'b1, 1'b0, 1'b1);
        expect_state(3, 1, 2, 1'b1, 1'b0);
        drive_pixel0(1'b0, 1'b0, 1'b1);
        expect_state(3, 1, 3, 1'b0, 1'b0);

        // Simultaneous ON/OFF has no defined order, so ON is retained and the
        // other event is accounted as ignored.
        drive_pixel0(1'b1, 1'b1, 1'b0);
        expect_state(4, 2, 3, 1'b1, 1'b0);
        drive_pixel0(1'b0, 1'b0, 1'b1);
        expect_state(4, 2, 4, 1'b0, 1'b0);

        $display("AER_PIXEL_PENDING_DEPTH2_PASS accepted=%0d ignored=%0d readout=%0d",
            accepted_event_count, ignored_event_count, readout_event_count);
        $finish;
    end
endmodule
