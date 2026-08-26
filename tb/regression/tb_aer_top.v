`timescale 1ns/1ps

module tb_aer_top;
    localparam integer SENSOR_ROWS = 16;
    localparam integer SENSOR_COLS = 16;
    localparam integer TILE_COUNT = (SENSOR_ROWS/2)*(SENSOR_COLS/2);

    reg clk;
    reg rst_n;
    reg [TILE_COUNT-1:0] tile_in_valid;
    reg [TILE_COUNT*4-1:0] tile_on_flat;
    reg [TILE_COUNT*4-1:0] tile_off_flat;
    wire [TILE_COUNT-1:0] tile_in_ready;
    wire [15:0] out_data;
    wire out_valid;
    reg out_ready;
    wire out_last;

    reg [15:0] packet_words [0:31];
    reg packet_last [0:31];
    reg [15:0] stalled_word;
    reg stalled_last;
    integer packet_count;
    integer errors;
    integer timeout_count;
    integer stall_index;
    integer seen_bank_1;
    integer seen_bank_3;

    aer_top #(
        .SENSOR_ROWS(SENSOR_ROWS),
        .SENSOR_COLS(SENSOR_COLS),
        .MAX_BANK_DELTA(31)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat),
        .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .out_data(out_data), .out_valid(out_valid),
        .out_ready(out_ready), .out_last(out_last)
    );

    always #5 clk = ~clk;

    task clear_inputs;
        begin
            tile_in_valid = {TILE_COUNT{1'b0}};
            tile_on_flat = {(TILE_COUNT*4){1'b0}};
            tile_off_flat = {(TILE_COUNT*4){1'b0}};
        end
    endtask

    task drive_two_rows_same_bank;
        begin
            // Bank 0, local tile 0 (row0/col0) and tile 4 (row1/col0).
            // Same cycle -> same base timestamp; should select BANK packet.
            @(negedge clk);
            if (!tile_in_ready[0] || !tile_in_ready[4]) begin
                $display("TB_ERROR: expected tile 0/4 ready");
                errors = errors + 1;
            end
            tile_on_flat[0*4 +: 4] = 4'b0001;
            tile_off_flat[0*4 +: 4] = 4'b1000;
            tile_on_flat[4*4 +: 4] = 4'b0010;
            tile_off_flat[4*4 +: 4] = 4'b0100;
            tile_in_valid[0] = 1'b1;
            tile_in_valid[4] = 1'b1;
            @(negedge clk);
            tile_in_valid[0] = 1'b0;
            tile_in_valid[4] = 1'b0;
        end
    endtask

    task drive_one_full_row;
        begin
            // Bank 0 row 2: local tiles 8,9,10,11. One active row -> ROW packet.
            @(negedge clk);
            tile_on_flat[8*4 +: 4]  = 4'b0001;
            tile_on_flat[9*4 +: 4]  = 4'b0010;
            tile_on_flat[10*4 +: 4] = 4'b0100;
            tile_on_flat[11*4 +: 4] = 4'b1000;
            tile_off_flat[8*4 +: 4]  = 4'b0000;
            tile_off_flat[9*4 +: 4]  = 4'b0000;
            tile_off_flat[10*4 +: 4] = 4'b0000;
            tile_off_flat[11*4 +: 4] = 4'b0000;
            tile_in_valid[8]  = 1'b1;
            tile_in_valid[9]  = 1'b1;
            tile_in_valid[10] = 1'b1;
            tile_in_valid[11] = 1'b1;
            @(negedge clk);
            tile_in_valid[8]  = 1'b0;
            tile_in_valid[9]  = 1'b0;
            tile_in_valid[10] = 1'b0;
            tile_in_valid[11] = 1'b0;
        end
    endtask

    task drive_two_banks;
        begin
            // Bank-major input order: bank 1/local tile 0 and
            // bank 3/local tile 15 are spatially distant sources.
            @(negedge clk);
            if (!tile_in_ready[16] || !tile_in_ready[63]) begin
                $display("TB_ERROR: expected bank 1/3 source tiles ready");
                errors = errors + 1;
            end
            tile_on_flat[16*4 +: 4] = 4'b0101;
            tile_off_flat[16*4 +: 4] = 4'b0010;
            tile_on_flat[63*4 +: 4] = 4'b1000;
            tile_off_flat[63*4 +: 4] = 4'b0001;
            tile_in_valid[16] = 1'b1;
            tile_in_valid[63] = 1'b1;
            @(negedge clk);
            tile_in_valid[16] = 1'b0;
            tile_in_valid[63] = 1'b0;
        end
    endtask

    task wait_for_stalled_output;
        begin
            timeout_count = 0;
            while (!out_valid && (timeout_count < 200)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            if (!out_valid) begin
                $display("TB_ERROR: timed out waiting for stalled top output");
                errors = errors + 1;
            end else begin
                stalled_word = out_data;
                stalled_last = out_last;
                for (stall_index = 0; stall_index < 4; stall_index = stall_index + 1) begin
                    @(posedge clk);
                    #1;
                    if (!out_valid || (out_data !== stalled_word) ||
                        (out_last !== stalled_last)) begin
                        $display("TB_ERROR: top output changed under backpressure");
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    task capture_packet;
        integer done;
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

    task check_last_layout;
        input [31:0] expected_count;
        integer check_index;
        begin
            for (check_index = 0; check_index < expected_count; check_index = check_index + 1) begin
                if (packet_last[check_index] !== (check_index == expected_count - 1)) begin
                    $display("TB_ERROR: out_last mismatch at word %0d", check_index);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        out_ready = 1'b1;
        errors = 0;
        clear_inputs;

        for (stall_index = 0; stall_index < 4; stall_index = stall_index + 1) begin
            @(posedge clk);
        end
        rst_n = 1'b1;
        for (stall_index = 0; stall_index < 2; stall_index = stall_index + 1) begin
            @(posedge clk);
        end

        // TEST 1: multi-row bank packet.
        drive_two_rows_same_bank;
        capture_packet;
        $display("TEST1 packet_count=%0d header=%h mask=%h", packet_count,
                 packet_words[0], packet_words[1]);
        if (packet_count != 5) begin
            $display("TB_ERROR TEST1: expected 5 words, got %0d", packet_count);
            errors = errors + 1;
        end
        if (packet_words[0][15:14] != 2'b10) begin
            $display("TB_ERROR TEST1: expected BANK header type 10, got %b",
                     packet_words[0][15:14]);
            errors = errors + 1;
        end
        if (packet_words[1] != 16'h0011) begin
            $display("TB_ERROR TEST1: expected tile mask 0x0011, got %h",
                     packet_words[1]);
            errors = errors + 1;
        end
        if (packet_words[0] !== 16'h8004) begin
            $display("TB_ERROR TEST1: expected header 0x8004, got %h",
                     packet_words[0]);
            errors = errors + 1;
        end
        if ((packet_words[3] !== 16'h00c0) ||
            (packet_words[4] !== 16'h0120)) begin
            $display("TB_ERROR TEST1: payload mismatch %h %h",
                     packet_words[3], packet_words[4]);
            errors = errors + 1;
        end
        check_last_layout(5);

        for (stall_index = 0; stall_index < 6; stall_index = stall_index + 1) begin
            @(posedge clk);
        end

        // TEST 2: single-row packet.
        drive_one_full_row;
        capture_packet;
        $display("TEST2 packet_count=%0d header=%h", packet_count, packet_words[0]);
        if (packet_count != 6) begin
            $display("TB_ERROR TEST2: expected 6 words, got %0d", packet_count);
            errors = errors + 1;
        end
        if (packet_words[0][15:14] != 2'b11) begin
            $display("TB_ERROR TEST2: expected ROW header type 11, got %b",
                     packet_words[0][15:14]);
            errors = errors + 1;
        end
        if (packet_words[0][3:0] != 4'b1111) begin
            $display("TB_ERROR TEST2: expected row column mask 1111, got %b",
                     packet_words[0][3:0]);
            errors = errors + 1;
        end
        if (packet_words[0] !== 16'hc02f) begin
            $display("TB_ERROR TEST2: expected header 0xc02f, got %h",
                     packet_words[0]);
            errors = errors + 1;
        end
        if ((packet_words[2] !== 16'h0080) ||
            (packet_words[3] !== 16'h0100) ||
            (packet_words[4] !== 16'h0200) ||
            (packet_words[5] !== 16'h0400)) begin
            $display("TB_ERROR TEST2: payload mismatch %h %h %h %h",
                     packet_words[2], packet_words[3],
                     packet_words[4], packet_words[5]);
            errors = errors + 1;
        end
        check_last_layout(6);

        for (stall_index = 0; stall_index < 6; stall_index = stall_index + 1) begin
            @(posedge clk);
        end

        // TEST 3: two bank streams must remain packet-locked while the global
        // output is stalled, and both bank IDs/payloads must be preserved.
        @(negedge clk);
        out_ready = 1'b0;
        drive_two_banks;
        wait_for_stalled_output;
        @(negedge clk);
        out_ready = 1'b1;
        seen_bank_1 = 0;
        seen_bank_3 = 0;

        capture_packet;
        if (packet_count != 3) begin
            $display("TB_ERROR TEST3: first packet expected 3 words, got %0d",
                     packet_count);
            errors = errors + 1;
        end
        check_last_layout(3);
        if (packet_words[0][13:6] == 8'd1) begin
            seen_bank_1 = 1;
            if ((packet_words[0] !== 16'hc041) ||
                (packet_words[2] !== 16'h0290)) begin
                $display("TB_ERROR TEST3: bank 1 packet mismatch %h %h",
                         packet_words[0], packet_words[2]);
                errors = errors + 1;
            end
        end else if (packet_words[0][13:6] == 8'd3) begin
            seen_bank_3 = 1;
            if ((packet_words[0] !== 16'hc0f8) ||
                (packet_words[2] !== 16'h0408)) begin
                $display("TB_ERROR TEST3: bank 3 packet mismatch %h %h",
                         packet_words[0], packet_words[2]);
                errors = errors + 1;
            end
        end else begin
            $display("TB_ERROR TEST3: unexpected first bank ID %0d",
                     packet_words[0][13:6]);
            errors = errors + 1;
        end

        capture_packet;
        if (packet_count != 3) begin
            $display("TB_ERROR TEST3: second packet expected 3 words, got %0d",
                     packet_count);
            errors = errors + 1;
        end
        check_last_layout(3);
        if (packet_words[0][13:6] == 8'd1) begin
            seen_bank_1 = 1;
            if ((packet_words[0] !== 16'hc041) ||
                (packet_words[2] !== 16'h0290)) begin
                $display("TB_ERROR TEST3: bank 1 packet mismatch %h %h",
                         packet_words[0], packet_words[2]);
                errors = errors + 1;
            end
        end else if (packet_words[0][13:6] == 8'd3) begin
            seen_bank_3 = 1;
            if ((packet_words[0] !== 16'hc0f8) ||
                (packet_words[2] !== 16'h0408)) begin
                $display("TB_ERROR TEST3: bank 3 packet mismatch %h %h",
                         packet_words[0], packet_words[2]);
                errors = errors + 1;
            end
        end else begin
            $display("TB_ERROR TEST3: unexpected second bank ID %0d",
                     packet_words[0][13:6]);
            errors = errors + 1;
        end

        if (!seen_bank_1 || !seen_bank_3) begin
            $display("TB_ERROR TEST3: did not observe both bank 1 and bank 3");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("AER_ADAPTIVE_PACKET_TB_PASS");
        else
            $display("AER_ADAPTIVE_PACKET_TB_FAIL errors=%0d", errors);

        #20;
        $finish;
    end
endmodule
