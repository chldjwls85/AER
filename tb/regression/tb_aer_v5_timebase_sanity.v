`timescale 1ns/1ps

module tb_aer_v5_timebase_sanity;
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

    integer region_index;
    integer error_count;
    reg [15:0] expected_time;

    aer_top_v5_128 dut (
        .clk(clk),
        .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat),
        .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_last(out_last)
    );

    task check_all_regions;
        input [15:0] expected;
        begin
            for (region_index = 0; region_index < 16;
                 region_index = region_index + 1) begin
                if (dut.top_i.regional_time_flat[region_index*16 +: 16]
                    !== expected) begin
                    $display("AER_V5_TIMEBASE_MISMATCH region=%0d expected=%04h actual=%04h time=%0t",
                             region_index,
                             expected,
                             dut.top_i.regional_time_flat[region_index*16 +: 16],
                             $time);
                    error_count = error_count + 1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        tile_in_valid = 4096'b0;
        tile_on_flat = 16384'b0;
        tile_off_flat = 16384'b0;
        out_ready = 1'b1;
        error_count = 0;
        expected_time = 16'h0000;

        // Initial synchronous reset: every regional counter must be zero.
        repeat (2) begin
            @(posedge clk);
            #1;
            check_all_regions(16'h0000);
        end

        // All counters must increment in lock-step for at least 64 cycles.
        @(negedge clk);
        rst_n = 1'b1;
        expected_time = 16'h0000;
        repeat (64) begin
            @(posedge clk);
            #1;
            expected_time = expected_time + 16'h0001;
            check_all_regions(expected_time);
        end

        // Re-assert reset during operation and check synchronous clearing.
        @(negedge clk);
        rst_n = 1'b0;
        repeat (2) begin
            @(posedge clk);
            #1;
            check_all_regions(16'h0000);
        end

        // Release reset again and confirm lock-step increment resumes.
        @(negedge clk);
        rst_n = 1'b1;
        expected_time = 16'h0000;
        repeat (16) begin
            @(posedge clk);
            #1;
            expected_time = expected_time + 16'h0001;
            check_all_regions(expected_time);
        end

        if (error_count == 0) begin
            $display("AER_V5_TIMEBASE_SANITY_PASS");
            $finish;
        end else begin
            $display("AER_V5_TIMEBASE_SANITY_FAIL errors=%0d", error_count);
            $fatal(1);
        end
    end
endmodule
