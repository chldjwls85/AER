`timescale 1ns/1ps

module tb_aer_v1_cifar_pending #(
    parameter integer CLK_HALF_PERIOD_NS = 5,
    parameter integer ENABLE_BINNING = 1,
    parameter integer ENABLE_ROW_FUSION = 0,
    parameter integer ENABLE_BANK_FUSION = 0,
    parameter integer ENABLE_LOSSY_BINNING = 0,
    parameter integer ENABLE_SPARSE = 0,
    parameter integer USE_SHARED_ARCH = 0,
    parameter integer PIXEL_FIFO_DEPTH = 1
);

    localparam integer SENSOR_ROWS = 128;
    localparam integer SENSOR_COLS = 128;
    localparam integer PIXEL_COUNT = SENSOR_ROWS * SENSOR_COLS;
    localparam integer TILE_COUNT = (SENSOR_ROWS/2) * (SENSOR_COLS/2);
    localparam integer MAX_EVENTS = 200000;

    reg clk;
    reg rst_n;
    reg [PIXEL_COUNT-1:0] pixel_event_on;
    reg [PIXEL_COUNT-1:0] pixel_event_off;
    wire [TILE_COUNT-1:0] tile_valid;
    wire [TILE_COUNT*4-1:0] tile_on_flat;
    wire [TILE_COUNT*4-1:0] tile_off_flat;
    wire [TILE_COUNT-1:0] tile_ready;
    wire [31:0] pixel_accepted_count;
    wire [31:0] pixel_ignored_count;
    wire [31:0] pixel_readout_count;
    wire [15:0] out_data;
    wire out_valid;
    reg out_ready;
    wire out_last;

    integer event_id_mem [0:MAX_EVENTS-1];
    integer event_cycle_mem [0:MAX_EVENTS-1];
    integer event_x_mem [0:MAX_EVENTS-1];
    integer event_y_mem [0:MAX_EVENTS-1];
    integer event_polarity_mem [0:MAX_EVENTS-1];
    integer event_elapsed_ns_mem [0:MAX_EVENTS-1];

    reg [8*1024-1:0] vector_path;
    reg [8*1024-1:0] log_path;
    integer vector_fd;
    integer log_fd;
    integer scan_count;
    integer event_count;
    integer event_cursor;
    integer injected_event_count;
    integer same_cycle_duplicate_count;
    integer accepted_tile_count;
    integer decoded_tile_count;
    integer output_word_count;
    integer data_cycle;
    integer max_cycles;
    integer timeout;
    integer stable_cycles;
    integer drive_event_index;
    integer drive_pixel_index;
    integer accept_tile_index;
    integer rx_phase;
    integer rx_data_remaining;
    integer rx_consumed;
    integer rx_header_columns;
    integer rx_bank_mode;
    integer rx_bank_count;
    integer rx_bank_mask_count;
    integer rx_bank_bin_count;
    integer rx_bank_raw_count;
    integer rx_bank_words_remaining;
    reg [15:0] rx_bank_mask;

    aer_pixel_pending_array #(
        .SENSOR_ROWS(SENSOR_ROWS),
        .SENSOR_COLS(SENSOR_COLS),
        .PIXEL_FIFO_DEPTH(PIXEL_FIFO_DEPTH)
    ) pixel_frontend_i (
        .clk                  (clk),
        .rst_n                (rst_n),
        .event_on             (pixel_event_on),
        .event_off            (pixel_event_off),
        .tile_valid           (tile_valid),
        .tile_on_flat         (tile_on_flat),
        .tile_off_flat        (tile_off_flat),
        .tile_ready           (tile_ready),
        .accepted_event_count (pixel_accepted_count),
        .ignored_event_count  (pixel_ignored_count),
        .readout_event_count  (pixel_readout_count)
    );

    generate
        if (USE_SHARED_ARCH != 0) begin : gen_shared_dut
            aer_v1_shared_top_128 #(
                .ENABLE_COMPRESSION(ENABLE_BINNING)
            ) dut (
                .clk           (clk),
                .rst_n         (rst_n),
                .tile_in_valid (tile_valid),
                .tile_on_flat  (tile_on_flat),
                .tile_off_flat (tile_off_flat),
                .tile_in_ready (tile_ready),
                .out_data      (out_data),
                .out_valid     (out_valid),
                .out_ready     (out_ready),
                .out_last      (out_last)
            );
        end else begin : gen_legacy_dut
            aer_v1_top_128 #(
                .ENABLE_BINNING(ENABLE_BINNING),
                .ENABLE_ROW_FUSION(ENABLE_ROW_FUSION),
                .ENABLE_BANK_FUSION(ENABLE_BANK_FUSION),
                .ENABLE_LOSSY_BINNING(ENABLE_LOSSY_BINNING),
                .ENABLE_SPARSE(ENABLE_SPARSE),
                .EXTERNAL_RX_TIMESTAMP(1)
            ) dut (
                .clk           (clk),
                .rst_n         (rst_n),
                .tile_in_valid (tile_valid),
                .tile_on_flat  (tile_on_flat),
                .tile_off_flat (tile_off_flat),
                .tile_in_ready (tile_ready),
                .out_data      (out_data),
                .out_valid     (out_valid),
                .out_ready     (out_ready),
                .out_last      (out_last)
            );
        end
    endgenerate

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

    function integer popcount16;
        input [15:0] value;
        integer bit_index;
        begin
            popcount16 = 0;
            for (bit_index = 0; bit_index < 16; bit_index = bit_index + 1)
                popcount16 = popcount16 + value[bit_index];
        end
    endfunction

    // Replay every serialized dataset event at its quantized source cycle.
    // Multiple pixels may assert in the same cycle.  An exact duplicate that
    // cannot be represented by a parallel request bit is counted explicitly.
    always @(negedge clk) begin
        pixel_event_on = {PIXEL_COUNT{1'b0}};
        pixel_event_off = {PIXEL_COUNT{1'b0}};
        if (rst_n) begin
            while ((event_cursor < event_count) &&
                   (event_cycle_mem[event_cursor] <= data_cycle)) begin
                drive_event_index = event_cursor;
                drive_pixel_index =
                    event_y_mem[drive_event_index] * SENSOR_COLS +
                    event_x_mem[drive_event_index];
                if (event_polarity_mem[drive_event_index] != 0) begin
                    if (pixel_event_on[drive_pixel_index])
                        same_cycle_duplicate_count =
                            same_cycle_duplicate_count + 1;
                    else
                        pixel_event_on[drive_pixel_index] = 1'b1;
                end else begin
                    if (pixel_event_off[drive_pixel_index])
                        same_cycle_duplicate_count =
                            same_cycle_duplicate_count + 1;
                    else
                        pixel_event_off[drive_pixel_index] = 1'b1;
                end
                injected_event_count = injected_event_count + 1;
                event_cursor = event_cursor + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            for (accept_tile_index = 0; accept_tile_index < TILE_COUNT;
                 accept_tile_index = accept_tile_index + 1) begin
                if (tile_valid[accept_tile_index] && tile_ready[accept_tile_index]) begin
                    $fdisplay(log_fd, "A %0d %0d %0d %0d %01h %01h %0d",
                        accepted_tile_count,
                        data_cycle,
                        data_cycle,
                        accept_tile_index,
                        tile_on_flat[accept_tile_index*4 +: 4],
                        tile_off_flat[accept_tile_index*4 +: 4],
                        popcount4(tile_on_flat[accept_tile_index*4 +: 4]) +
                        popcount4(tile_off_flat[accept_tile_index*4 +: 4]));
                    accepted_tile_count = accepted_tile_count + 1;
                end
            end

            if (out_valid && out_ready) begin
                $fdisplay(log_fd, "W %0d %04h %0d", data_cycle, out_data, out_last);
                output_word_count = output_word_count + 1;
                if (rx_phase == 0) begin
                    if (!out_data[15]) begin
                        if (!out_last) begin
                            $display("AER_V1_CIFAR_PENDING_SPARSE_LAST_FAIL word=%h",
                                out_data);
                            $fatal(1);
                        end
                        decoded_tile_count = decoded_tile_count + 1;
                    end else if (out_last) begin
                        $display("AER_V1_CIFAR_PENDING_HEADER_LAST_FAIL word=%h", out_data);
                        $fatal(1);
                    end else if (out_data[15:14] == 2'b11) begin
                        rx_data_remaining = popcount4(out_data[3:0]);
                        rx_header_columns = rx_data_remaining;
                        rx_phase = 1;
                    end else if (out_data[15:14] == 2'b10) begin
                        rx_bank_mode = out_data[5:4];
                        rx_bank_count = out_data[3:0] + 1;
                        rx_phase = 2;
                    end else begin
                        $display("AER_V1_CIFAR_PENDING_HEADER_FAIL word=%h", out_data);
                        $fatal(1);
                    end
                end else if (rx_phase == 1) begin
                    rx_consumed = 1;
                    if (out_data[15:14] == 2'b11)
                        rx_consumed = rx_data_remaining;
                    else if ((out_data[15:14] == 2'b10) && out_data[13])
                        rx_consumed = 2;
                    decoded_tile_count = decoded_tile_count + rx_consumed;
                    rx_data_remaining = rx_data_remaining - rx_consumed;
                    if (rx_data_remaining == 0) begin
                        if (!out_last) begin
                            $display("AER_V1_CIFAR_PENDING_LAST_MISSING word=%h", out_data);
                            $fatal(1);
                        end
                        rx_phase = 0;
                    end else if ((rx_data_remaining < 0) || out_last) begin
                        $display("AER_V1_CIFAR_PENDING_PACKET_LENGTH_FAIL word=%h remaining=%0d",
                            out_data, rx_data_remaining);
                        $fatal(1);
                    end
                end else if (rx_phase == 2) begin
                    rx_bank_mask = out_data;
                    rx_bank_mask_count = popcount16(out_data);
                    if ((rx_bank_mask_count != rx_bank_count) || out_last) begin
                        $display("AER_V1_CIFAR_PENDING_BANK_MASK_FAIL word=%h expected=%0d actual=%0d last=%0d",
                            out_data, rx_bank_count, rx_bank_mask_count, out_last);
                        $fatal(1);
                    end
                    if (rx_bank_mode == 3) begin
                        rx_phase = 4;
                    end else begin
                        case (rx_bank_mode)
                            0: rx_bank_words_remaining = (rx_bank_count + 1) / 2;
                            1: rx_bank_words_remaining =
                                   ((rx_bank_count * 3) + 15) / 16;
                            2: rx_bank_words_remaining = 1;
                            default: begin
                                $display("AER_V1_CIFAR_PENDING_BANK_MODE_FAIL mode=%0d",
                                    rx_bank_mode);
                                $fatal(1);
                            end
                        endcase
                        rx_phase = 3;
                    end
                end else if (rx_phase == 4) begin
                    rx_bank_bin_count = popcount16(out_data);
                    rx_bank_raw_count = rx_bank_count - rx_bank_bin_count;
                    if (((out_data & ~rx_bank_mask) != 0) || out_last) begin
                        $display("AER_V1_CIFAR_PENDING_BANK_BIN_MASK_FAIL active=%h bin=%h last=%0d",
                            rx_bank_mask, out_data, out_last);
                        $fatal(1);
                    end
                    rx_bank_words_remaining =
                        ((rx_bank_bin_count + (rx_bank_raw_count * 8)) + 15) / 16;
                    rx_phase = 3;
                end else begin
                    if (rx_bank_words_remaining <= 0) begin
                        $display("AER_V1_CIFAR_PENDING_BANK_DATA_OVERFLOW word=%h", out_data);
                        $fatal(1);
                    end
                    if (rx_bank_words_remaining == 1) begin
                        if (!out_last) begin
                            $display("AER_V1_CIFAR_PENDING_BANK_LAST_MISSING word=%h", out_data);
                            $fatal(1);
                        end
                        decoded_tile_count = decoded_tile_count + rx_bank_count;
                        rx_bank_words_remaining = 0;
                        rx_phase = 0;
                    end else begin
                        if (out_last) begin
                            $display("AER_V1_CIFAR_PENDING_BANK_LAST_EARLY word=%h remaining=%0d",
                                out_data, rx_bank_words_remaining);
                            $fatal(1);
                        end
                        rx_bank_words_remaining = rx_bank_words_remaining - 1;
                    end
                end
            end
            data_cycle = data_cycle + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        pixel_event_on = {PIXEL_COUNT{1'b0}};
        pixel_event_off = {PIXEL_COUNT{1'b0}};
        out_ready = 1'b1;
        event_count = 0;
        event_cursor = 0;
        injected_event_count = 0;
        same_cycle_duplicate_count = 0;
        accepted_tile_count = 0;
        decoded_tile_count = 0;
        output_word_count = 0;
        data_cycle = 0;
        rx_phase = 0;
        rx_data_remaining = 0;
        rx_header_columns = 0;
        rx_bank_mode = 0;
        rx_bank_count = 0;
        rx_bank_mask_count = 0;
        rx_bank_bin_count = 0;
        rx_bank_raw_count = 0;
        rx_bank_words_remaining = 0;
        rx_bank_mask = 16'b0;
        max_cycles = 1000000;

        if (!$value$plusargs("PIXEL_VECTOR=%s", vector_path))
            vector_path = "pixel_vectors.txt";
        if (!$value$plusargs("LOG=%s", log_path))
            log_path = "rtl_events.log";
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 1000000;

        vector_fd = $fopen(vector_path, "r");
        if (vector_fd == 0) begin
            $display("AER_V1_CIFAR_PENDING_VECTOR_OPEN_FAIL path=%0s", vector_path);
            $fatal(1);
        end
        while (!$feof(vector_fd)) begin
            if (event_count >= MAX_EVENTS) begin
                $display("AER_V1_CIFAR_PENDING_TOO_MANY_EVENTS max=%0d", MAX_EVENTS);
                $fatal(1);
            end
            scan_count = $fscanf(vector_fd, "%d %d %d %d %d %d\n",
                event_id_mem[event_count],
                event_cycle_mem[event_count],
                event_x_mem[event_count],
                event_y_mem[event_count],
                event_polarity_mem[event_count],
                event_elapsed_ns_mem[event_count]);
            if (scan_count == 6) begin
                if ((event_x_mem[event_count] < 0) ||
                    (event_x_mem[event_count] >= SENSOR_COLS) ||
                    (event_y_mem[event_count] < 0) ||
                    (event_y_mem[event_count] >= SENSOR_ROWS)) begin
                    $display("AER_V1_CIFAR_PENDING_COORDINATE_FAIL id=%0d x=%0d y=%0d",
                        event_id_mem[event_count], event_x_mem[event_count],
                        event_y_mem[event_count]);
                    $fatal(1);
                end
                event_count = event_count + 1;
            end else if (scan_count != -1) begin
                $display("AER_V1_CIFAR_PENDING_VECTOR_PARSE_FAIL fields=%0d event=%0d",
                    scan_count, event_count);
                $fatal(1);
            end
        end
        $fclose(vector_fd);
        if (event_count == 0) begin
            $display("AER_V1_CIFAR_PENDING_EMPTY_VECTOR");
            $fatal(1);
        end

        log_fd = $fopen(log_path, "w");
        if (log_fd == 0) begin
            $display("AER_V1_CIFAR_PENDING_LOG_OPEN_FAIL path=%0s", log_path);
            $fatal(1);
        end
        $fdisplay(log_fd, "M %0d RX_TIMESTAMP ENABLE_BINNING=%0d ENABLE_ROW_FUSION=%0d ENABLE_BANK_FUSION=%0d ENABLE_SPARSE=%0d PIXEL_FIFO_DEPTH=%0d",
            event_count, ENABLE_BINNING, ENABLE_ROW_FUSION,
            ENABLE_BANK_FUSION, ENABLE_SPARSE, PIXEL_FIFO_DEPTH);

        repeat (5) @(posedge clk);
        #1 rst_n = 1'b1;

        timeout = 0;
        stable_cycles = 0;
        while ((stable_cycles < 4) && (timeout < max_cycles)) begin
            @(posedge clk);
            timeout = timeout + 1;
            if ((event_cursor == event_count) &&
                (pixel_accepted_count == pixel_readout_count) &&
                (accepted_tile_count == decoded_tile_count) &&
                !(|tile_valid) && !out_valid && (rx_phase == 0))
                stable_cycles = stable_cycles + 1;
            else
                stable_cycles = 0;
        end

        if (stable_cycles < 4) begin
            $display("AER_V1_CIFAR_PENDING_TIMEOUT source=%0d injected=%0d accepted_pixel=%0d ignored=%0d readout=%0d accepted_tile=%0d decoded=%0d cycle=%0d",
                event_count, injected_event_count, pixel_accepted_count,
                pixel_ignored_count, pixel_readout_count, accepted_tile_count,
                decoded_tile_count, data_cycle);
            $fatal(1);
        end
        if ((pixel_accepted_count + pixel_ignored_count +
             same_cycle_duplicate_count) != event_count) begin
            $display("AER_V1_CIFAR_PENDING_ACCOUNTING_FAIL source=%0d accepted=%0d ignored=%0d duplicate=%0d",
                event_count, pixel_accepted_count, pixel_ignored_count,
                same_cycle_duplicate_count);
            $fatal(1);
        end
        if ((pixel_readout_count != pixel_accepted_count) ||
            (decoded_tile_count != accepted_tile_count) || (rx_phase != 0)) begin
            $display("AER_V1_CIFAR_PENDING_DRAIN_FAIL accepted_pixel=%0d readout=%0d accepted_tile=%0d decoded=%0d phase=%0d",
                pixel_accepted_count, pixel_readout_count, accepted_tile_count,
                decoded_tile_count, rx_phase);
            $fatal(1);
        end

        $fdisplay(log_fd, "S %0d %0d %0d %0d %0d %0d %0d %0d",
            event_count, pixel_accepted_count, pixel_ignored_count,
            same_cycle_duplicate_count, pixel_readout_count,
            accepted_tile_count, decoded_tile_count, output_word_count);
        $fclose(log_fd);
        $display("AER_V1_CIFAR_PENDING_PASS binning=%0d row_fusion=%0d bank_fusion=%0d lossy=%0d sparse=%0d depth=%0d source=%0d accepted_pixel=%0d ignored=%0d duplicate=%0d tiles=%0d words=%0d cycles=%0d",
            ENABLE_BINNING, ENABLE_ROW_FUSION, ENABLE_BANK_FUSION,
            ENABLE_LOSSY_BINNING, ENABLE_SPARSE,
            PIXEL_FIFO_DEPTH,
            event_count, pixel_accepted_count, pixel_ignored_count,
            same_cycle_duplicate_count, accepted_tile_count,
            output_word_count, data_cycle);
        $finish;
    end

endmodule

module tb_aer_v1_cifar_pending_adaptive;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_raw;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(0)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_adaptive_d2;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .PIXEL_FIFO_DEPTH(2)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_rowfusion;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .ENABLE_ROW_FUSION(1)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_rowfusion_d2;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .ENABLE_ROW_FUSION(1),
        .PIXEL_FIFO_DEPTH(2)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_bankfusion;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .ENABLE_BANK_FUSION(1)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_bankfusion_d2;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .ENABLE_BANK_FUSION(1),
        .PIXEL_FIFO_DEPTH(2)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_raw_d2;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(0),
        .PIXEL_FIFO_DEPTH(2)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_lossy;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .ENABLE_BANK_FUSION(1),
        .ENABLE_LOSSY_BINNING(1)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_lossy_d2;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .ENABLE_BANK_FUSION(1),
        .ENABLE_LOSSY_BINNING(1),
        .PIXEL_FIFO_DEPTH(2)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_combined;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .ENABLE_BANK_FUSION(1),
        .ENABLE_LOSSY_BINNING(1),
        .ENABLE_SPARSE(1)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_combined_d2;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .ENABLE_BANK_FUSION(1),
        .ENABLE_LOSSY_BINNING(1),
        .ENABLE_SPARSE(1),
        .PIXEL_FIFO_DEPTH(2)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_sharedraw;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(0),
        .USE_SHARED_ARCH(1)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_sharedraw_d2;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(0),
        .USE_SHARED_ARCH(1),
        .PIXEL_FIFO_DEPTH(2)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_sharedcare;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .USE_SHARED_ARCH(1)
    ) test_i ();
endmodule

module tb_aer_v1_cifar_pending_sharedcare_d2;
    tb_aer_v1_cifar_pending #(
        .ENABLE_BINNING(1),
        .USE_SHARED_ARCH(1),
        .PIXEL_FIFO_DEPTH(2)
    ) test_i ();
endmodule
