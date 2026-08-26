`timescale 1ns/1ps

module tb_aer_v1_uzh #(
    parameter integer CLK_HALF_PERIOD_NS = 5
);

    localparam integer TILE_COUNT = 4096;
    localparam integer MAX_GROUPS = 200000;

    reg            clk;
    reg            rst_n;
    reg  [4095:0]  tile_in_valid;
    reg  [16383:0] tile_on_flat;
    reg  [16383:0] tile_off_flat;
    wire [4095:0]  tile_in_ready;
    wire [15:0]    out_data;
    wire           out_valid;
    reg            out_ready;
    wire           out_last;

    integer group_id_mem [0:MAX_GROUPS-1];
    integer group_cycle_mem [0:MAX_GROUPS-1];
    integer group_tile_mem [0:MAX_GROUPS-1];
    reg [3:0] group_on_mem [0:MAX_GROUPS-1];
    reg [3:0] group_off_mem [0:MAX_GROUPS-1];
    integer group_event_count_mem [0:MAX_GROUPS-1];
    integer next_group_mem [0:MAX_GROUPS-1];

    integer tile_head [0:TILE_COUNT-1];
    integer tile_tail [0:TILE_COUNT-1];
    integer active_group [0:TILE_COUNT-1];

    reg [8*1024-1:0] vector_path;
    reg [8*1024-1:0] log_path;
    integer vector_fd;
    integer log_fd;
    integer scan_count;
    integer group_count;
    integer accepted_count;
    integer decoded_group_count;
    integer output_word_count;
    integer data_cycle;
    integer max_cycles;
    integer timeout;
    integer drive_tile_index;
    integer drive_group_index;
    integer accept_tile_index;
    integer accept_group_index;
    integer load_tile_index;
    integer previous_group;

    integer rx_phase;
    integer rx_data_remaining;

    aer_v1_top_128 dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .tile_in_valid (tile_in_valid),
        .tile_on_flat  (tile_on_flat),
        .tile_off_flat (tile_off_flat),
        .tile_in_ready (tile_in_ready),
        .out_data      (out_data),
        .out_valid     (out_valid),
        .out_ready     (out_ready),
        .out_last      (out_last)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_HALF_PERIOD_NS) clk = ~clk;
    end

    function integer popcount4;
        input [3:0] value;
        integer bit_index;
        begin
            popcount4 = 0;
            for (bit_index = 0; bit_index < 4; bit_index = bit_index + 1)
                popcount4 = popcount4 + value[bit_index];
        end
    endfunction

    always @(negedge clk) begin
        if (!rst_n) begin
            tile_in_valid = 4096'b0;
            tile_on_flat  = 16384'b0;
            tile_off_flat = 16384'b0;
        end else begin
            for (drive_tile_index = 0; drive_tile_index < TILE_COUNT;
                 drive_tile_index = drive_tile_index + 1) begin
                if ((active_group[drive_tile_index] < 0) &&
                    (tile_head[drive_tile_index] >= 0) &&
                    (group_cycle_mem[tile_head[drive_tile_index]] <= data_cycle))
                    active_group[drive_tile_index] = tile_head[drive_tile_index];

                if (active_group[drive_tile_index] >= 0) begin
                    drive_group_index = active_group[drive_tile_index];
                    tile_in_valid[drive_tile_index] = 1'b1;
                    tile_on_flat[drive_tile_index*4 +: 4] = group_on_mem[drive_group_index];
                    tile_off_flat[drive_tile_index*4 +: 4] = group_off_mem[drive_group_index];
                end else begin
                    tile_in_valid[drive_tile_index] = 1'b0;
                    tile_on_flat[drive_tile_index*4 +: 4] = 4'b0;
                    tile_off_flat[drive_tile_index*4 +: 4] = 4'b0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            for (accept_tile_index = 0; accept_tile_index < TILE_COUNT;
                 accept_tile_index = accept_tile_index + 1) begin
                if (tile_in_valid[accept_tile_index] && tile_in_ready[accept_tile_index]) begin
                    accept_group_index = active_group[accept_tile_index];
                    if (accept_group_index < 0) begin
                        $display("AER_V1_UZH_DRIVER_STATE_FAIL tile=%0d", accept_tile_index);
                        $fatal(1);
                    end
                    $fdisplay(log_fd, "A %0d %0d %0d %0d %01h %01h %0d",
                        group_id_mem[accept_group_index],
                        group_cycle_mem[accept_group_index],
                        data_cycle,
                        accept_tile_index,
                        group_on_mem[accept_group_index],
                        group_off_mem[accept_group_index],
                        group_event_count_mem[accept_group_index]);
                    tile_head[accept_tile_index] = next_group_mem[accept_group_index];
                    active_group[accept_tile_index] = -1;
                    accepted_count = accepted_count + 1;
                end
            end

            if (out_valid && out_ready) begin
                $fdisplay(log_fd, "W %0d %04h %0d", data_cycle, out_data, out_last);
                output_word_count = output_word_count + 1;
                if (rx_phase == 0) begin
                    if (out_data[15:14] != 2'b11) begin
                        $display("AER_V1_UZH_HEADER_FAIL word=%h", out_data);
                        $fatal(1);
                    end
                    rx_data_remaining = popcount4(out_data[3:0]);
                    rx_phase = 1;
                end else if (rx_phase == 1) begin
                    rx_phase = 2;
                end else begin
                    decoded_group_count = decoded_group_count + 1;
                    rx_data_remaining = rx_data_remaining - 1;
                    if (rx_data_remaining == 0) begin
                        if (!out_last) begin
                            $display("AER_V1_UZH_LAST_MISSING word=%h", out_data);
                            $fatal(1);
                        end
                        rx_phase = 0;
                    end else if (out_last) begin
                        $display("AER_V1_UZH_LAST_EARLY word=%h", out_data);
                        $fatal(1);
                    end
                end
            end
            data_cycle = data_cycle + 1;
        end
    end

    initial begin
        rst_n               = 1'b0;
        tile_in_valid       = 4096'b0;
        tile_on_flat        = 16384'b0;
        tile_off_flat       = 16384'b0;
        out_ready           = 1'b1;
        group_count         = 0;
        accepted_count      = 0;
        decoded_group_count = 0;
        output_word_count   = 0;
        data_cycle          = 0;
        rx_phase            = 0;
        rx_data_remaining   = 0;
        max_cycles          = 1000000;

        if (!$value$plusargs("VECTOR=%s", vector_path))
            vector_path = "vectors.txt";
        if (!$value$plusargs("LOG=%s", log_path))
            log_path = "rtl_events.log";
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 1000000;

        for (load_tile_index = 0; load_tile_index < TILE_COUNT;
             load_tile_index = load_tile_index + 1) begin
            tile_head[load_tile_index] = -1;
            tile_tail[load_tile_index] = -1;
            active_group[load_tile_index] = -1;
        end

        vector_fd = $fopen(vector_path, "r");
        if (vector_fd == 0) begin
            $display("AER_V1_UZH_VECTOR_OPEN_FAIL path=%0s", vector_path);
            $fatal(1);
        end

        while (!$feof(vector_fd)) begin
            if (group_count >= MAX_GROUPS) begin
                $display("AER_V1_UZH_TOO_MANY_GROUPS max=%0d", MAX_GROUPS);
                $fatal(1);
            end
            scan_count = $fscanf(vector_fd, "%d %d %d %h %h %d\n",
                group_id_mem[group_count],
                group_cycle_mem[group_count],
                group_tile_mem[group_count],
                group_on_mem[group_count],
                group_off_mem[group_count],
                group_event_count_mem[group_count]);
            if (scan_count == 6) begin
                if ((group_tile_mem[group_count] < 0) ||
                    (group_tile_mem[group_count] >= TILE_COUNT)) begin
                    $display("AER_V1_UZH_TILE_RANGE_FAIL tile=%0d",
                        group_tile_mem[group_count]);
                    $fatal(1);
                end
                next_group_mem[group_count] = -1;
                load_tile_index = group_tile_mem[group_count];
                previous_group = tile_tail[load_tile_index];
                if (previous_group < 0)
                    tile_head[load_tile_index] = group_count;
                else
                    next_group_mem[previous_group] = group_count;
                tile_tail[load_tile_index] = group_count;
                group_count = group_count + 1;
            end else if (scan_count != -1) begin
                $display("AER_V1_UZH_VECTOR_PARSE_FAIL fields=%0d group=%0d",
                    scan_count, group_count);
                $fatal(1);
            end
        end
        $fclose(vector_fd);

        if (group_count == 0) begin
            $display("AER_V1_UZH_EMPTY_VECTOR");
            $fatal(1);
        end

        log_fd = $fopen(log_path, "w");
        if (log_fd == 0) begin
            $display("AER_V1_UZH_LOG_OPEN_FAIL path=%0s", log_path);
            $fatal(1);
        end
        $fdisplay(log_fd, "M %0d", group_count);

        repeat (5) @(posedge clk);
        #1 rst_n = 1'b1;

        timeout = 0;
        while ((decoded_group_count < group_count) && (timeout < max_cycles)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (decoded_group_count != group_count) begin
            $display(
                "AER_V1_UZH_TIMEOUT groups=%0d accepted=%0d decoded=%0d cycles=%0d",
                group_count, accepted_count, decoded_group_count, data_cycle);
            $fatal(1);
        end
        if (accepted_count != group_count || rx_phase != 0) begin
            $display(
                "AER_V1_UZH_COUNT_FAIL groups=%0d accepted=%0d decoded=%0d phase=%0d",
                group_count, accepted_count, decoded_group_count, rx_phase);
            $fatal(1);
        end

        $fdisplay(log_fd, "D %0d %0d %0d", accepted_count,
            decoded_group_count, output_word_count);
        $fclose(log_fd);
        $display(
            "AER_V1_UZH_PASS groups=%0d words=%0d cycles=%0d",
            group_count, output_word_count, data_cycle);
        $finish;
    end

endmodule
