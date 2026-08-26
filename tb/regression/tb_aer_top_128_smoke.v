`timescale 1ns/1ps

// Full 128x128 elaboration/connectivity smoke test.  Events are injected at
// both ends of the bank-major input bus to exercise bank 0 and bank 255.
module tb_aer_top_128_smoke;
    reg clk;
    reg rst_n;
    reg [4095:0] tile_in_valid;
    reg [16383:0] tile_on_flat;
    reg [16383:0] tile_off_flat;
    wire [4095:0] tile_in_ready;
    wire [15:0] out_data;
    wire out_valid;
    reg out_ready;
    wire out_last;

    reg [15:0] packet_words [0:7];
    reg packet_last [0:7];
    integer packet_count;
    integer timeout_count;
    integer done;
    integer errors;
    integer wait_index;

    aer_top_128 dut (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat),
        .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .out_data(out_data), .out_valid(out_valid),
        .out_ready(out_ready), .out_last(out_last)
    );

    always #5 clk = ~clk;

    task drive_tile;
        input [31:0] tile_id;
        input [3:0] on_bits;
        input [3:0] off_bits;
        begin
            @(negedge clk);
            if (!tile_in_ready[tile_id]) begin
                $display("AER_128_SMOKE_FAIL tile %0d not ready", tile_id);
                errors = errors + 1;
            end
            tile_on_flat[tile_id*4 +: 4] = on_bits;
            tile_off_flat[tile_id*4 +: 4] = off_bits;
            tile_in_valid[tile_id] = 1'b1;
            @(negedge clk);
            tile_in_valid[tile_id] = 1'b0;
        end
    endtask

    task capture_packet;
        begin
            packet_count = 0;
            timeout_count = 0;
            done = 0;
            while ((timeout_count < 1000) && (done == 0)) begin
                @(posedge clk);
                if (out_valid && out_ready) begin
                    if (packet_count < 8) begin
                        packet_words[packet_count] = out_data;
                        packet_last[packet_count] = out_last;
                    end else begin
                        $display("AER_128_SMOKE_FAIL packet capture overflow");
                        errors = errors + 1;
                    end
                    packet_count = packet_count + 1;
                    if (out_last)
                        done = 1;
                end
                timeout_count = timeout_count + 1;
            end
            if (done == 0) begin
                $display("AER_128_SMOKE_FAIL packet capture timeout");
                errors = errors + 1;
            end
        end
    endtask

    task check_packet;
        input [31:0] expected_count;
        input [15:0] expected_header;
        input [15:0] expected_data;
        input [31:0] test_number;
        begin
            if (packet_count != expected_count) begin
                $display("AER_128_SMOKE_FAIL TEST%0d expected %0d words, got %0d",
                         test_number, expected_count, packet_count);
                errors = errors + 1;
            end
            if (packet_words[0] !== expected_header) begin
                $display("AER_128_SMOKE_FAIL TEST%0d header expected=%h got=%h",
                         test_number, expected_header, packet_words[0]);
                errors = errors + 1;
            end
            if (packet_words[expected_count-1] !== expected_data) begin
                $display("AER_128_SMOKE_FAIL TEST%0d data expected=%h got=%h",
                         test_number, expected_data, packet_words[expected_count-1]);
                errors = errors + 1;
            end
            if ((packet_last[0] !== 1'b0) ||
                (packet_last[expected_count-1] !== 1'b1)) begin
                $display("AER_128_SMOKE_FAIL TEST%0d out_last placement", test_number);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tile_in_valid = 4096'b0;
        tile_on_flat = 16384'b0;
        tile_off_flat = 16384'b0;
        out_ready = 1'b1;
        errors = 0;

        for (wait_index = 0; wait_index < 4; wait_index = wait_index + 1) begin
            @(posedge clk);
        end
        rst_n = 1'b1;
        for (wait_index = 0; wait_index < 2; wait_index = wait_index + 1) begin
            @(posedge clk);
        end

        // Bank 0, local tile 0 -> row 0, column 0.
        drive_tile(0, 4'b0001, 4'b0000);
        capture_packet;
        check_packet(2, 16'h0001, 16'h0003, 1);

        for (wait_index = 0; wait_index < 4; wait_index = wait_index + 1) begin
            @(posedge clk);
        end

        // Bank 255, local tile 15 -> row 3, column 3.  This checks the final
        // input slices, final region, and full 8-bit bank address.
        drive_tile(4095, 4'b1010, 4'b0101);
        capture_packet;
        check_packet(3, 16'hfff8, 16'h0528, 2);

        if (errors == 0)
            $display("AER_128_SMOKE_PASS packets=2 words=5");
        else
            $display("AER_128_SMOKE_FAIL errors=%0d", errors);

        #20;
        $finish;
    end
endmodule
