`timescale 1ns/1ps

module tb_aer_v1_raw_top_128;

    reg            clk;
    reg            rst_n;
    reg  [4095:0]  tile_in_valid;
    reg  [16383:0] tile_on_flat;
    reg  [16383:0] tile_off_flat;
    wire [4095:0]  tile_in_ready;
    wire [15:0]    out_data;
    wire           out_valid;
    reg            out_ready;
    wire           out_last;

    localparam integer TEST_BANK = 17;
    localparam integer TEST_TILE = 5;
    localparam integer TEST_INDEX = TEST_BANK * 16 + TEST_TILE;

    aer_v1_raw_top_128 dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .tile_in_valid (tile_in_valid),
        .tile_on_flat  (tile_on_flat),
        .tile_off_flat (tile_off_flat),
        .tile_in_ready (tile_in_ready),
        .out_data      (out_data),
        .out_valid     (out_valid),
        .out_ready     (out_ready),
        .out_last      (out_last)
    );

    always #5 clk = ~clk;

    integer transfer_count;
    integer timeout;
    reg [15:0] captured [0:2];
    reg [2:0] captured_last;

    initial begin
        clk            = 1'b0;
        rst_n          = 1'b0;
        tile_in_valid  = 4096'b0;
        tile_on_flat   = 16384'b0;
        tile_off_flat  = 16384'b0;
        out_ready      = 1'b1;
        transfer_count = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        if (tile_in_ready[TEST_INDEX] !== 1'b1) begin
            $display("AER_V1_RAW_TOP_READY_FAIL");
            $fatal(1);
        end

        tile_on_flat[TEST_INDEX*4 +: 4] = 4'b1111;
        tile_in_valid[TEST_INDEX] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 4096'b0;
        tile_on_flat  = 16384'b0;

        timeout = 0;
        while ((transfer_count < 3) && (timeout < 200)) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                captured[transfer_count] = out_data;
                captured_last[transfer_count] = out_last;
                transfer_count = transfer_count + 1;
            end
            timeout = timeout + 1;
        end

        if (transfer_count != 3) begin
            $display("AER_V1_RAW_TOP_TIMEOUT transfers=%0d", transfer_count);
            $fatal(1);
        end
        if ((captured[0] !== 16'h8440) ||
            (captured[1] !== 16'h0020) ||
            (captured[2] !== 16'h00F0) ||
            (captured_last !== 3'b100)) begin
            $display("AER_V1_RAW_TOP_FAIL words=%h,%h,%h last=%b",
                captured[0], captured[1], captured[2], captured_last);
            $fatal(1);
        end

        $display("AER_V1_RAW_TOP_128_PASS header=%h mask=%h data=%h",
            captured[0], captured[1], captured[2]);
        $finish;
    end

endmodule
