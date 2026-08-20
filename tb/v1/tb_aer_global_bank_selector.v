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

    aer_global_bank_selector #(
        .BANK_ROWS(2),
        .BANK_COLS(4),
        .ROW_INDEX_WIDTH(1),
        .COL_INDEX_WIDTH(2)
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

    task expect_transfer;
        input [15:0] expected_data;
        input        expected_last;
        input [7:0]  expected_ready;
        integer timeout;
        begin
            timeout = 0;
            while (timeout < 40) begin
                @(posedge clk);
                if (out_valid && out_ready) begin
                    if ((out_data !== expected_data) ||
                        (out_last !== expected_last) ||
                        (bank_ready !== expected_ready)) begin
                        $display("GLOBAL_SELECTOR_FAIL got=%h/%b/%b expected=%h/%b/%b",
                            out_data, out_last, bank_ready,
                            expected_data, expected_last, expected_ready);
                        $fatal(1);
                    end
                    timeout = 1000;
                end else begin
                    timeout = timeout + 1;
                end
            end
            if (timeout != 1000) begin
                $display("GLOBAL_SELECTOR_TIMEOUT expected=%h", expected_data);
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

        // Bank 1 is the first non-empty bank. Bank 4 is also waiting.
        bank_data_flat[1*16 +: 16] = 16'hA101;
        bank_data_flat[4*16 +: 16] = 16'hA404;
        bank_valid[1] = 1'b1;
        bank_valid[4] = 1'b1;
        bank_last[1]  = 1'b0;
        bank_last[4]  = 1'b1;

        expect_transfer(16'hA101, 1'b0, 8'b0000_0010);

        // The selector must remain locked to bank 1 until its last word.
        @(negedge clk);
        bank_data_flat[1*16 +: 16] = 16'hA102;
        bank_last[1] = 1'b1;
        expect_transfer(16'hA102, 1'b1, 8'b0000_0010);

        @(negedge clk);
        bank_valid[1] = 1'b0;
        // Banks 2 and 3 are empty, so row-major scan jumps to bank 4.
        expect_transfer(16'hA404, 1'b1, 8'b0001_0000);

        @(negedge clk);
        bank_valid[4] = 1'b0;
        bank_data_flat[0*16 +: 16] = 16'hA000;
        bank_valid[0] = 1'b1;
        bank_last[0]  = 1'b1;
        // After bank 4, the circular row-major pointer wraps to bank 0.
        expect_transfer(16'hA000, 1'b1, 8'b0000_0001);

        $display("AER_GLOBAL_BANK_SELECTOR_PASS");
        $finish;
    end

endmodule
