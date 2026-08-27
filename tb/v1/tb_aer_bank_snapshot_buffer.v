`timescale 1ns/1ps

module tb_aer_bank_snapshot_buffer;
    reg clk;
    reg rst_n;
    reg [15:0] tile_in_valid;
    reg [63:0] tile_on_flat;
    reg [63:0] tile_off_flat;
    wire [15:0] tile_in_ready;
    wire snapshot_valid;
    reg snapshot_ready;
    wire [15:0] snapshot_mask;
    wire [127:0] snapshot_raw_flat;
    wire [15:0] pending_debug;

    aer_bank_snapshot_buffer dut (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat), .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .snapshot_valid(snapshot_valid),
        .snapshot_ready(snapshot_ready),
        .snapshot_mask(snapshot_mask),
        .snapshot_raw_flat(snapshot_raw_flat),
        .pending_debug(pending_debug)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;
        tile_off_flat = 64'b0;
        snapshot_ready = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Store A in tile 0.
        tile_in_valid[0] = 1'b1;
        tile_on_flat[3:0] = 4'b0001;
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 16'b0;
        tile_on_flat = 64'b0;
        if (!snapshot_valid || snapshot_mask != 16'h0001 ||
            snapshot_raw_flat[7:0] != 8'h10 || tile_in_ready[0]) begin
            $display("AER_BANK_SNAPSHOT_HOLD_FAIL valid=%b mask=%h raw=%h ready=%b",
                snapshot_valid, snapshot_mask, snapshot_raw_flat[7:0],
                tile_in_ready[0]);
            $fatal(1);
        end

        // Consume A while replacing the same tile with B on the same edge.
        snapshot_ready = 1'b1;
        tile_in_valid[0] = 1'b1;
        tile_off_flat[3:0] = 4'b0100;
        #1;
        if (!tile_in_ready[0] || snapshot_raw_flat[7:0] != 8'h10) begin
            $display("AER_BANK_SNAPSHOT_REPLACE_READY_FAIL");
            $fatal(1);
        end
        @(posedge clk);
        @(negedge clk);
        snapshot_ready = 1'b0;
        tile_in_valid = 16'b0;
        tile_off_flat = 64'b0;
        if (!snapshot_valid || snapshot_mask != 16'h0001 ||
            snapshot_raw_flat[7:0] != 8'h04) begin
            $display("AER_BANK_SNAPSHOT_REPLACE_FAIL valid=%b mask=%h raw=%h",
                snapshot_valid, snapshot_mask, snapshot_raw_flat[7:0]);
            $fatal(1);
        end

        // Drain B.
        snapshot_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        snapshot_ready = 1'b0;
        if (snapshot_valid || pending_debug != 16'b0) begin
            $display("AER_BANK_SNAPSHOT_DRAIN_FAIL pending=%h", pending_debug);
            $fatal(1);
        end

        $display("AER_BANK_SNAPSHOT_BUFFER_PASS same_cycle_replace=1");
        $finish;
    end
endmodule
