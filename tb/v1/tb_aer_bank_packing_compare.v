`timescale 1ns/1ps

module tb_aer_bank_packing_compare;

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

    reg [15:0] adaptive_words [0:5];
    reg [5:0]  adaptive_last;
    integer    adaptive_count;
    reg [15:0] raw_words [0:5];
    reg [5:0]  raw_last;
    integer    raw_count;
    integer    timeout;
    integer    index;

    aer_bank_row_reader #(
        .BANK_ID(16'h00A5),
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
        .BANK_ID(16'h00A5),
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

    always @(posedge clk) begin
        if (!rst_n) begin
            adaptive_count = 0;
            raw_count = 0;
        end else begin
            if (adaptive_out_valid && out_ready) begin
                adaptive_words[adaptive_count] = adaptive_out_data;
                adaptive_last[adaptive_count] = adaptive_out_last;
                adaptive_count = adaptive_count + 1;
            end
            if (raw_out_valid && out_ready) begin
                raw_words[raw_count] = raw_out_data;
                raw_last[raw_count] = raw_out_last;
                raw_count = raw_count + 1;
            end
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
        adaptive_last = 6'b0;
        raw_last = 6'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        if ((adaptive_tile_in_ready !== 16'hFFFF) ||
            (raw_tile_in_ready !== 16'hFFFF)) begin
            $display("PACKING_COMPARE_READY_FAIL adaptive=%h raw=%h",
                adaptive_tile_in_ready, raw_tile_in_ready);
            $fatal(1);
        end

        time_now = 16'd100;
        for (index = 0; index < 4; index = index + 1) begin
            tile_on_flat[index*4 +: 4] = 4'b1111;
            tile_in_valid[index] = 1'b1;
        end
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;

        timeout = 0;
        while (((adaptive_count < 4) || (raw_count < 6)) &&
               (timeout < 100)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if ((adaptive_count != 4) || (raw_count != 6)) begin
            $display("PACKING_COMPARE_COUNT_FAIL adaptive=%0d raw=%0d",
                adaptive_count, raw_count);
            $fatal(1);
        end

        if ((adaptive_words[0] !== 16'hE94F) ||
            (adaptive_words[1] !== 16'd100) ||
            (adaptive_words[2] !== 16'hA108) ||
            (adaptive_words[3] !== 16'hA108) ||
            (adaptive_last !== 6'b00_1000)) begin
            $display("PACKING_COMPARE_ADAPTIVE_FAIL words=%h,%h,%h,%h last=%b",
                adaptive_words[0], adaptive_words[1],
                adaptive_words[2], adaptive_words[3], adaptive_last);
            $fatal(1);
        end

        if ((raw_words[0] !== 16'hE94F) ||
            (raw_words[1] !== 16'd100) ||
            (raw_words[2] !== 16'h03C0) ||
            (raw_words[3] !== 16'h03C0) ||
            (raw_words[4] !== 16'h03C0) ||
            (raw_words[5] !== 16'h03C0) ||
            (raw_last !== 6'b10_0000)) begin
            $display("PACKING_COMPARE_RAW_FAIL last=%b", raw_last);
            $fatal(1);
        end

        $display("AER_BANK_PACKING_COMPARE_PASS adaptive_words=4 raw_words=6");
        $finish;
    end

endmodule
