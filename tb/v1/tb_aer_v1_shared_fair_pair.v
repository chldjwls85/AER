`timescale 1ns/1ps

module tb_aer_v1_shared_fair_pair;
    reg clk;
    reg rst_n;
    reg [4095:0] tile_in_valid;
    reg [16383:0] tile_on_flat;
    reg [16383:0] tile_off_flat;
    wire [4095:0] raw_ready;
    wire [4095:0] care_ready;
    wire [15:0] raw_data;
    wire raw_valid;
    wire raw_last;
    wire [15:0] care_data;
    wire care_valid;
    wire care_last;
    reg out_ready;

    integer raw_words;
    integer care_words;
    integer timeout;
    localparam integer BANK = 17;

    aer_v1_shared_top_128 #(.ENABLE_COMPRESSION(0)) raw_dut (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat), .tile_off_flat(tile_off_flat),
        .tile_in_ready(raw_ready),
        .out_data(raw_data), .out_valid(raw_valid),
        .out_ready(out_ready), .out_last(raw_last)
    );

    aer_v1_shared_top_128 #(.ENABLE_COMPRESSION(1)) care_dut (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat), .tile_off_flat(tile_off_flat),
        .tile_in_ready(care_ready),
        .out_data(care_data), .out_valid(care_valid),
        .out_ready(out_ready), .out_last(care_last)
    );

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (raw_valid && out_ready) raw_words <= raw_words + 1;
        if (care_valid && out_ready) care_words <= care_words + 1;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tile_in_valid = 4096'b0;
        tile_on_flat = 16384'b0;
        tile_off_flat = 16384'b0;
        out_ready = 1'b1;
        raw_words = 0;
        care_words = 0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Eight dense tiles in one bank.  Both designs receive the same
        // snapshot on the same cycle and differ only in packet selection.
        tile_in_valid[BANK*16 +: 16] = 16'h00FF;
        tile_on_flat[BANK*64 +: 64] = 64'h20EF_00E1;
        tile_off_flat[BANK*64 +: 64] = 64'h4F00_EF00;
        if ((raw_ready[BANK*16 +: 16] !== 16'hFFFF) ||
            (care_ready[BANK*16 +: 16] !== 16'hFFFF)) begin
            $display("AER_SHARED_FAIR_READY_FAIL raw=%h care=%h",
                raw_ready[BANK*16 +: 16], care_ready[BANK*16 +: 16]);
            $fatal(1);
        end
        @(posedge clk);
        @(negedge clk);
        tile_in_valid = 4096'b0;
        tile_on_flat = 16384'b0;
        tile_off_flat = 16384'b0;

        timeout = 0;
        while (((raw_words < 6) || (care_words < 6)) && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        // With only one isolated snapshot the congestion gate keeps lossy
        // GROUP3 disabled, so both paths intentionally remain lossless RAW.
        if ((raw_words != 6) || (care_words != 6)) begin
            $display("AER_SHARED_FAIR_COUNT_FAIL raw=%0d care=%0d",
                raw_words, care_words);
            $fatal(1);
        end
        $display("AER_V1_SHARED_FAIR_PAIR_PASS raw_words=%0d care_words=%0d",
            raw_words, care_words);
        $finish;
    end
endmodule
