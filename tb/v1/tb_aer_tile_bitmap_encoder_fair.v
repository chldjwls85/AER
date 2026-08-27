`timescale 1ns/1ps

module tb_aer_tile_bitmap_encoder_fair;

    reg  [3:0] on_bitmap;
    reg  [3:0] off_bitmap;

    wire       adaptive_has_event;
    wire [1:0] adaptive_format;
    wire [7:0] adaptive_payload;
    wire [1:0] adaptive_flags;
    wire       adaptive_is_sparse;
    wire [2:0] adaptive_sparse_payload;

    wire       raw_has_event;
    wire [1:0] raw_format;
    wire [7:0] raw_payload;
    wire [1:0] raw_flags;
    wire       raw_is_sparse;
    wire [2:0] raw_sparse_payload;

    aer_tile_bitmap_encoder #(
        .ENABLE_BINNING(1)
    ) adaptive_encoder_i (
        .on_bitmap  (on_bitmap),
        .off_bitmap (off_bitmap),
        .has_event  (adaptive_has_event),
        .format     (adaptive_format),
        .payload    (adaptive_payload),
        .flags      (adaptive_flags),
        .is_sparse  (adaptive_is_sparse),
        .sparse_payload(adaptive_sparse_payload)
    );

    aer_tile_bitmap_encoder #(
        .ENABLE_BINNING(0)
    ) raw_encoder_i (
        .on_bitmap  (on_bitmap),
        .off_bitmap (off_bitmap),
        .has_event  (raw_has_event),
        .format     (raw_format),
        .payload    (raw_payload),
        .flags      (raw_flags),
        .is_sparse  (raw_is_sparse),
        .sparse_payload(raw_sparse_payload)
    );

    task check_case;
        input [3:0] test_on;
        input [3:0] test_off;
        input       expected_has_event;
        input [1:0] expected_adaptive_format;
        input [7:0] expected_adaptive_payload;
        input [1:0] expected_flags;
        begin
            on_bitmap  = test_on;
            off_bitmap = test_off;
            #1;

            if ((adaptive_has_event !== expected_has_event) ||
                (raw_has_event !== expected_has_event) ||
                (adaptive_format !== expected_adaptive_format) ||
                (adaptive_payload !== expected_adaptive_payload) ||
                (adaptive_flags !== expected_flags) ||
                (raw_format !== 2'b00) ||
                (raw_payload !== {test_on, test_off}) ||
                (raw_flags !== expected_flags)) begin
                $display("FAIR_ENCODER_FAIL on=%b off=%b", test_on, test_off);
                $display(" adaptive=%b/%h/%b raw=%b/%h/%b",
                    adaptive_format, adaptive_payload, adaptive_flags,
                    raw_format, raw_payload, raw_flags);
                $fatal(1);
            end
        end
    endtask

    initial begin
        check_case(4'b0000, 4'b0000, 1'b0, 2'b00, 8'h00, 2'b00);
        check_case(4'b1111, 4'b0000, 1'b1, 2'b10, 8'h80, 2'b00);
        check_case(4'b0000, 4'b1111, 1'b1, 2'b10, 8'h00, 2'b00);
        check_case(4'b1110, 4'b0000, 1'b1, 2'b01, 8'h80, 2'b00);
        check_case(4'b0000, 4'b1011, 1'b1, 2'b01, 8'h40, 2'b00);
        check_case(4'b0011, 4'b1100, 1'b1, 2'b00, 8'h3C, 2'b00);
        check_case(4'b0001, 4'b0001, 1'b1, 2'b00, 8'h11, 2'b10);
        $display("AER_TILE_ENCODER_FAIR_PAIR_PASS");
        $finish;
    end

endmodule
