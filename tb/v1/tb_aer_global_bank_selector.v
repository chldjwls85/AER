`timescale 1ns/1ps

module tb_aer_global_bank_selector;

    reg          clk;
    reg          rst_n;
    reg  [127:0] bank_data_flat;
    reg  [7:0]   bank_valid;
    reg  [7:0]   bank_last;
    wire [7:0]   bank_ready;
    wire [15:0]  out_data;
    wire         out_valid;
    reg          out_ready;
    wire         out_last;

    reg [15:0] captured_data [0:7];
    reg        captured_last [0:7];
    integer    captured_cycle [0:7];
    integer    transfer_count;
    integer    cycle_count;
    integer    timeout;
    reg [15:0] held_data;
    reg        held_last;

    aer_global_bank_selector #(
        .BANK_ROWS(2),
        .BANK_COLS(4),
        .ROW_INDEX_WIDTH(1),
        .COL_INDEX_WIDTH(2),
        .REGION_ROWS(2),
        .REGION_COLS(2)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .bank_data_flat (bank_data_flat),
        .bank_valid     (bank_valid),
        .bank_last      (bank_last),
        .bank_ready     (bank_ready),
        .out_data       (out_data),
        .out_valid      (out_valid),
        .out_ready      (out_ready),
        .out_last       (out_last)
    );

    always #5 clk = ~clk;

    // Handshake-aware bank stream models.  A FIFO is allowed to consume a bank
    // word before that word reaches the root output.
    always @(posedge clk) begin
        if (rst_n) begin
            if (bank_valid[1] && bank_ready[1]) begin
                if (!bank_last[1]) begin
                    bank_data_flat[1*16 +: 16] <= 16'hA102;
                    bank_last[1] <= 1'b1;
                end else begin
                    bank_valid[1] <= 1'b0;
                end
            end
            if (bank_valid[6] && bank_ready[6])
                bank_valid[6] <= 1'b0;
            if (bank_valid[0] && bank_ready[0])
                bank_valid[0] <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            transfer_count = 0;
            cycle_count = 0;
        end else begin
            cycle_count = cycle_count + 1;
            if (out_valid && out_ready) begin
                captured_data[transfer_count] = out_data;
                captured_last[transfer_count] = out_last;
                captured_cycle[transfer_count] = cycle_count;
                transfer_count = transfer_count + 1;
            end
        end
    end

    task wait_for_transfers;
        input integer expected_count;
        begin
            timeout = 0;
            while ((transfer_count < expected_count) && (timeout < 100)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (transfer_count != expected_count) begin
                $display("GLOBAL_SELECTOR_TIMEOUT got=%0d expected=%0d",
                    transfer_count, expected_count);
                $fatal(1);
            end
        end
    endtask

    task check_transfer;
        input integer transfer_index;
        input [15:0] expected_data;
        input expected_last;
        begin
            if ((captured_data[transfer_index] !== expected_data) ||
                (captured_last[transfer_index] !== expected_last)) begin
                $display("GLOBAL_SELECTOR_FAIL index=%0d got=%h/%b expected=%h/%b",
                    transfer_index,
                    captured_data[transfer_index],
                    captured_last[transfer_index],
                    expected_data,
                    expected_last);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk            = 1'b0;
        rst_n          = 1'b0;
        bank_data_flat = 128'b0;
        bank_valid     = 8'b0;
        bank_last      = 8'b0;
        out_ready      = 1'b1;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Bank 1 has a two-word packet.  Bank 6 is in another spatial region
        // and waits with a one-word packet.
        bank_data_flat[1*16 +: 16] = 16'hA101;
        bank_data_flat[6*16 +: 16] = 16'hA606;
        bank_valid[1] = 1'b1;
        bank_valid[6] = 1'b1;
        bank_last[1] = 1'b0;
        bank_last[6] = 1'b1;

        wait_for_transfers(3);
        check_transfer(0, 16'hA101, 1'b0);
        check_transfer(1, 16'hA102, 1'b1);
        check_transfer(2, 16'hA606, 1'b1);

        // Words inside one packet remain consecutive.  A different packet is
        // selected through the registered grant boundary, so one idle cycle
        // is intentional between packet 1 and packet 2.
        if ((captured_cycle[1] != captured_cycle[0] + 1) ||
            (captured_cycle[2] != captured_cycle[1] + 2)) begin
            $display("GLOBAL_SELECTOR_REGISTERED_BOUNDARY_FAIL cycles=%0d,%0d,%0d",
                captured_cycle[0], captured_cycle[1], captured_cycle[2]);
            $fatal(1);
        end

        // The two-entry root FIFO must hold a stalled output stable while the
        // bank-side handshake is allowed to complete independently.
        @(negedge clk);
        out_ready = 1'b0;
        bank_data_flat[0*16 +: 16] = 16'hA000;
        bank_valid[0] = 1'b1;
        bank_last[0] = 1'b1;

        timeout = 0;
        while (!out_valid && (timeout < 30)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!out_valid) begin
            $display("GLOBAL_SELECTOR_BUFFER_TIMEOUT");
            $fatal(1);
        end

        held_data = out_data;
        held_last = out_last;
        repeat (3) begin
            @(posedge clk);
            if (!out_valid || (out_data !== held_data) || (out_last !== held_last)) begin
                $display("GLOBAL_SELECTOR_STABILITY_FAIL got=%h/%b held=%h/%b",
                    out_data, out_last, held_data, held_last);
                $fatal(1);
            end
        end

        @(negedge clk);
        out_ready = 1'b1;
        wait_for_transfers(4);
        check_transfer(3, 16'hA000, 1'b1);

        $display("AER_GLOBAL_BANK_SELECTOR_PASS levels=2 registered_boundary=1 fifo2=1");
        $finish;
    end

endmodule
