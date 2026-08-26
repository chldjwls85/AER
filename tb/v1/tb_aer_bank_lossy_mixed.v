`timescale 1ns/1ps

module tb_aer_bank_lossy_mixed;

    reg clk;
    reg rst_n;
    reg [15:0] tile_in_valid;
    reg [63:0] tile_on_flat;
    reg [63:0] tile_off_flat;
    reg [15:0] time_now;
    reg out_ready;

    wire [15:0] tile_in_ready;
    wire [15:0] out_data;
    wire out_valid;
    wire out_last;
    wire [15:0] pending_debug;

    reg [15:0] captured_word [0:31];
    reg captured_last [0:31];
    integer captured_count;
    integer timeout;

    aer_bank_row_reader #(
        .BANK_ID(16'h0005),
        .ENABLE_BINNING(1),
        .ENABLE_ROW_FUSION(0),
        .ENABLE_BANK_FUSION(1),
        .ENABLE_LOSSY_BINNING(1),
        .EXTERNAL_RX_TIMESTAMP(1)
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
        if (!rst_n)
            captured_count = 0;
        else if (out_valid && out_ready) begin
            captured_word[captured_count] = out_data;
            captured_last[captured_count] = out_last;
            captured_count = captured_count + 1;
        end
    end

    task send_bank;
        input [15:0] valid_mask;
        input [63:0] on_values;
        input [63:0] off_values;
        begin
            @(negedge clk);
            tile_in_valid = valid_mask;
            tile_on_flat = on_values;
            tile_off_flat = off_values;
            @(posedge clk);
            @(negedge clk);
            tile_in_valid = 16'b0;
            tile_on_flat = 64'b0;
            tile_off_flat = 64'b0;
        end
    endtask

    task wait_for_count;
        input integer expected_count;
        begin
            timeout = 0;
            while ((captured_count < expected_count) && (timeout < 200)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (captured_count != expected_count) begin
                $display("AER_BANK_LOSSY_TIMEOUT expected=%0d got=%0d pending=%h",
                    expected_count, captured_count, pending_debug);
                $fatal(1);
            end
        end
    endtask

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

        // Python lossy-policy reference:
        // 8 active tiles = 2 RAW8 + 3 GROUP3 + 3 BIN4.
        // Mixed cost = 3 + ceil((2*8 + 6*1)/16) = 5 words.
        // RAW-bank cost = 2 + ceil(8*8/16) = 6 words.
        send_bank(16'h00FF, 64'h20EF_00E1, 64'h4F00_EF00);
        wait_for_count(5);
        if ((captured_word[0] !== 16'h8177) ||
            (captured_word[1] !== 16'h00FF) ||
            (captured_word[2] !== 16'h007E) ||
            (captured_word[3] !== 16'h1910) ||
            (captured_word[4] !== 16'h0009) ||
            captured_last[0] || captured_last[1] || captured_last[2] ||
            captured_last[3] || !captured_last[4]) begin
            $display("AER_BANK_LOSSY_MIXED_FAIL words=%h,%h,%h,%h,%h last=%b%b%b%b%b",
                captured_word[0], captured_word[1], captured_word[2],
                captured_word[3], captured_word[4], captured_last[0],
                captured_last[1], captured_last[2], captured_last[3],
                captured_last[4]);
            $fatal(1);
        end

        // A GROUP3 plus one RAW8 tile has no word advantage.  The lossy mode
        // must therefore fall back to exact row RAW8, preserving the missing
        // pixel instead of reconstructing it.
        send_bank(16'h0003, 64'h0000_0000_0000_001E, 64'b0);
        wait_for_count(8);
        if ((captured_word[5] !== 16'hC143) ||
            (captured_word[6] !== 16'h0380) ||
            (captured_word[7] !== 16'h0040) ||
            captured_last[5] || captured_last[6] || !captured_last[7]) begin
            $display("AER_BANK_LOSSY_ROW_FALLBACK_FAIL words=%h,%h,%h last=%b%b%b",
                captured_word[5], captured_word[6], captured_word[7],
                captured_last[5], captured_last[6], captured_last[7]);
            $fatal(1);
        end

        // Four BIN candidates, one per row: mixed and RAW-bank both cost four
        // words.  Strict comparison keeps the lossless RAW-bank packet.
        send_bank(16'h1111, 64'h000F_000F_000F_000F, 64'b0);
        wait_for_count(12);
        if ((captured_word[8] !== 16'h8143) ||
            (captured_word[9] !== 16'h1111) ||
            (captured_word[10] !== 16'hF0F0) ||
            (captured_word[11] !== 16'hF0F0) ||
            captured_last[8] || captured_last[9] || captured_last[10] ||
            !captured_last[11]) begin
            $display("AER_BANK_LOSSY_RAW_BANK_FALLBACK_FAIL words=%h,%h,%h,%h",
                captured_word[8], captured_word[9], captured_word[10],
                captured_word[11]);
            $fatal(1);
        end

        $display("AER_BANK_LOSSY_MIXED_PASS mixed_words=5 row_fallback=3 raw_bank_tie=4");
        $finish;
    end

endmodule
