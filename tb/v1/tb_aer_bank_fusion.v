`timescale 1ns/1ps

module tb_aer_bank_fusion;

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
    integer word_index;

    aer_bank_row_reader #(
        .BANK_ID(16'h002A),
        .ENABLE_BINNING(1),
        .ENABLE_ROW_FUSION(0),
        .ENABLE_BANK_FUSION(1),
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
                $display("AER_BANK_FUSION_TIMEOUT expected=%0d got=%0d pending=%h",
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

        // Sixteen BIN4 tiles: header + bank mask + one polarity bitmap.
        send_bank(16'hFFFF, 64'hFFFF_FFFF_FFFF_FFFF, 64'b0);
        wait_for_count(3);
        if ((captured_word[0] !== 16'h8AAF) ||
            (captured_word[1] !== 16'hFFFF) ||
            (captured_word[2] !== 16'hFFFF) ||
            captured_last[0] || captured_last[1] || !captured_last[2]) begin
            $display("AER_BANK_FUSION_BIN4_FAIL words=%h,%h,%h last=%b%b%b",
                captured_word[0], captured_word[1], captured_word[2],
                captured_last[0], captured_last[1], captured_last[2]);
            $fatal(1);
        end

        // Sixteen GROUP3 tiles: 48 token bits become three payload words.
        send_bank(16'hFFFF, 64'hEEEE_EEEE_EEEE_EEEE, 64'b0);
        wait_for_count(8);
        if ((captured_word[3] !== 16'h8A9F) ||
            (captured_word[4] !== 16'hFFFF) ||
            (captured_word[5] !== 16'h4924) ||
            (captured_word[6] !== 16'h2492) ||
            (captured_word[7] !== 16'h9249) ||
            captured_last[3] || captured_last[4] || captured_last[5] ||
            captured_last[6] || !captured_last[7]) begin
            $display("AER_BANK_FUSION_GROUP3_FAIL words=%h,%h,%h,%h,%h",
                captured_word[3], captured_word[4], captured_word[5],
                captured_word[6], captured_word[7]);
            $fatal(1);
        end

        // Sixteen lossless RAW8 tiles: two tokens per 16-bit payload word.
        send_bank(16'hFFFF, 64'h1111_1111_1111_1111, 64'b0);
        wait_for_count(18);
        if ((captured_word[8] !== 16'h8A8F) ||
            (captured_word[9] !== 16'hFFFF) ||
            !captured_last[17]) begin
            $display("AER_BANK_FUSION_RAW8_HEADER_FAIL header=%h mask=%h last=%b",
                captured_word[8], captured_word[9], captured_last[17]);
            $fatal(1);
        end
        for (word_index = 10; word_index < 18; word_index = word_index + 1) begin
            if ((captured_word[word_index] !== 16'h1010) ||
                ((word_index != 17) && captured_last[word_index])) begin
                $display("AER_BANK_FUSION_RAW8_DATA_FAIL index=%0d word=%h last=%b",
                    word_index, captured_word[word_index],
                    captured_last[word_index]);
                $fatal(1);
            end
        end

        // One RAW8 tile costs two row words but three bank words, so the
        // strict cost gate must keep the legacy row packet.
        send_bank(16'h0001, 64'h0000_0000_0000_0001, 64'b0);
        wait_for_count(20);
        if ((captured_word[18] !== 16'hCA81) ||
            (captured_word[19] !== 16'h0040) ||
            captured_last[18] || !captured_last[19]) begin
            $display("AER_BANK_FUSION_FALLBACK_FAIL header=%h data=%h last=%b%b",
                captured_word[18], captured_word[19],
                captured_last[18], captured_last[19]);
            $fatal(1);
        end

        $display("AER_BANK_FUSION_PASS bin4_words=3 group3_words=5 raw8_words=10 fallback_words=2");
        $finish;
    end

endmodule
