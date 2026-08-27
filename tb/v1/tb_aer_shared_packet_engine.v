`timescale 1ns/1ps

module tb_aer_shared_packet_engine;

    reg clk;
    reg rst_n;
    reg [7:0] bank_id;
    reg [15:0] snapshot_mask;
    reg [127:0] snapshot_raw_flat;
    reg snapshot_valid;
    wire snapshot_ready;
    wire [15:0] out_data;
    wire out_valid;
    reg out_ready;
    wire out_last;
    wire busy_debug;
    reg congestion_high;
    reg congestion_critical;

    reg [15:0] captured_word [0:15];
    reg captured_last [0:15];
    integer captured_count;
    integer timeout;
    integer dense_tile;
    reg [63:0] dense_on;
    reg [63:0] dense_off;
    reg [127:0] dense_raw;
    reg [15:0] held_word;

    aer_shared_packet_engine #(
        .ENABLE_COMPRESSION(1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .snapshot_bank_id(bank_id),
        .snapshot_mask(snapshot_mask),
        .snapshot_raw_flat(snapshot_raw_flat),
        .snapshot_valid(snapshot_valid),
        .snapshot_ready(snapshot_ready),
        .congestion_high(congestion_high),
        .congestion_critical(congestion_critical),
        .out_data(out_data), .out_valid(out_valid),
        .out_ready(out_ready), .out_last(out_last),
        .busy_debug(busy_debug)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            captured_word[captured_count] <= out_data;
            captured_last[captured_count] <= out_last;
            captured_count <= captured_count + 1;
        end
    end

    task send_snapshot;
        input [15:0] mask;
        input [127:0] raw_flat;
        begin
            while (!snapshot_ready) @(posedge clk);
            @(negedge clk);
            snapshot_mask = mask;
            snapshot_raw_flat = raw_flat;
            snapshot_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            snapshot_valid = 1'b0;
            snapshot_mask = 16'b0;
            snapshot_raw_flat = 128'b0;
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
                $display("AER_SHARED_ENGINE_TIMEOUT expected=%0d got=%0d busy=%b",
                    expected_count, captured_count, busy_debug);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        bank_id = 8'd5;
        snapshot_mask = 16'b0;
        snapshot_raw_flat = 128'b0;
        snapshot_valid = 1'b0;
        out_ready = 1'b1;
        congestion_high = 1'b0;
        congestion_critical = 1'b0;
        captured_count = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // One lossless SPARSE event: tile 0, pixel 2, ON.  Hold the output
        // stalled for two cycles to verify ready/valid stability.
        out_ready = 1'b0;
        send_snapshot(16'h0001, 128'h0000_0000_0000_0000_0000_0000_0000_0040);
        while (!out_valid) @(posedge clk);
        held_word = out_data;
        repeat (2) begin
            @(posedge clk);
            if (!out_valid || (out_data !== held_word) || !out_last) begin
                $display("AER_SHARED_ENGINE_BACKPRESSURE_FAIL word=%h held=%h valid=%b last=%b",
                    out_data, held_word, out_valid, out_last);
                $fatal(1);
            end
        end
        @(negedge clk);
        out_ready = 1'b1;
        wait_for_count(1);
        if ((captured_word[0] !== 16'h0285) || !captured_last[0]) begin
            $display("AER_SHARED_ENGINE_SPARSE_FAIL word=%h last=%b",
                captured_word[0], captured_last[0]);
            $fatal(1);
        end

        // Dense mixed packet must remain bit-compatible with the optimized
        // per-bank implementation.
        congestion_high = 1'b1;
        congestion_critical = 1'b1;
        dense_on = 64'h20EF_00E1;
        dense_off = 64'h4F00_EF00;
        dense_raw = 128'b0;
        for (dense_tile = 0; dense_tile < 16;
             dense_tile = dense_tile + 1) begin
            dense_raw[dense_tile*8 +: 8] = {
                dense_on[dense_tile*4 +: 4],
                dense_off[dense_tile*4 +: 4]
            };
        end
        send_snapshot(16'h00FF, dense_raw);
        wait_for_count(6);
        if ((captured_word[1] !== 16'h8177) ||
            (captured_word[2] !== 16'h00FF) ||
            (captured_word[3] !== 16'h007E) ||
            (captured_word[4] !== 16'h1910) ||
            (captured_word[5] !== 16'h0009) ||
            captured_last[1] || captured_last[2] ||
            captured_last[3] || captured_last[4] ||
            !captured_last[5]) begin
            $display("AER_SHARED_ENGINE_DENSE_FAIL %h %h %h %h %h",
                captured_word[1], captured_word[2], captured_word[3],
                captured_word[4], captured_word[5]);
            $fatal(1);
        end

        $display("AER_SHARED_PACKET_ENGINE_PASS sparse=1 dense=5");
        $finish;
    end

endmodule
