`timescale 1ns/1ps

module tb_aer_bank_fair_pair;

    reg          clk;
    reg          rst_n;
    reg  [15:0]  tile_in_valid;
    reg  [63:0]  tile_on_flat;
    reg  [63:0]  tile_off_flat;
    reg  [15:0]  time_now;
    reg          out_ready;

    wire [15:0] adaptive_tile_in_ready;
    wire [15:0] adaptive_out_data;
    wire        adaptive_out_valid;
    wire        adaptive_out_last;
    wire [15:0] adaptive_pending;

    wire [15:0] raw_tile_in_ready;
    wire [15:0] raw_out_data;
    wire        raw_out_valid;
    wire        raw_out_last;
    wire [15:0] raw_pending;

    aer_bank_row_reader #(
        .BANK_ID(8'hA5),
        .ENABLE_BINNING(1)
    ) adaptive_bank_i (
        .clk           (clk),
        .rst_n         (rst_n),
        .tile_in_valid (tile_in_valid),
        .tile_on_flat  (tile_on_flat),
        .tile_off_flat (tile_off_flat),
        .tile_in_ready (adaptive_tile_in_ready),
        .time_now      (time_now),
        .out_data      (adaptive_out_data),
        .out_valid     (adaptive_out_valid),
        .out_ready     (out_ready),
        .out_last      (adaptive_out_last),
        .pending_debug (adaptive_pending)
    );

    aer_bank_row_reader #(
        .BANK_ID(8'hA5),
        .ENABLE_BINNING(0)
    ) raw_bank_i (
        .clk           (clk),
        .rst_n         (rst_n),
        .tile_in_valid (tile_in_valid),
        .tile_on_flat  (tile_on_flat),
        .tile_off_flat (tile_off_flat),
        .tile_in_ready (raw_tile_in_ready),
        .time_now      (time_now),
        .out_data      (raw_out_data),
        .out_valid     (raw_out_valid),
        .out_ready     (out_ready),
        .out_last      (raw_out_last),
        .pending_debug (raw_pending)
    );

    always #5 clk = ~clk;

    task expect_pair_transfer;
        input [15:0] expected_adaptive_data;
        input [15:0] expected_raw_data;
        input        expected_last;
        integer timeout;
        begin
            timeout = 0;
            while (timeout < 50) begin
                @(posedge clk);

                if ((adaptive_tile_in_ready !== raw_tile_in_ready) ||
                    (adaptive_pending !== raw_pending) ||
                    (adaptive_out_valid !== raw_out_valid) ||
                    (adaptive_out_last !== raw_out_last)) begin
                    $display("FAIR_CONTROL_MISMATCH ready=%h/%h pending=%h/%h valid=%b/%b last=%b/%b",
                        adaptive_tile_in_ready, raw_tile_in_ready,
                        adaptive_pending, raw_pending,
                        adaptive_out_valid, raw_out_valid,
                        adaptive_out_last, raw_out_last);
                    $fatal(1);
                end

                if (adaptive_out_valid && out_ready) begin
                    if ((adaptive_out_data !== expected_adaptive_data) ||
                        (raw_out_data !== expected_raw_data) ||
                        (adaptive_out_last !== expected_last)) begin
                        $display("FAIR_DATA_FAIL adaptive=%h raw=%h last=%b expected=%h/%h/%b",
                            adaptive_out_data, raw_out_data, adaptive_out_last,
                            expected_adaptive_data, expected_raw_data,
                            expected_last);
                        $fatal(1);
                    end
                    timeout = 1000;
                end else begin
                    timeout = timeout + 1;
                end
            end
            if (timeout != 1000) begin
                $display("FAIR_PAIR_TIMEOUT adaptive=%h raw=%h",
                    expected_adaptive_data, expected_raw_data);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk           = 1'b0;
        rst_n         = 1'b0;
        tile_in_valid = 16'b0;
        tile_on_flat  = 64'b0;
        tile_off_flat = 64'b0;
        time_now      = 16'b0;
        out_ready     = 1'b1;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Same mixed-format row enters both structures in one capture.  The
        // adaptive side uses BIN4 then GROUP3, so this case intentionally does
        // not trigger the two-BIN packing optimization.
        time_now = 16'd100;
        tile_on_flat[1*4 +: 4] = 4'b1111;
        tile_on_flat[3*4 +: 4] = 4'b1110;
        tile_in_valid[1] = 1'b1;
        tile_in_valid[3] = 1'b1;
        @(posedge clk);

        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat  = 64'b0;

        // Header, timestamp, handshake, and word count must be identical.
        expect_pair_transfer(16'hE94A, 16'hE94A, 1'b0);
        expect_pair_transfer(16'd100, 16'd100, 1'b0);
        // Only the DATA representation is allowed to differ.
        expect_pair_transfer(16'h8100, 16'h03C0, 1'b0);
        expect_pair_transfer(16'h4200, 16'h0380, 1'b1);

        $display("AER_BANK_FAIR_PAIR_PASS words_adaptive=4 words_raw=4");
        $finish;
    end

endmodule
