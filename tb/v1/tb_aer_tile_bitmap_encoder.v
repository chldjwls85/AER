`timescale 1ns/1ps

module tb_aer_tile_bitmap_encoder;

    reg  [3:0] on_bitmap;
    reg  [3:0] off_bitmap;
    wire       has_event;
    wire [1:0] format;
    wire [7:0] payload;
    wire [1:0] flags;
    wire       is_sparse;
    wire [2:0] sparse_payload;

    aer_tile_bitmap_encoder dut (
        .on_bitmap  (on_bitmap),
        .off_bitmap (off_bitmap),
        .has_event  (has_event),
        .format     (format),
        .payload    (payload),
        .flags      (flags),
        .is_sparse  (is_sparse),
        .sparse_payload(sparse_payload)
    );

    task check_case;
        input [3:0] test_on;
        input [3:0] test_off;
        input       expected_has_event;
        input [1:0] expected_format;
        input [7:0] expected_payload;
        input [1:0] expected_flags;
        begin
            on_bitmap  = test_on;
            off_bitmap = test_off;
            #1;
            if ((has_event !== expected_has_event) ||
                (format !== expected_format) ||
                (payload !== expected_payload) ||
                (flags !== expected_flags)) begin
                $display("TILE_ENCODER_FAIL on=%b off=%b got=%b/%b/%h/%b expected=%b/%b/%h/%b",
                    test_on, test_off, has_event, format, payload, flags,
                    expected_has_event, expected_format, expected_payload,
                    expected_flags);
                $fatal(1);
            end
        end
    endtask

    task check_sparse;
        input [3:0] test_on;
        input [3:0] test_off;
        input       expected_sparse;
        input [2:0] expected_payload;
        begin
            on_bitmap = test_on;
            off_bitmap = test_off;
            #1;
            if ((is_sparse !== expected_sparse) ||
                (sparse_payload !== expected_payload)) begin
                $display("TILE_SPARSE_FAIL on=%b off=%b got=%b/%b expected=%b/%b",
                    test_on, test_off, is_sparse, sparse_payload,
                    expected_sparse, expected_payload);
                $fatal(1);
            end
        end
    endtask

    initial begin
        check_case(4'b0000, 4'b0000, 1'b0, 2'b00, 8'h00, 2'b00);
        check_case(4'b0101, 4'b0000, 1'b1, 2'b00, 8'h50, 2'b00);
        check_case(4'b1111, 4'b0000, 1'b1, 2'b10, 8'h80, 2'b00);
        check_case(4'b0000, 4'b1111, 1'b1, 2'b10, 8'h00, 2'b00);
        check_case(4'b1110, 4'b0000, 1'b1, 2'b01, 8'h80, 2'b00);
        check_case(4'b0000, 4'b1011, 1'b1, 2'b01, 8'h40, 2'b00);
        check_case(4'b0001, 4'b0001, 1'b1, 2'b00, 8'h11, 2'b10);
        check_sparse(4'b0001, 4'b0000, 1'b1, 3'b001);
        check_sparse(4'b0100, 4'b0000, 1'b1, 3'b101);
        check_sparse(4'b0000, 4'b1000, 1'b1, 3'b110);
        check_sparse(4'b0011, 4'b0000, 1'b0, 3'b000);
        check_sparse(4'b0001, 4'b0001, 1'b0, 3'b000);
        $display("AER_TILE_BITMAP_ENCODER_PASS");
        $finish;
    end

endmodule
