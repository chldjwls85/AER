`timescale 1ns/1ps

// Decoder round-trip and randomized backpressure test for one 8x8-pixel bank.
// Equality is semantic: decoded {tile, ON, OFF, timestamp} records may be
// packet-reordered, but every accepted input must appear exactly once.
module tb_aer_roundtrip_random;
    localparam integer RANDOM_ACCEPTS = 2048;
    localparam integer MAX_RECORDS = RANDOM_ACCEPTS + 8;

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

    integer expected_tile [0:MAX_RECORDS-1];
    reg [3:0] expected_on [0:MAX_RECORDS-1];
    reg [3:0] expected_off [0:MAX_RECORDS-1];
    reg [15:0] expected_time [0:MAX_RECORDS-1];
    reg expected_matched [0:MAX_RECORDS-1];
    integer expected_count;
    integer matched_count;
    integer errors;
    integer input_index;
    integer search_index;
    integer selected_index;
    integer random_seed;
    integer random_value;
    integer batch_size;
    integer batch_index;
    integer timeout_count;
    integer low_ready_cycles;
    integer accepted_before_second;

    reg random_ready_enable;
    reg [15:0] ready_lfsr;
    reg stalled_valid;
    reg stalled_ready;
    reg [15:0] stalled_data;
    reg stalled_last;

    integer decode_state;
    reg [15:0] decode_mask;
    reg [15:0] decode_remaining;
    reg [15:0] decode_base_time;
    integer decoded_tile;
    reg [15:0] decoded_time;
    reg [3:0] decoded_on;
    reg [3:0] decoded_off;
    reg [15:0] remaining_after_decode;
    reg found_match;
    integer bit_index;

    aer_bank_packetizer #(
        .BANK_ID(8'd37),
        .MAX_BANK_DELTA(31)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat),
        .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .time_now(time_now),
        .out_data(out_data), .out_valid(out_valid),
        .out_ready(out_ready), .out_last(out_last),
        .pending_debug(), .bank_mode_debug()
    );

    always #5 clk = ~clk;

    // Pseudo-random ready with a guaranteed nonzero service rate.
    always @(negedge clk) begin
        if (!rst_n) begin
            ready_lfsr <= 16'h1ace;
        end else if (random_ready_enable) begin
            ready_lfsr <= {ready_lfsr[14:0],
                           ready_lfsr[15] ^ ready_lfsr[13] ^
                           ready_lfsr[12] ^ ready_lfsr[10]};
            out_ready <= ready_lfsr[0] | ready_lfsr[3];
        end
    end

    // Record only protocol-accepted, nonempty input transactions.
    always @(posedge clk) begin
        if (rst_n) begin
            for (input_index = 0; input_index < 16; input_index = input_index + 1) begin
                if (tile_in_valid[input_index] && tile_in_ready[input_index] &&
                    (|tile_on_flat[input_index*4 +: 4] ||
                     |tile_off_flat[input_index*4 +: 4])) begin
                    if (expected_count >= MAX_RECORDS) begin
                        $display("ROUNDTRIP_ERROR expected record overflow");
                        errors = errors + 1;
                    end else begin
                        expected_tile[expected_count] = input_index;
                        expected_on[expected_count] = tile_on_flat[input_index*4 +: 4];
                        expected_off[expected_count] = tile_off_flat[input_index*4 +: 4];
                        expected_time[expected_count] = time_now;
                        expected_matched[expected_count] = 1'b0;
                        expected_count = expected_count + 1;
                    end
                end
            end
        end
    end

    // Backpressure stability: valid/data/last must not change while stalled.
    always @(posedge clk) begin
        if (rst_n && stalled_valid && !stalled_ready) begin
            if (!out_valid || out_data !== stalled_data || out_last !== stalled_last) begin
                $display("ROUNDTRIP_ERROR output changed while ready=0");
                errors = errors + 1;
            end
        end
        stalled_valid = out_valid;
        stalled_ready = out_ready;
        stalled_data = out_data;
        stalled_last = out_last;
    end

    // Decode accepted output words and match each reconstructed event once.
    always @(posedge clk) begin
        if (!rst_n) begin
            decode_state = 0;
            decode_mask = 16'b0;
            decode_remaining = 16'b0;
            decode_base_time = 16'b0;
        end else if (out_valid && out_ready) begin
            case (decode_state)
                0: begin
                    if (out_data[15:14] == 2'b11) begin
                        if (out_data[13:6] != 8'd37) begin
                            $display("ROUNDTRIP_ERROR ROW bank ID %0d", out_data[13:6]);
                            errors = errors + 1;
                        end
                        decode_mask = ({12'b0, out_data[3:0]} << (out_data[5:4] * 4));
                        decode_state = 1;
                    end else if (out_data[15:14] == 2'b10) begin
                        if (out_data[13:6] != 8'd37) begin
                            $display("ROUNDTRIP_ERROR BANK bank ID %0d", out_data[13:6]);
                            errors = errors + 1;
                        end
                        decode_state = 2;
                    end else begin
                        $display("ROUNDTRIP_ERROR invalid header %h", out_data);
                        errors = errors + 1;
                    end
                    if (out_last) begin
                        $display("ROUNDTRIP_ERROR header asserted LAST");
                        errors = errors + 1;
                    end
                end
                1: begin
                    decode_base_time = out_data;
                    decode_remaining = decode_mask;
                    decode_state = 4;
                    if (out_last) begin
                        $display("ROUNDTRIP_ERROR ROW time asserted LAST");
                        errors = errors + 1;
                    end
                end
                2: begin
                    decode_mask = out_data;
                    decode_state = 3;
                    if (out_last) begin
                        $display("ROUNDTRIP_ERROR BANK mask asserted LAST");
                        errors = errors + 1;
                    end
                end
                3: begin
                    decode_base_time = out_data;
                    decode_remaining = decode_mask;
                    decode_state = 4;
                    if (out_last) begin
                        $display("ROUNDTRIP_ERROR BANK time asserted LAST");
                        errors = errors + 1;
                    end
                end
                4: begin
                    decoded_tile = -1;
                    for (bit_index = 0; bit_index < 16; bit_index = bit_index + 1)
                        if ((decoded_tile < 0) && decode_remaining[bit_index])
                            decoded_tile = bit_index;
                    if (decoded_tile < 0) begin
                        $display("ROUNDTRIP_ERROR DATA without mask bit");
                        errors = errors + 1;
                    end else begin
                        decoded_time = decode_base_time + {11'b0, out_data[15:11]};
                        decoded_on = out_data[10:7];
                        decoded_off = out_data[6:3];
                        found_match = 1'b0;
                        selected_index = -1;
                        for (search_index = 0; search_index < expected_count;
                             search_index = search_index + 1) begin
                            if (!found_match && !expected_matched[search_index] &&
                                expected_tile[search_index] == decoded_tile &&
                                expected_on[search_index] === decoded_on &&
                                expected_off[search_index] === decoded_off &&
                                expected_time[search_index] === decoded_time) begin
                                found_match = 1'b1;
                                selected_index = search_index;
                            end
                        end
                        if (!found_match) begin
                            $display("ROUNDTRIP_ERROR unmatched tile=%0d on=%h off=%h time=%0d",
                                     decoded_tile, decoded_on, decoded_off, decoded_time);
                            errors = errors + 1;
                        end else begin
                            expected_matched[selected_index] = 1'b1;
                            matched_count = matched_count + 1;
                        end
                        remaining_after_decode = decode_remaining;
                        remaining_after_decode[decoded_tile] = 1'b0;
                        decode_remaining = remaining_after_decode;
                        if (out_last !== (remaining_after_decode == 16'b0)) begin
                            $display("ROUNDTRIP_ERROR LAST/mask mismatch tile=%0d", decoded_tile);
                            errors = errors + 1;
                        end
                        if (out_last)
                            decode_state = 0;
                    end
                end
                default: begin
                    $display("ROUNDTRIP_ERROR bad decoder state");
                    errors = errors + 1;
                    decode_state = 0;
                end
            endcase
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;
        tile_off_flat = 64'b0;
        time_now = 16'd100;
        out_ready = 1'b0;
        random_ready_enable = 1'b0;
        ready_lfsr = 16'h1ace;
        stalled_valid = 1'b0;
        stalled_ready = 1'b0;
        stalled_data = 16'b0;
        stalled_last = 1'b0;
        expected_count = 0;
        matched_count = 0;
        errors = 0;
        decode_state = 0;
        random_seed = 32'h51a7c0de;
        for (input_index = 0; input_index < MAX_RECORDS; input_index = input_index + 1)
            expected_matched[input_index] = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Directed same-tile test: the second event is held while ready=0.
        @(negedge clk);
        tile_on_flat[5*4 +: 4] = 4'h1;
        tile_off_flat[5*4 +: 4] = 4'h2;
        tile_in_valid[5] = 1'b1;
        @(negedge clk);
        tile_in_valid[5] = 1'b0;
        time_now = 16'd101;
        tile_on_flat[5*4 +: 4] = 4'h4;
        tile_off_flat[5*4 +: 4] = 4'h8;
        tile_in_valid[5] = 1'b1;
        low_ready_cycles = 0;
        repeat (4) begin
            @(posedge clk);
            if (!tile_in_ready[5]) low_ready_cycles = low_ready_cycles + 1;
        end
        if (low_ready_cycles != 4 || expected_count != 1) begin
            $display("ROUNDTRIP_ERROR same-tile input was not backpressured");
            errors = errors + 1;
        end
        accepted_before_second = expected_count;
        @(negedge clk);
        out_ready = 1'b1;
        timeout_count = 0;
        while ((expected_count == accepted_before_second) && timeout_count < 100) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end
        tile_in_valid[5] = 1'b0;
        if (expected_count != 2) begin
            $display("ROUNDTRIP_ERROR held same-tile event was not accepted");
            errors = errors + 1;
        end
        timeout_count = 0;
        while ((matched_count < expected_count) && timeout_count < 200) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (matched_count != 2) begin
            $display("ROUNDTRIP_ERROR same-tile round-trip matched=%0d", matched_count);
            errors = errors + 1;
        end

        // Random accepted transactions with random backpressure and timestamps.
        random_ready_enable = 1'b1;
        while (expected_count < RANDOM_ACCEPTS + 2) begin
            @(negedge clk);
            tile_in_valid = 16'b0;
            tile_on_flat = 64'b0;
            tile_off_flat = 64'b0;
            time_now = time_now + 1'b1;
            random_value = $random(random_seed);
            if (random_value < 0) random_value = -random_value;
            batch_size = (random_value % 4) + 1;
            if (batch_size > (RANDOM_ACCEPTS + 2 - expected_count))
                batch_size = RANDOM_ACCEPTS + 2 - expected_count;
            for (batch_index = 0; batch_index < batch_size; batch_index = batch_index + 1) begin
                random_value = $random(random_seed);
                if (random_value < 0) random_value = -random_value;
                selected_index = random_value % 16;
                if (tile_in_ready[selected_index] && !tile_in_valid[selected_index]) begin
                    tile_in_valid[selected_index] = 1'b1;
                    random_value = $random(random_seed);
                    tile_on_flat[selected_index*4 +: 4] = (random_value & 15) | 1;
                    random_value = $random(random_seed);
                    tile_off_flat[selected_index*4 +: 4] = random_value & 15;
                end
            end
            @(negedge clk);
            tile_in_valid = 16'b0;
        end

        random_ready_enable = 1'b0;
        @(negedge clk);
        out_ready = 1'b1;
        tile_in_valid = 16'b0;
        timeout_count = 0;
        while ((matched_count < expected_count) && timeout_count < 100000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        repeat (5) @(posedge clk);

        if (expected_count != RANDOM_ACCEPTS + 2) begin
            $display("ROUNDTRIP_ERROR expected accepted=%0d got=%0d",
                     RANDOM_ACCEPTS + 2, expected_count);
            errors = errors + 1;
        end
        if (matched_count != expected_count) begin
            $display("ROUNDTRIP_ERROR decoded=%0d accepted=%0d",
                     matched_count, expected_count);
            errors = errors + 1;
        end
        if (decode_state != 0) begin
            $display("ROUNDTRIP_ERROR decoder ended mid-packet state=%0d", decode_state);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("AER_ROUNDTRIP_RANDOM_PASS accepted=%0d decoded=%0d",
                     expected_count, matched_count);
        else
            $display("AER_ROUNDTRIP_RANDOM_FAIL errors=%0d accepted=%0d decoded=%0d",
                     errors, expected_count, matched_count);
        #20;
        $finish;
    end
endmodule
