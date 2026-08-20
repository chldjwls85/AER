`timescale 1ns/1ps

module aer_timebase #(
    parameter integer TIME_WIDTH = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,
    output reg  [TIME_WIDTH-1:0] time_now
);
    always @(posedge clk) begin
        if (!rst_n)
            time_now <= {TIME_WIDTH{1'b0}};
        else
            time_now <= time_now + {{(TIME_WIDTH-1){1'b0}}, 1'b1};
    end
endmodule
