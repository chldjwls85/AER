`timescale 1ns/1ps

module tb_aer_bank_row_fusion;

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

    reg [15:0] captured_word [0:7];
    reg captured_last [0:7];
    integer captured_count;
    integer timeout;

    aer_bank_row_reader #(
        .BANK_ID(16'h002A),
        .ENABLE_BINNING(1),
        .ENABLE_ROW_FUSION(1),
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
        if (!rst_n) begin
            captured_count = 0;
        end else if (out_valid && out_ready) begin
            captured_word[captured_count] = out_data;
            captured_last[captured_count] = out_last;
            captured_count = captured_count + 1;
        end
    end

    task send_row;
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
            while ((captured_count < expected_count) && (timeout < 100)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (captured_count != expected_count) begin
                $display("AER_BANK_ROW_FUSION_TIMEOUT expected=%0d got=%0d pending=%h",
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
        time_now = 16'd0;
        out_ready = 1'b1;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Row 0: four BIN4 tiles become one row data word.
        send_row(16'h000F, 64'h0000_0000_0000_FFFF, 64'b0);
        wait_for_count(2);
        if ((captured_word[0] !== 16'hCA8F) ||
            (captured_word[1] !== 16'hDE00) ||
            captured_last[0] || !captured_last[1]) begin
            $display("AER_BANK_ROW_BIN4_FAIL header=%h data=%h last=%b%b",
                captured_word[0], captured_word[1],
                captured_last[0], captured_last[1]);
            $fatal(1);
        end

        // Row 1: four GROUP3 tiles become one fixed-column token word.
        send_row(16'h00F0,
            64'h0000_0000_00DE_0000,
            64'h0000_0000_7B00_0000);
        wait_for_count(4);
        if ((captured_word[2] !== 16'hCA9F) ||
            (captured_word[3] !== 16'hED58) ||
            captured_last[2] || !captured_last[3]) begin
            $display("AER_BANK_ROW_GROUP3_FAIL header=%h data=%h last=%b%b",
                captured_word[2], captured_word[3],
                captured_last[2], captured_last[3]);
            $fatal(1);
        end

        // Row 2 is mixed RAW8/GROUP3, so it must use the old per-tile path.
        send_row(16'h0300,
            64'h0000_00E1_0000_0000,
            64'b0);
        wait_for_count(7);
        if ((captured_word[4] !== 16'hCAA3) ||
            (captured_word[5] !== 16'h0040) ||
            (captured_word[6] !== 16'h4200) ||
            captured_last[4] || captured_last[5] || !captured_last[6]) begin
            $display("AER_BANK_ROW_FALLBACK_FAIL words=%h,%h,%h last=%b%b%b",
                captured_word[4], captured_word[5], captured_word[6],
                captured_last[4], captured_last[5], captured_last[6]);
            $fatal(1);
        end

        $display("AER_BANK_ROW_FUSION_PASS bin4_words=2 group3_words=2 fallback_words=3");
        $finish;
    end

endmodule
