`timescale 1ns/1ps

module tb_aer_bank_combined_opt;

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

    aer_bank_row_reader_combined_opt #(
        .BANK_ID(16'h0005)
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
            while ((captured_count < expected_count) && (timeout < 300)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (captured_count != expected_count) begin
                $display("AER_BANK_COMBINED_OPT_TIMEOUT expected=%0d got=%0d pending=%h",
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

        // Lossless SPARSE packet.
        send_bank(16'h0001, 64'h0000_0000_0000_0004, 64'b0);
        wait_for_count(1);
        if ((captured_word[0] !== 16'h0285) || !captured_last[0]) begin
            $display("AER_BANK_COMBINED_OPT_SPARSE_FAIL word=%h last=%b",
                captured_word[0], captured_last[0]);
            $fatal(1);
        end

        // Same dense mixed packet as the legacy combined reader.
        send_bank(16'h00FF, 64'h20EF_00E1, 64'h4F00_EF00);
        wait_for_count(6);
        if ((captured_word[1] !== 16'h8177) ||
            (captured_word[2] !== 16'h00FF) ||
            (captured_word[3] !== 16'h007E) ||
            (captured_word[4] !== 16'h1910) ||
            (captured_word[5] !== 16'h0009) ||
            captured_last[1] || captured_last[2] || captured_last[3] ||
            captured_last[4] || !captured_last[5]) begin
            $display("AER_BANK_COMBINED_OPT_DENSE_FAIL words=%h,%h,%h,%h,%h",
                captured_word[1], captured_word[2], captured_word[3],
                captured_word[4], captured_word[5]);
            $fatal(1);
        end

        $display("AER_BANK_COMBINED_OPT_PASS sparse_words=1 dense_words=5");
        $finish;
    end

endmodule
