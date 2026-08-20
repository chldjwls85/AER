`timescale 1ns/1ps

module tb_aer_bank_row_reader;

    reg          clk;
    reg          rst_n;
    reg  [15:0]  tile_in_valid;
    reg  [63:0]  tile_on_flat;
    reg  [63:0]  tile_off_flat;
    wire [15:0]  tile_in_ready;
    reg  [15:0]  time_now;
    wire [15:0]  out_data;
    wire         out_valid;
    reg          out_ready;
    wire         out_last;
    wire [15:0]  pending_debug;

    aer_bank_row_reader #(
        .BANK_ID(8'hA5)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .tile_in_valid (tile_in_valid),
        .tile_on_flat  (tile_on_flat),
        .tile_off_flat (tile_off_flat),
        .tile_in_ready (tile_in_ready),
        .time_now      (time_now),
        .out_data      (out_data),
        .out_valid     (out_valid),
        .out_ready     (out_ready),
        .out_last      (out_last),
        .pending_debug (pending_debug)
    );

    always #5 clk = ~clk;

    task expect_transfer;
        input [15:0] expected_data;
        input        expected_last;
        integer timeout;
        begin
            timeout = 0;
            while (timeout < 50) begin
                @(posedge clk);
                if (out_valid && out_ready) begin
                    if ((out_data !== expected_data) ||
                        (out_last !== expected_last)) begin
                        $display("BANK_READER_FAIL got=%h/%b expected=%h/%b",
                            out_data, out_last, expected_data, expected_last);
                        $fatal(1);
                    end
                    timeout = 1000;
                end else begin
                    timeout = timeout + 1;
                end
            end
            if (timeout != 1000) begin
                $display("BANK_READER_TIMEOUT expected=%h", expected_data);
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

        // Row 0, column 1: four ON pixels at t=100.
        time_now = 16'd100;
        tile_on_flat[1*4 +: 4] = 4'b1111;
        tile_in_valid[1] = 1'b1;
        @(posedge clk);

        // Row 0, column 3: three ON pixels at t=105.
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat  = 64'b0;
        time_now = 16'd105;
        tile_on_flat[3*4 +: 4] = 4'b1110;
        tile_in_valid[3] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat  = 64'b0;

        // Header: type, bank A5, row 0, valid columns 1010.
        expect_transfer(16'hE94A, 1'b0);
        expect_transfer(16'd100, 1'b0);
        // Column 1 BIN4, delta 0, ON polarity.
        expect_transfer(16'h8200, 1'b0);
        // Column 3 GROUP3, delta 5, ON polarity, missing pixel 0.
        expect_transfer(16'h5600, 1'b1);

        // Hold an old row packet to verify the 4-bit delta-time guard.
        @(negedge clk);
        out_ready = 1'b0;
        time_now = 16'd200;
        tile_off_flat[4*4 +: 4] = 4'b1111;
        tile_in_valid[4] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_off_flat = 64'b0;
        time_now = 16'd216;
        #1;
        if (tile_in_ready[5] !== 1'b0) begin
            $display("BANK_READER_TIME_GUARD_FAIL ready=%b", tile_in_ready[5]);
            $fatal(1);
        end

        out_ready = 1'b1;
        expect_transfer(16'hE951, 1'b0);
        expect_transfer(16'd200, 1'b0);
        expect_transfer(16'h8000, 1'b1);

        @(negedge clk);
        #1;
        if (tile_in_ready[5] !== 1'b1) begin
            $display("BANK_READER_REARM_FAIL ready=%b pending=%h",
                tile_in_ready[5], pending_debug);
            $fatal(1);
        end

        $display("AER_BANK_ROW_READER_PASS");
        $finish;
    end

endmodule
