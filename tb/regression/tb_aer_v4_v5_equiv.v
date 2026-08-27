`timescale 1ns/1ps

module tb_aer_v4_v5_equiv;
    reg clk;
    reg rst_n;
    reg [4095:0] tile_in_valid;
    reg [16383:0] tile_on_flat;
    reg [16383:0] tile_off_flat;
    reg out_ready;

    wire [4095:0] tile_in_ready_v4;
    wire [15:0] out_data_v4;
    wire out_valid_v4;
    wire out_last_v4;

    wire [4095:0] tile_in_ready_v5;
    wire [15:0] out_data_v5;
    wire out_valid_v5;
    wire out_last_v5;

    integer cycle_count;
    integer error_count;
    integer sparse_packet_count;
    integer row_packet_count;
    integer backpressure_hold_cycles;
    integer compare_index;
    integer first_ready_mismatch;
    integer scenario_error_start;
    integer scenario_packet_start;
    integer scenario_stall_start;
    reg packet_start;

    aer_top_v4_128 dut_v4 (
        .clk(clk),
        .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat),
        .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready_v4),
        .out_data(out_data_v4),
        .out_valid(out_valid_v4),
        .out_ready(out_ready),
        .out_last(out_last_v4)
    );

    aer_top_v5_128 dut_v5 (
        .clk(clk),
        .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat),
        .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready_v5),
        .out_data(out_data_v5),
        .out_valid(out_valid_v5),
        .out_ready(out_ready),
        .out_last(out_last_v5)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Cycle-level comparison and packet-type accounting.
    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            packet_start = 1'b1;
        end else begin
            cycle_count = cycle_count + 1;

            if (tile_in_ready_v4 !== tile_in_ready_v5) begin
                first_ready_mismatch = -1;
                for (compare_index = 0; compare_index < 4096;
                     compare_index = compare_index + 1) begin
                    if ((first_ready_mismatch < 0) &&
                        (tile_in_ready_v4[compare_index] !==
                         tile_in_ready_v5[compare_index])) begin
                        first_ready_mismatch = compare_index;
                    end
                end
                $display("AER_V4_V5_READY_MISMATCH cycle=%0d tile=%0d v4=%b v5=%b",
                         cycle_count,
                         first_ready_mismatch,
                         tile_in_ready_v4[first_ready_mismatch],
                         tile_in_ready_v5[first_ready_mismatch]);
                error_count = error_count + 1;
            end

            if (out_valid_v4 !== out_valid_v5) begin
                $display("AER_V4_V5_VALID_MISMATCH cycle=%0d v4=%b v5=%b",
                         cycle_count, out_valid_v4, out_valid_v5);
                error_count = error_count + 1;
            end

            if (out_valid_v4 && out_valid_v5) begin
                if (out_data_v4 !== out_data_v5) begin
                    $display("AER_V4_V5_DATA_MISMATCH cycle=%0d v4=%04h v5=%04h",
                             cycle_count, out_data_v4, out_data_v5);
                    error_count = error_count + 1;
                end
                if (out_last_v4 !== out_last_v5) begin
                    $display("AER_V4_V5_LAST_MISMATCH cycle=%0d v4=%b v5=%b",
                             cycle_count, out_last_v4, out_last_v5);
                    error_count = error_count + 1;
                end

                if (!out_ready)
                    backpressure_hold_cycles = backpressure_hold_cycles + 1;

                if (out_ready) begin
                    if (packet_start) begin
                        if (out_data_v4[15] == 1'b0) begin
                            sparse_packet_count = sparse_packet_count + 1;
                        end else if (out_data_v4[15:14] == 2'b11) begin
                            row_packet_count = row_packet_count + 1;
                        end else begin
                            $display("AER_V4_V5_BAD_PACKET_HEADER cycle=%0d data=%04h",
                                     cycle_count, out_data_v4);
                            error_count = error_count + 1;
                        end
                    end
                    packet_start = out_last_v4;
                end
            end
        end
    end

    task send_sparse_event;
        input integer bank_id;
        input integer local_tile;
        input [3:0] on_bits;
        input [3:0] off_bits;
        integer flat_tile;
        begin
            flat_tile = bank_id * 16 + local_tile;
            while (!(tile_in_ready_v4[flat_tile] &&
                     tile_in_ready_v5[flat_tile])) begin
                @(posedge clk);
            end
            @(negedge clk);
            tile_in_valid[flat_tile] = 1'b1;
            tile_on_flat[flat_tile*4 +: 4] = on_bits;
            tile_off_flat[flat_tile*4 +: 4] = off_bits;
            @(negedge clk);
            tile_in_valid = 4096'b0;
            tile_on_flat = 16384'b0;
            tile_off_flat = 16384'b0;
        end
    endtask

    // Three singleton tiles make ROW cost 5 words versus SPARSE cost 6 words.
    task send_three_tile_row;
        input integer bank_id;
        input integer local_row;
        integer first_tile;
        begin
            first_tile = bank_id * 16 + local_row * 4;
            while (!(tile_in_ready_v4[first_tile] &&
                     tile_in_ready_v5[first_tile] &&
                     tile_in_ready_v4[first_tile+1] &&
                     tile_in_ready_v5[first_tile+1] &&
                     tile_in_ready_v4[first_tile+2] &&
                     tile_in_ready_v5[first_tile+2])) begin
                @(posedge clk);
            end
            @(negedge clk);
            tile_in_valid[first_tile] = 1'b1;
            tile_in_valid[first_tile+1] = 1'b1;
            tile_in_valid[first_tile+2] = 1'b1;
            tile_on_flat[first_tile*4 +: 4] = 4'b0001;
            tile_off_flat[(first_tile+1)*4 +: 4] = 4'b0010;
            tile_on_flat[(first_tile+2)*4 +: 4] = 4'b0100;
            @(negedge clk);
            tile_in_valid = 4096'b0;
            tile_on_flat = 16384'b0;
            tile_off_flat = 16384'b0;
        end
    endtask

    // Same-cycle events in Regions 0, 1, 5, 10, and 15.
    task send_simultaneous_multi_region;
        begin
            while (!(tile_in_ready_v4[1] && tile_in_ready_v5[1] &&
                     tile_in_ready_v4[66] && tile_in_ready_v5[66] &&
                     tile_in_ready_v4[1091] && tile_in_ready_v5[1091] &&
                     tile_in_ready_v4[2180] && tile_in_ready_v5[2180] &&
                     tile_in_ready_v4[3269] && tile_in_ready_v5[3269])) begin
                @(posedge clk);
            end
            @(negedge clk);
            tile_in_valid[1] = 1'b1;       // Bank 0, Region 0
            tile_in_valid[66] = 1'b1;      // Bank 4, Region 1
            tile_in_valid[1091] = 1'b1;    // Bank 68, Region 5
            tile_in_valid[2180] = 1'b1;    // Bank 136, Region 10
            tile_in_valid[3269] = 1'b1;    // Bank 204, Region 15
            tile_on_flat[1*4 +: 4] = 4'b0001;
            tile_off_flat[66*4 +: 4] = 4'b0010;
            tile_on_flat[1091*4 +: 4] = 4'b0100;
            tile_off_flat[2180*4 +: 4] = 4'b1000;
            tile_on_flat[3269*4 +: 4] = 4'b0010;
            @(negedge clk);
            tile_in_valid = 4096'b0;
            tile_on_flat = 16384'b0;
            tile_off_flat = 16384'b0;
        end
    endtask

    task wait_for_drain;
        integer drain_cycles;
        integer idle_cycles;
        begin
            drain_cycles = 0;
            idle_cycles = 0;
            while ((idle_cycles < 12) && (drain_cycles < 1000)) begin
                @(negedge clk);
                drain_cycles = drain_cycles + 1;
                if ((&tile_in_ready_v4) && (&tile_in_ready_v5) &&
                    !out_valid_v4 && !out_valid_v5) begin
                    idle_cycles = idle_cycles + 1;
                end else begin
                    idle_cycles = 0;
                end
            end
            if (idle_cycles < 12) begin
                $display("AER_V4_V5_DRAIN_TIMEOUT cycle=%0d", cycle_count);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        tile_in_valid = 4096'b0;
        tile_on_flat = 16384'b0;
        tile_off_flat = 16384'b0;
        out_ready = 1'b1;
        cycle_count = 0;
        error_count = 0;
        sparse_packet_count = 0;
        row_packet_count = 0;
        backpressure_hold_cycles = 0;
        packet_start = 1'b1;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Scenario A: singleton ON/OFF traffic in five spatial regions.
        scenario_error_start = error_count;
        scenario_packet_start = sparse_packet_count;
        send_sparse_event(0,   0, 4'b0001, 4'b0000);
        send_sparse_event(4,   0, 4'b0000, 4'b0010);
        send_sparse_event(68,  0, 4'b0100, 4'b0000);
        send_sparse_event(136, 0, 4'b0000, 4'b1000);
        send_sparse_event(204, 0, 4'b0010, 4'b0000);
        wait_for_drain;
        if ((error_count == scenario_error_start) &&
            (sparse_packet_count >= scenario_packet_start + 5)) begin
            $display("AER_V4_V5_SPARSE_EQUIV_PASS packets=%0d",
                     sparse_packet_count - scenario_packet_start);
        end else begin
            $display("AER_V4_V5_SPARSE_EQUIV_FAIL");
            error_count = error_count + 1;
        end

        // Scenario B: one guaranteed ROW-mode selection.
        scenario_error_start = error_count;
        scenario_packet_start = row_packet_count;
        send_three_tile_row(85, 1);
        wait_for_drain;
        if ((error_count == scenario_error_start) &&
            (row_packet_count >= scenario_packet_start + 1)) begin
            $display("AER_V4_V5_ROW_EQUIV_PASS packets=%0d",
                     row_packet_count - scenario_packet_start);
        end else begin
            $display("AER_V4_V5_ROW_EQUIV_FAIL");
            error_count = error_count + 1;
        end

        // Scenario C: five regions request service on the same cycle.
        scenario_error_start = error_count;
        scenario_packet_start = sparse_packet_count;
        send_simultaneous_multi_region;
        wait_for_drain;
        if ((error_count == scenario_error_start) &&
            (sparse_packet_count >= scenario_packet_start + 5)) begin
            $display("AER_V4_V5_MULTI_REGION_EQUIV_PASS packets=%0d",
                     sparse_packet_count - scenario_packet_start);
        end else begin
            $display("AER_V4_V5_MULTI_REGION_EQUIV_FAIL");
            error_count = error_count + 1;
        end

        // Scenario D: stall an active ROW packet for six cycles.
        scenario_error_start = error_count;
        scenario_stall_start = backpressure_hold_cycles;
        send_three_tile_row(170, 0);
        while (!(out_valid_v4 && out_valid_v5)) @(posedge clk);
        @(negedge clk);
        out_ready = 1'b0;
        repeat (6) @(posedge clk);
        @(negedge clk);
        out_ready = 1'b1;
        wait_for_drain;
        if ((error_count == scenario_error_start) &&
            (backpressure_hold_cycles > scenario_stall_start)) begin
            $display("AER_V4_V5_BACKPRESSURE_EQUIV_PASS stalled_cycles=%0d",
                     backpressure_hold_cycles - scenario_stall_start);
        end else begin
            $display("AER_V4_V5_BACKPRESSURE_EQUIV_FAIL");
            error_count = error_count + 1;
        end

        if (error_count == 0) begin
            $display("AER_V4_V5_READY_EQUIV_PASS");
            $display("AER_V4_V5_OUTPUT_EQUIV_PASS sparse=%0d row=%0d",
                     sparse_packet_count, row_packet_count);
            $display("AER_V4_V5_EQUIV_PASS");
            $finish;
        end else begin
            $display("AER_V4_V5_EQUIV_FAIL errors=%0d", error_count);
            $fatal(1);
        end
    end

    initial begin
        #50000;
        $display("AER_V4_V5_EQUIV_FAIL timeout");
        $fatal(1);
    end
endmodule
