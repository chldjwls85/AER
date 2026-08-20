`timescale 1ns/1ps

// Focused adaptive-mode test with a controllable timestamp input.
module tb_aer_bank_packetizer;
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
    wire bank_mode_debug;

    reg [15:0] packet_words [0:31];
    reg packet_last [0:31];
    reg [15:0] stalled_word;
    reg stalled_last;
    integer packet_count;
    integer errors;
    integer timeout_count;
    integer done;
    integer stall_index;

    aer_bank_packetizer #(
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
        .pending_debug(pending_debug),
        .bank_mode_debug(bank_mode_debug)
    );

    always #5 clk = ~clk;

    task drive_tile;
        input [31:0] tile_id;
        input [3:0] on_bits;
        input [3:0] off_bits;
        input [15:0] stamp;
        begin
            @(negedge clk);
            if (!tile_in_ready[tile_id]) begin
                $display("TB_ERROR: tile %0d was not ready", tile_id);
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
            while (!out_valid && (timeout_count < 100)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            if (!out_valid) begin
                $display("TB_ERROR: timed out waiting for stalled output");
                errors = errors + 1;
            end else begin
                stalled_word = out_data;
                stalled_last = out_last;
                for (stall_index = 0; stall_index < 3; stall_index = stall_index + 1) begin
                    @(posedge clk);
                    #1;
                    if (!out_valid || (out_data !== stalled_word) ||
                        (out_last !== stalled_last)) begin
                        $display("TB_ERROR: output changed under backpressure");
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    task capture_packet;
        begin
            packet_count = 0;
            timeout_count = 0;
            done = 0;
            while ((timeout_count < 200) && (done == 0)) begin
                @(posedge clk);
                if (out_valid && out_ready) begin
                    if (packet_count < 32) begin
                        packet_words[packet_count] = out_data;
                        packet_last[packet_count] = out_last;
                    end else begin
                        $display("TB_ERROR: packet exceeded capture storage");
                        errors = errors + 1;
                    end
                    packet_count = packet_count + 1;
                    if (out_last)
                        done = 1;
                end
                timeout_count = timeout_count + 1;
            end
            if (done == 0) begin
                $display("TB_ERROR: packet capture timeout");
                errors = errors + 1;
            end
        end
    endtask

    task check_count;
        input [31:0] expected_count;
        input [31:0] test_number;
        begin
            if (packet_count != expected_count) begin
                $display("TB_ERROR TEST%0d: expected %0d words, got %0d",
                         test_number, expected_count, packet_count);
                errors = errors + 1;
            end
        end
    endtask

    task check_word;
        input [31:0] word_index;
        input [15:0] expected_word;
        input [31:0] test_number;
        begin
            if (packet_words[word_index] !== expected_word) begin
                $display("TB_ERROR TEST%0d: word[%0d] expected=%h got=%h",
                         test_number, word_index, expected_word,
                         packet_words[word_index]);
                errors = errors + 1;
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
        out_ready = 1'b0;
        errors = 0;

        for (stall_index = 0; stall_index < 4; stall_index = stall_index + 1) begin
            @(posedge clk);
        end
        rst_n = 1'b1;
        for (stall_index = 0; stall_index < 2; stall_index = stall_index + 1) begin
            @(posedge clk);
        end

        // TEST 1: accumulate two future events behind a stalled one-word
        // payload.  A timestamp span of exactly 31 must select BANK mode.
        drive_tile(15, 4'b1000, 4'b0000, 16'd10);
        wait_for_stalled_output;
        drive_tile(0, 4'b0001, 4'b0000, 16'd100);
        drive_tile(4, 4'b0010, 4'b0100, 16'd131);
        @(negedge clk);
        out_ready = 1'b1;

        capture_packet;
        check_count(3, 1);
        if (packet_words[0][15:14] !== 2'b11) begin
            $display("TB_ERROR TEST1: blocker was not a ROW packet");
            errors = errors + 1;
        end

        capture_packet;
        check_count(5, 1);
        check_word(0, 16'h9684, 1);
        check_word(1, 16'h0011, 1);
        check_word(2, 16'd100, 1);
        check_word(3, 16'h0080, 1);
        check_word(4, 16'hf920, 1);

        for (stall_index = 0; stall_index < 3; stall_index = stall_index + 1) begin
            @(posedge clk);
        end

        // TEST 2: a span of 32 cannot fit delta[4:0], so the two rows must
        // remain lossless as two independent ROW packets.
        @(negedge clk);
        out_ready = 1'b0;
        drive_tile(15, 4'b1000, 4'b0000, 16'd20);
        wait_for_stalled_output;
        drive_tile(0, 4'b0001, 4'b0000, 16'd200);
        drive_tile(4, 4'b0010, 4'b0000, 16'd232);
        @(negedge clk);
        out_ready = 1'b1;

        capture_packet;
        check_count(3, 2);

        capture_packet;
        check_count(3, 2);
        check_word(0, 16'hd681, 2);
        check_word(1, 16'd200, 2);
        check_word(2, 16'h0080, 2);

        capture_packet;
        check_count(3, 2);
        check_word(0, 16'hd691, 2);
        check_word(1, 16'd232, 2);
        check_word(2, 16'h0100, 2);

        if (errors == 0)
            $display("AER_BANK_PACKETIZER_TB_PASS");
        else
            $display("AER_BANK_PACKETIZER_TB_FAIL errors=%0d", errors);

        #20;
        $finish;
    end
endmodule
