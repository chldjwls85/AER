`timescale 1ns/1ps

// Reset recovery, random backpressure, packet locking, and sustained
// four-bank contention test on a compact 16x16 instance.
module tb_aer_protocol_stress;
    localparam integer TARGET_PER_BANK = 16;

    reg clk;
    reg rst_n;
    reg [63:0] tile_in_valid;
    reg [255:0] tile_on_flat;
    reg [255:0] tile_off_flat;
    wire [63:0] tile_in_ready;
    wire [15:0] out_data;
    wire out_valid;
    reg out_ready;
    wire out_last;

    integer accepted [0:3];
    integer packets [0:3];
    integer errors;
    integer bank_index;
    integer total_packets;
    integer timeout_count;
    integer current_bank;
    integer packet_words;
    reg in_packet;
    reg monitor_enable;
    reg random_ready_enable;
    reg [15:0] ready_lfsr;
    reg stalled_valid;
    reg stalled_ready;
    reg [15:0] stalled_data;
    reg stalled_last;

`ifdef V4_DESIGN
    aer_top_v4 #(
`else
    aer_top #(
`endif
        .SENSOR_ROWS(16),
        .SENSOR_COLS(16),
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

    always @(negedge clk) begin
        if (!rst_n) begin
            ready_lfsr <= 16'hb4d3;
        end else if (random_ready_enable) begin
            ready_lfsr <= {ready_lfsr[14:0],
                           ready_lfsr[15] ^ ready_lfsr[13] ^
                           ready_lfsr[12] ^ ready_lfsr[10]};
            out_ready <= ready_lfsr[0] | ready_lfsr[2];
        end
    end

    always @(posedge clk) begin
        if (rst_n && monitor_enable) begin
            for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
                if (tile_in_valid[bank_index*16] && tile_in_ready[bank_index*16])
                    accepted[bank_index] = accepted[bank_index] + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && monitor_enable && stalled_valid && !stalled_ready) begin
            if (!out_valid || out_data !== stalled_data || out_last !== stalled_last) begin
                $display("PROTOCOL_ERROR output changed under backpressure");
                errors = errors + 1;
            end
        end
        stalled_valid = out_valid;
        stalled_ready = out_ready;
        stalled_data = out_data;
        stalled_last = out_last;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            in_packet = 1'b0;
            packet_words = 0;
            current_bank = -1;
        end else if (monitor_enable && out_valid && out_ready) begin
            if (!in_packet) begin
                if (out_data[15:14] != 2'b11) begin
                    $display("PROTOCOL_ERROR expected single-tile ROW header got=%h", out_data);
                    errors = errors + 1;
                end
                current_bank = out_data[13:6];
                if (current_bank < 0 || current_bank > 3) begin
                    $display("PROTOCOL_ERROR invalid bank ID %0d", current_bank);
                    errors = errors + 1;
                end
                in_packet = 1'b1;
                packet_words = 1;
            end else begin
                packet_words = packet_words + 1;
            end

            if (out_last) begin
                if (packet_words != 3) begin
                    $display("PROTOCOL_ERROR bank=%0d packet words=%0d", current_bank, packet_words);
                    errors = errors + 1;
                end
                if (current_bank >= 0 && current_bank <= 3)
                    packets[current_bank] = packets[current_bank] + 1;
                total_packets = total_packets + 1;
                in_packet = 1'b0;
                packet_words = 0;
                current_bank = -1;
            end
        end
    end

    task clear_inputs;
        begin
            tile_in_valid = 64'b0;
            tile_on_flat = 256'b0;
            tile_off_flat = 256'b0;
        end
    endtask

    task inject_single;
        input integer tile_id;
        input [3:0] on_bits;
        input [3:0] off_bits;
        begin
            @(negedge clk);
            tile_on_flat[tile_id*4 +: 4] = on_bits;
            tile_off_flat[tile_id*4 +: 4] = off_bits;
            tile_in_valid[tile_id] = 1'b1;
            @(negedge clk);
            tile_in_valid[tile_id] = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        out_ready = 1'b1;
        monitor_enable = 1'b0;
        random_ready_enable = 1'b0;
        ready_lfsr = 16'hb4d3;
        stalled_valid = 1'b0;
        stalled_ready = 1'b0;
        stalled_data = 16'b0;
        stalled_last = 1'b0;
        in_packet = 1'b0;
        packet_words = 0;
        current_bank = -1;
        total_packets = 0;
        errors = 0;
        clear_inputs;
        for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
            accepted[bank_index] = 0;
            packets[bank_index] = 0;
        end

        // Idle reset and recovery.
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        if (out_valid) begin
            $display("PROTOCOL_ERROR output valid after idle reset");
            errors = errors + 1;
        end

        // Packet-before and packet-midstream reset. Pending data is specified
        // to flush on reset; only clean post-reset recovery is required.
        out_ready = 1'b0;
        inject_single(0, 4'h1, 4'h0);
        timeout_count = 0;
        while (!out_valid && timeout_count < 100) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (!out_valid) begin
            $display("PROTOCOL_ERROR no output before mid-packet reset");
            errors = errors + 1;
        end
        @(negedge clk);
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        if (out_valid || out_last) begin
            $display("PROTOCOL_ERROR stream not cleared by reset");
            errors = errors + 1;
        end
        @(negedge clk);
        rst_n = 1'b1;
        out_ready = 1'b1;
        repeat (3) @(posedge clk);
        inject_single(16, 4'h2, 4'h4);
        timeout_count = 0;
        while (!(out_valid && out_ready && out_last) && timeout_count < 200) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (timeout_count >= 200) begin
            $display("PROTOCOL_ERROR post-reset recovery packet timeout");
            errors = errors + 1;
        end
        repeat (4) @(posedge clk);

        // Long contention: continuously refill the same tile in all 4 banks.
        clear_inputs;
        for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
            accepted[bank_index] = 0;
            packets[bank_index] = 0;
            tile_on_flat[(bank_index*16)*4 +: 4] = 4'b0001 << bank_index;
            tile_off_flat[(bank_index*16)*4 +: 4] = 4'b1000 >> bank_index;
        end
        total_packets = 0;
        monitor_enable = 1'b1;
        random_ready_enable = 1'b1;
        timeout_count = 0;
        while ((total_packets < TARGET_PER_BANK*4) && timeout_count < 20000) begin
            @(negedge clk);
            for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1)
                tile_in_valid[bank_index*16] = (accepted[bank_index] < TARGET_PER_BANK);
            timeout_count = timeout_count + 1;
        end
        @(negedge clk);
        tile_in_valid = 64'b0;
        random_ready_enable = 1'b0;
        out_ready = 1'b1;
        timeout_count = 0;
        while ((total_packets < TARGET_PER_BANK*4) && timeout_count < 5000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        monitor_enable = 1'b0;

        if (total_packets != TARGET_PER_BANK*4) begin
            $display("PROTOCOL_ERROR contention timeout packets=%0d", total_packets);
            errors = errors + 1;
        end
        for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
            if (accepted[bank_index] != TARGET_PER_BANK) begin
                $display("PROTOCOL_ERROR bank=%0d accepted=%0d", bank_index, accepted[bank_index]);
                errors = errors + 1;
            end
            if (packets[bank_index] != TARGET_PER_BANK) begin
                $display("PROTOCOL_ERROR bank=%0d packets=%0d", bank_index, packets[bank_index]);
                errors = errors + 1;
            end
        end
        if (in_packet) begin
            $display("PROTOCOL_ERROR ended inside packet");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("AER_PROTOCOL_STRESS_PASS accepted=64 packets=64");
        else
            $display("AER_PROTOCOL_STRESS_FAIL errors=%0d packets=%0d",
                     errors, total_packets);
        #20;
        $finish;
    end
endmodule
