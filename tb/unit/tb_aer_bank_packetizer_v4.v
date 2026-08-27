`timescale 1ns/1ps

// Directed V4 SPARSE/ROW policy, timestamp boundary, and handshake test.
module tb_aer_bank_packetizer_v4;
    reg clk;
    reg rst_n;
    reg [15:0] tile_in_valid;
    reg [63:0] tile_on_flat;
    reg [63:0] tile_off_flat;
    wire [15:0] tile_in_ready;
    reg [15:0] time_now;
    wire [15:0] out_data;
    wire out_valid;
    reg out_ready;
    wire out_last;
    wire [15:0] pending_debug;

    reg [15:0] packet_words [0:15];
    reg packet_last [0:15];
    reg [15:0] stalled_data;
    reg stalled_last;
    integer packet_count;
    integer timeout_count;
    integer errors;
    integer index;
    integer done;

    aer_bank_packetizer_v4 #(
        .BANK_ID(8'h5a),
        .MAX_BANK_DELTA(31)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat),
        .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .time_now(time_now),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_last(out_last),
        .pending_debug(pending_debug)
    );

    always #5 clk = ~clk;

    task drive_tile;
        input [3:0] tile_id;
        input [3:0] on_bits;
        input [3:0] off_bits;
        input [15:0] stamp;
        begin
            @(negedge clk);
            if (!tile_in_ready[tile_id]) begin
                $display("V4_TB_ERROR tile %0d not ready", tile_id);
                errors = errors + 1;
            end
            time_now = stamp;
            tile_on_flat[tile_id*4 +: 4] = on_bits;
            tile_off_flat[tile_id*4 +: 4] = off_bits;
            tile_in_valid[tile_id] = 1'b1;
            @(negedge clk);
            tile_in_valid[tile_id] = 1'b0;
        end
    endtask

    task wait_for_stalled_output;
        begin
            timeout_count = 0;
            while (!out_valid && timeout_count < 100) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            if (!out_valid) begin
                $display("V4_TB_ERROR stalled output timeout");
                errors = errors + 1;
            end else begin
                stalled_data = out_data;
                stalled_last = out_last;
                for (index = 0; index < 3; index = index + 1) begin
                    @(posedge clk);
                    #1;
                    if (!out_valid || out_data !== stalled_data ||
                        out_last !== stalled_last) begin
                        $display("V4_TB_ERROR output changed under backpressure");
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    task start_blocker;
        input [15:0] stamp;
        begin
            @(negedge clk);
            out_ready = 1'b0;
            drive_tile(4'd15, 4'b1000, 4'b0000, stamp);
            wait_for_stalled_output;
            if (!pending_debug[15]) begin
                $display("V4_TB_ERROR stalled tile cleared before handshake");
                errors = errors + 1;
            end
        end
    endtask

    task release_blocker;
        begin
            @(negedge clk);
            out_ready = 1'b1;
        end
    endtask

    task capture_packet;
        begin
            packet_count = 0;
            timeout_count = 0;
            done = 0;
            while (timeout_count < 300 && done == 0) begin
                @(posedge clk);
                if (out_valid && out_ready) begin
                    if (packet_count < 16) begin
                        packet_words[packet_count] = out_data;
                        packet_last[packet_count] = out_last;
                    end else begin
                        $display("V4_TB_ERROR packet capture overflow");
                        errors = errors + 1;
                    end
                    packet_count = packet_count + 1;
                    if (out_last)
                        done = 1;
                end
                timeout_count = timeout_count + 1;
            end
            if (!done) begin
                $display("V4_TB_ERROR packet capture timeout");
                errors = errors + 1;
            end
        end
    endtask

    task check_count;
        input integer expected;
        input integer test_id;
        begin
            if (packet_count != expected) begin
                $display("V4_TB_ERROR TEST%0d words expected=%0d got=%0d",
                         test_id, expected, packet_count);
                errors = errors + 1;
            end
        end
    endtask

    task check_word;
        input integer word_index;
        input [15:0] expected;
        input integer test_id;
        begin
            if (packet_words[word_index] !== expected) begin
                $display("V4_TB_ERROR TEST%0d word[%0d] expected=%h got=%h",
                         test_id, word_index, expected,
                         packet_words[word_index]);
                errors = errors + 1;
            end
        end
    endtask

    task check_last;
        input integer expected_words;
        input integer test_id;
        begin
            for (index = 0; index < expected_words; index = index + 1) begin
                if (packet_last[index] !== (index == expected_words-1)) begin
                    $display("V4_TB_ERROR TEST%0d LAST at word %0d",
                             test_id, index);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task check_sparse_packet;
        input [3:0] tile_id;
        input [1:0] pixel;
        input polarity;
        input [15:0] stamp;
        input integer test_id;
        begin
            check_count(2, test_id);
            check_word(0, {1'b0, 8'h5a, tile_id, pixel, polarity}, test_id);
            check_word(1, stamp, test_id);
            check_last(2, test_id);
        end
    endtask

    task check_row_header;
        input [1:0] row_id;
        input [3:0] columns;
        input integer test_id;
        begin
            check_word(0, {2'b11, 8'h5a, row_id, columns}, test_id);
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
        errors = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        if (pending_debug !== 16'b0 || out_valid || out_last) begin
            $display("V4_TB_ERROR reset/idle state");
            errors = errors + 1;
        end

        // TEST 1: singleton SPARSE plus backpressure stability and clear.
        out_ready = 1'b0;
        drive_tile(4'd0, 4'b0001, 4'b0000, 16'h1234);
        wait_for_stalled_output;
        if (!pending_debug[0]) begin
            $display("V4_TB_ERROR TEST1 pending cleared while stalled");
            errors = errors + 1;
        end
        release_blocker;
        capture_packet;
        check_sparse_packet(4'd0, 2'd0, 1'b1, 16'h1234, 1);
        @(posedge clk);
        #1;
        if (pending_debug[0]) begin
            $display("V4_TB_ERROR TEST1 pending not cleared after handshake");
            errors = errors + 1;
        end

        // TEST 2: multi-bit transaction uses lossless single-tile ROW.
        drive_tile(4'd2, 4'b0011, 4'b0100, 16'd200);
        capture_packet;
        check_count(3, 2);
        check_row_header(2'd0, 4'b0100, 2);
        check_word(1, 16'd200, 2);
        check_word(2, {5'd0, 4'b0011, 4'b0100, 3'b000}, 2);
        check_last(3, 2);

        // TEST 3: four same-row singletons make ROW strictly cheaper.
        start_blocker(16'd1000);
        drive_tile(4'd0, 4'b0001, 4'b0000, 16'd300);
        drive_tile(4'd1, 4'b0010, 4'b0000, 16'd300);
        drive_tile(4'd2, 4'b0000, 4'b0100, 16'd300);
        drive_tile(4'd3, 4'b0000, 4'b1000, 16'd300);
        release_blocker;
        capture_packet;
        check_sparse_packet(4'd15, 2'd3, 1'b1, 16'd1000, 3);
        capture_packet;
        check_count(6, 3);
        check_row_header(2'd0, 4'b1111, 3);
        check_word(1, 16'd300, 3);
        check_word(2, {5'd0, 4'b0001, 4'b0000, 3'b000}, 3);
        check_word(3, {5'd0, 4'b0010, 4'b0000, 3'b000}, 3);
        check_word(4, {5'd0, 4'b0000, 4'b0100, 3'b000}, 3);
        check_word(5, {5'd0, 4'b0000, 4'b1000, 3'b000}, 3);
        check_last(6, 3);

        // TEST 4: two singleton tie chooses individual SPARSE packets.
        start_blocker(16'd1001);
        drive_tile(4'd4, 4'b0001, 4'b0000, 16'd400);
        drive_tile(4'd5, 4'b0000, 4'b0010, 16'd400);
        release_blocker;
        capture_packet;
        check_sparse_packet(4'd15, 2'd3, 1'b1, 16'd1001, 4);
        capture_packet;
        check_sparse_packet(4'd4, 2'd0, 1'b1, 16'd400, 4);
        capture_packet;
        check_sparse_packet(4'd5, 2'd1, 1'b0, 16'd400, 4);

        // TEST 5: delta 31 remains in one ROW packet.
        start_blocker(16'd1002);
        drive_tile(4'd8, 4'b0011, 4'b0000, 16'd500);
        drive_tile(4'd9, 4'b0000, 4'b0011, 16'd531);
        release_blocker;
        capture_packet;
        check_sparse_packet(4'd15, 2'd3, 1'b1, 16'd1002, 5);
        capture_packet;
        check_count(4, 5);
        check_row_header(2'd2, 4'b0011, 5);
        check_word(1, 16'd500, 5);
        check_word(2, {5'd0, 4'b0011, 4'b0000, 3'b000}, 5);
        check_word(3, {5'd31, 4'b0000, 4'b0011, 3'b000}, 5);
        check_last(4, 5);

        // TEST 6: delta 32 is split into two lossless ROW fallbacks.
        start_blocker(16'd1003);
        drive_tile(4'd8, 4'b0011, 4'b0000, 16'd600);
        drive_tile(4'd9, 4'b0000, 4'b0011, 16'd632);
        release_blocker;
        capture_packet;
        check_sparse_packet(4'd15, 2'd3, 1'b1, 16'd1003, 6);
        capture_packet;
        check_count(3, 6);
        check_row_header(2'd2, 4'b0001, 6);
        check_word(1, 16'd600, 6);
        check_word(2, {5'd0, 4'b0011, 4'b0000, 3'b000}, 6);
        check_last(3, 6);
        capture_packet;
        check_count(3, 6);
        check_row_header(2'd2, 4'b0010, 6);
        check_word(1, 16'd632, 6);
        check_word(2, {5'd0, 4'b0000, 4'b0011, 3'b000}, 6);
        check_last(3, 6);

        if (errors == 0)
            $display("AER_BANK_PACKETIZER_V4_TB_PASS");
        else
            $display("AER_BANK_PACKETIZER_V4_TB_FAIL errors=%0d", errors);

        #20;
        $finish;
    end
endmodule
