`timescale 1ns/1ps

module tb_aer_bank_row_reader_extended;

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

    reg [15:0] captured [0:3];
    reg [3:0]  captured_last;
    integer    transfer_count;
    integer    timeout;

    aer_bank_row_reader #(
        .BANK_ID(16'h0123),
        .EXTENDED_BANK_ID(1)
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
        end else if (out_valid && out_ready) begin
            captured[transfer_count] = out_data;
            captured_last[transfer_count] = out_last;
            transfer_count = transfer_count + 1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;
        tile_off_flat = 64'b0;
        time_now = 16'b0;
        out_ready = 1'b1;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        time_now = 16'd42;
        tile_on_flat[3:0] = 4'b1111;
        tile_in_valid[0] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;

        timeout = 0;
        while ((transfer_count < 4) && (timeout < 50)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if ((transfer_count != 4) ||
            (captured[0] !== 16'hC8C1) ||
            (captured[1] !== 16'h0001) ||
            (captured[2] !== 16'd42) ||
            (captured[3] !== 16'h8100) ||
            (captured_last !== 4'b1000)) begin
            $display("AER_BANK_EXTENDED_FAIL count=%0d words=%h,%h,%h,%h last=%b",
                transfer_count,
                captured[0], captured[1], captured[2], captured[3],
                captured_last);
            $fatal(1);
        end

        $display("AER_BANK_EXTENDED_PASS bank_id=0123");
        $finish;
    end

endmodule
