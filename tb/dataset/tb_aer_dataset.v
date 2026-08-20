`timescale 1ns/1ps

// Common 128x128 file-driven dataset harness. The same three memory vectors
// are compiled against current, fair RAW, and team second-design RTL.
module tb_aer_dataset;
    localparam integer STIM_CYCLES = 1024;
    localparam integer DRAIN_LIMIT = 1000000;

    reg clk;
    reg rst_n;
    reg [4095:0] tile_in_valid;
    reg [16383:0] tile_on_flat;
    reg [16383:0] tile_off_flat;
    wire [4095:0] tile_in_ready;
    wire [15:0] out_data;
    wire out_valid;
    reg out_ready;
    wire out_last;
    wire [15:0] dut_time_now;

    reg [4095:0] valid_mem [0:STIM_CYCLES-1];
    reg [16383:0] on_mem [0:STIM_CYCLES-1];
    reg [16383:0] off_mem [0:STIM_CYCLES-1];
    integer stimulus_cycle;
    integer active_stimulus_cycle;
    integer tile_index;
    integer accepted_file;
    integer output_file;
    integer accepted_transactions;
    integer output_words;
    integer drain_cycles;
    integer quiet_cycles;
    integer tb_cycle;
    reg stimulus_active;

`ifdef CURRENT_DESIGN
    aer_top #(
        .SENSOR_ROWS(128), .SENSOR_COLS(128), .MAX_BANK_DELTA(31)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat), .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .out_data(out_data), .out_valid(out_valid),
        .out_ready(out_ready), .out_last(out_last)
    );
`else
`ifdef TEAM_BINNING
    aer_v1_top #(
        .SENSOR_ROWS(128), .SENSOR_COLS(128),
        .REGION_BANK_ROWS(4), .REGION_BANK_COLS(4),
        .ENABLE_BINNING(1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat), .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .out_data(out_data), .out_valid(out_valid),
        .out_ready(out_ready), .out_last(out_last)
    );
`else
    aer_v1_top #(
        .SENSOR_ROWS(128), .SENSOR_COLS(128),
        .REGION_BANK_ROWS(4), .REGION_BANK_COLS(4),
        .ENABLE_BINNING(0)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_in_valid(tile_in_valid),
        .tile_on_flat(tile_on_flat), .tile_off_flat(tile_off_flat),
        .tile_in_ready(tile_in_ready),
        .out_data(out_data), .out_valid(out_valid),
        .out_ready(out_ready), .out_last(out_last)
    );
`endif
`endif

    assign dut_time_now = dut.time_now;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            tb_cycle = 0;
        end else begin
            tb_cycle = tb_cycle + 1;
            if (stimulus_active) begin
                for (tile_index = 0; tile_index < 4096; tile_index = tile_index + 1) begin
                    if (tile_in_valid[tile_index] && tile_in_ready[tile_index] &&
                        (|tile_on_flat[tile_index*4 +: 4] ||
                         |tile_off_flat[tile_index*4 +: 4])) begin
                        $fdisplay(accepted_file, "A %0d %0d %01h %01h %04h",
                                  active_stimulus_cycle, tile_index,
                                  tile_on_flat[tile_index*4 +: 4],
                                  tile_off_flat[tile_index*4 +: 4],
                                  dut_time_now);
                        accepted_transactions = accepted_transactions + 1;
                    end
                end
            end
            if (out_valid && out_ready) begin
                $fdisplay(output_file, "W %0d %04h %0d", tb_cycle, out_data, out_last);
                output_words = output_words + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tile_in_valid = 4096'b0;
        tile_on_flat = 16384'b0;
        tile_off_flat = 16384'b0;
        out_ready = 1'b1;
        stimulus_active = 1'b0;
        active_stimulus_cycle = -1;
        accepted_transactions = 0;
        output_words = 0;
        quiet_cycles = 0;
        tb_cycle = 0;
        $readmemh("valid.hex", valid_mem);
        $readmemh("on.hex", on_mem);
        $readmemh("off.hex", off_mem);
        accepted_file = $fopen("accepted.log", "w");
        output_file = $fopen("output.log", "w");
        if (accepted_file == 0 || output_file == 0) begin
            $display("AER_DATASET_XSIM_FAIL cannot open output files");
            $finish;
        end

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        stimulus_active = 1'b1;
        for (stimulus_cycle = 0; stimulus_cycle < STIM_CYCLES;
             stimulus_cycle = stimulus_cycle + 1) begin
            @(negedge clk);
            active_stimulus_cycle = stimulus_cycle;
            tile_in_valid = valid_mem[stimulus_cycle];
            tile_on_flat = on_mem[stimulus_cycle];
            tile_off_flat = off_mem[stimulus_cycle];
        end
        @(negedge clk);
        stimulus_active = 1'b0;
        tile_in_valid = 4096'b0;
        tile_on_flat = 16384'b0;
        tile_off_flat = 16384'b0;

        quiet_cycles = 0;
        drain_cycles = 0;
        while ((quiet_cycles < 128) && (drain_cycles < DRAIN_LIMIT)) begin
            @(posedge clk);
            #1;
            if ((&tile_in_ready) && !out_valid)
                quiet_cycles = quiet_cycles + 1;
            else
                quiet_cycles = 0;
            drain_cycles = drain_cycles + 1;
        end
        $fclose(accepted_file);
        $fclose(output_file);
        if (drain_cycles >= DRAIN_LIMIT) begin
            $display("AER_DATASET_XSIM_FAIL drain timeout accepted=%0d words=%0d",
                     accepted_transactions, output_words);
        end else begin
            $display("AER_DATASET_XSIM_PASS accepted_transactions=%0d words=%0d",
                     accepted_transactions, output_words);
        end
        #20;
        $finish;
    end
endmodule
