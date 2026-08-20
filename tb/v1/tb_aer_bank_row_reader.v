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

    reg [15:0] captured_data [0:31];
    reg        captured_last [0:31];
    integer    captured_cycle [0:31];
    integer    transfer_count;
    integer    cycle_count;
    integer    timeout;
    integer    index;

    aer_bank_row_reader #(
        .BANK_ID(16'h00A5)
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

    always @(posedge clk) begin
        if (!rst_n) begin
            transfer_count = 0;
            cycle_count = 0;
        end else begin
            cycle_count = cycle_count + 1;
            if (out_valid && out_ready) begin
                captured_data[transfer_count] = out_data;
                captured_last[transfer_count] = out_last;
                captured_cycle[transfer_count] = cycle_count;
                transfer_count = transfer_count + 1;
            end
        end
    end

    task wait_for_transfers;
        input integer expected_count;
        begin
            timeout = 0;
            while ((transfer_count < expected_count) && (timeout < 100)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (transfer_count != expected_count) begin
                $display("BANK_READER_TIMEOUT got=%0d expected=%0d",
                    transfer_count, expected_count);
                $fatal(1);
            end
        end
    endtask

    task check_transfer;
        input integer transfer_index;
        input [15:0] expected_data;
        input expected_last;
        begin
            if ((captured_data[transfer_index] !== expected_data) ||
                (captured_last[transfer_index] !== expected_last)) begin
                $display("BANK_READER_FAIL index=%0d got=%h/%b expected=%h/%b",
                    transfer_index,
                    captured_data[transfer_index],
                    captured_last[transfer_index],
                    expected_data,
                    expected_last);
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

        // A token accepted together with the look-ahead header is included in
        // the same snapshot.  This one is GROUP3 at t=105.
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;
        time_now = 16'd105;
        tile_on_flat[3*4 +: 4] = 4'b1110;
        tile_in_valid[3] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;

        wait_for_transfers(4);
        check_transfer(0, 16'hE94A, 1'b0);
        check_transfer(1, 16'd100, 1'b0);
        check_transfer(2, 16'h8100, 1'b0);
        check_transfer(3, 16'h5600, 1'b1);

        // Four BIN4 tiles become two packed data words: 16 pixel events use
        // four total words including the row header and base time.
        @(negedge clk);
        time_now = 16'd150;
        tile_on_flat[8*4 +: 4] = 4'b1111;
        tile_off_flat[9*4 +: 4] = 4'b1111;
        tile_on_flat[10*4 +: 4] = 4'b1111;
        tile_off_flat[11*4 +: 4] = 4'b1111;
        tile_in_valid[8] = 1'b1;
        tile_in_valid[9] = 1'b1;
        tile_in_valid[10] = 1'b1;
        tile_in_valid[11] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;
        tile_off_flat = 64'b0;

        wait_for_transfers(8);
        check_transfer(4, 16'hE96F, 1'b0);
        check_transfer(5, 16'd150, 1'b0);
        check_transfer(6, 16'hA100, 1'b0);
        check_transfer(7, 16'hA100, 1'b1);

        // Hold a row packet to verify the 4-bit delta-time guard.
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
        wait_for_transfers(11);
        check_transfer(8, 16'hE951, 1'b0);
        check_transfer(9, 16'd200, 1'b0);
        check_transfer(10, 16'h8000, 1'b1);

        @(negedge clk);
        #1;
        if (tile_in_ready[5] !== 1'b1) begin
            $display("BANK_READER_REARM_FAIL ready=%b pending=%h",
                tile_in_ready[5], pending_debug);
            $fatal(1);
        end

        // Queue two rows together.  Their six words must be emitted on six
        // consecutive cycles, including the packet boundary.
        time_now = 16'd300;
        tile_on_flat[0*4 +: 4] = 4'b1111;
        tile_off_flat[4*4 +: 4] = 4'b1111;
        tile_in_valid[0] = 1'b1;
        tile_in_valid[4] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;
        tile_off_flat = 64'b0;

        wait_for_transfers(17);
        check_transfer(11, 16'hE941, 1'b0);
        check_transfer(12, 16'd300, 1'b0);
        check_transfer(13, 16'h8100, 1'b1);
        check_transfer(14, 16'hE951, 1'b0);
        check_transfer(15, 16'd300, 1'b0);
        check_transfer(16, 16'h8000, 1'b1);

        for (index = 12; index < 17; index = index + 1) begin
            if (captured_cycle[index] != captured_cycle[index-1] + 1) begin
                $display("BANK_READER_BUBBLE_FAIL index=%0d cycles=%0d,%0d",
                    index, captured_cycle[index-1], captured_cycle[index]);
                $fatal(1);
            end
        end

        $display("AER_BANK_ROW_READER_PASS events=16 words=4 zero_bubble=1");
        $finish;
    end

endmodule
