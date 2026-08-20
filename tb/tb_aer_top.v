`timescale 1ns/1ps

module tb_aer_top;

    reg          clk;
    reg          rst_n;
    reg  [255:0] pixel_req_async;
    reg  [255:0] pixel_polarity_async;
    wire [255:0] pixel_ack;
    wire [31:0]  event_data;
    wire         event_valid;
    reg          event_ready;
    wire [63:0]  tile_fifo_levels;

    integer errors;
    integer expected_total;
    integer observed_total;
    integer expected_count [0:255];
    reg     expected_polarity [0:255];

    integer monitor_x;
    integer monitor_y;
    integer monitor_index;
    integer i;
    integer x;
    integer y;
    integer cycles;
    integer target_total;
    reg [255:0] request_mask;
    reg [255:0] polarity_mask;
    reg [255:0] ack_seen;
    reg [31:0]  held_data;

    aer_top dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .pixel_req_async      (pixel_req_async),
        .pixel_polarity_async (pixel_polarity_async),
        .pixel_ack            (pixel_ack),
        .event_data           (event_data),
        .event_valid          (event_valid),
        .event_ready          (event_ready),
        .tile_fifo_levels     (tile_fifo_levels)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n && event_valid && event_ready) begin
            monitor_x = event_data[29:20];
            monitor_y = event_data[19:10];
            monitor_index = monitor_y * 16 + monitor_x;

            if (event_data[31:30] !== 2'b00) begin
                $display("ERROR: non-RAW packet %h", event_data);
                errors = errors + 1;
            end

            if ((monitor_x < 0) || (monitor_x >= 16) ||
                (monitor_y < 0) || (monitor_y >= 16)) begin
                $display("ERROR: coordinate out of range x=%0d y=%0d", monitor_x, monitor_y);
                errors = errors + 1;
            end else if (expected_count[monitor_index] <= 0) begin
                $display("ERROR: unexpected or duplicate event x=%0d y=%0d packet=%h",
                         monitor_x, monitor_y, event_data);
                errors = errors + 1;
            end else begin
                if (event_data[9] !== expected_polarity[monitor_index]) begin
                    $display("ERROR: polarity mismatch x=%0d y=%0d expected=%0d got=%0d",
                             monitor_x, monitor_y,
                             expected_polarity[monitor_index], event_data[9]);
                    errors = errors + 1;
                end
                expected_count[monitor_index] = expected_count[monitor_index] - 1;
            end

            observed_total = observed_total + 1;
        end
    end

    task add_expected;
        input [255:0] mask;
        input [255:0] polarities;
        integer index;
        begin
            for (index = 0; index < 256; index = index + 1) begin
                if (mask[index]) begin
                    expected_count[index] = expected_count[index] + 1;
                    expected_polarity[index] = polarities[index];
                    expected_total = expected_total + 1;
                end
            end
        end
    endtask

    task drive_and_wait_for_ack;
        input [255:0] mask;
        input [255:0] polarities;
        input integer timeout_cycles;
        begin
            add_expected(mask, polarities);
            ack_seen = 256'b0;
            cycles = 0;

            @(negedge clk);
            pixel_polarity_async = polarities;
            pixel_req_async = mask;

            while (((ack_seen & mask) != mask) && (cycles < timeout_cycles)) begin
                @(posedge clk);
                #1;
                ack_seen = ack_seen | pixel_ack;
                cycles = cycles + 1;
            end

            if ((ack_seen & mask) != mask) begin
                $display("ERROR: ACK timeout after %0d cycles", timeout_cycles);
                errors = errors + 1;
            end

            @(negedge clk);
            pixel_req_async = 256'b0;
            pixel_polarity_async = 256'b0;
            repeat (4) @(posedge clk);
        end
    endtask

    task wait_for_all_outputs;
        input integer timeout_cycles;
        integer index;
        begin
            target_total = expected_total;
            cycles = 0;
            while ((observed_total < target_total) && (cycles < timeout_cycles)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            if (observed_total != target_total) begin
                $display("ERROR: output timeout expected=%0d observed=%0d",
                         target_total, observed_total);
                errors = errors + 1;
            end

            for (index = 0; index < 256; index = index + 1) begin
                if (expected_count[index] != 0) begin
                    $display("ERROR: missing event index=%0d remaining=%0d",
                             index, expected_count[index]);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        pixel_req_async = 256'b0;
        pixel_polarity_async = 256'b0;
        event_ready = 1'b1;
        errors = 0;
        expected_total = 0;
        observed_total = 0;
        request_mask = 256'b0;
        polarity_mask = 256'b0;
        ack_seen = 256'b0;
        held_data = 32'b0;

        for (i = 0; i < 256; i = i + 1) begin
            expected_count[i] = 0;
            expected_polarity[i] = 1'b0;
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        $display("TEST 1: single event");
        request_mask = 256'b0;
        polarity_mask = 256'b0;
        request_mask[5*16 + 3] = 1'b1;
        polarity_mask[5*16 + 3] = 1'b1;
        drive_and_wait_for_ack(request_mask, polarity_mask, 100);
        wait_for_all_outputs(100);

        $display("TEST 2: one event in every tile");
        request_mask = 256'b0;
        polarity_mask = 256'b0;
        for (y = 0; y < 16; y = y + 4) begin
            for (x = 0; x < 16; x = x + 4) begin
                request_mask[y*16 + x] = 1'b1;
                polarity_mask[y*16 + x] = (x + y) & 1;
            end
        end
        drive_and_wait_for_ack(request_mask, polarity_mask, 500);
        wait_for_all_outputs(500);

        $display("TEST 3: all 256 pixels request simultaneously");
        request_mask = {256{1'b1}};
        polarity_mask = 256'b0;
        for (i = 0; i < 256; i = i + 1)
            polarity_mask[i] = i[0];
        drive_and_wait_for_ack(request_mask, polarity_mask, 5000);
        wait_for_all_outputs(5000);

        $display("TEST 4: output backpressure and FIFO retention");
        request_mask = 256'b0;
        polarity_mask = 256'b0;
        for (y = 0; y < 4; y = y + 1) begin
            for (x = 0; x < 4; x = x + 1) begin
                request_mask[y*16 + x] = 1'b1;
                polarity_mask[y*16 + x] = (x ^ y) & 1;
            end
        end

        add_expected(request_mask, polarity_mask);
        ack_seen = 256'b0;
        @(negedge clk);
        event_ready = 1'b0;
        pixel_polarity_async = polarity_mask;
        pixel_req_async = request_mask;

        repeat (40) begin
            @(posedge clk);
            #1;
            ack_seen = ack_seen | pixel_ack;
        end

        if ((ack_seen & request_mask) == request_mask) begin
            $display("ERROR: all events were ACKed even though storage should be full");
            errors = errors + 1;
        end

        if (!event_valid) begin
            $display("ERROR: no packet waiting during output backpressure");
            errors = errors + 1;
        end

        held_data = event_data;
        repeat (5) begin
            @(posedge clk);
            #1;
            if (!event_valid || (event_data !== held_data)) begin
                $display("ERROR: output changed while valid=1 and ready=0");
                errors = errors + 1;
            end
        end

        @(negedge clk);
        event_ready = 1'b1;
        cycles = 0;
        while (((ack_seen & request_mask) != request_mask) && (cycles < 2000)) begin
            @(posedge clk);
            #1;
            ack_seen = ack_seen | pixel_ack;
            cycles = cycles + 1;
        end

        if ((ack_seen & request_mask) != request_mask) begin
            $display("ERROR: ACK timeout after releasing backpressure");
            errors = errors + 1;
        end

        @(negedge clk);
        pixel_req_async = 256'b0;
        pixel_polarity_async = 256'b0;
        repeat (4) @(posedge clk);
        wait_for_all_outputs(2000);

        if (expected_total != observed_total) begin
            $display("ERROR: final count mismatch expected=%0d observed=%0d",
                     expected_total, observed_total);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("AER_RTL_PASS events=%0d", observed_total);
        else
            $display("AER_RTL_FAIL errors=%0d expected=%0d observed=%0d",
                     errors, expected_total, observed_total);

        $finish;
    end

endmodule
