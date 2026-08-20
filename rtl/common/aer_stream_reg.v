`timescale 1ns/1ps

module aer_stream_reg #(
    parameter integer DATA_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [DATA_WIDTH-1:0] in_data,
    input  wire                  in_valid,
    output wire                  in_ready,
    output wire [DATA_WIDTH-1:0] out_data,
    output wire                  out_valid,
    input  wire                  out_ready
);

    reg [DATA_WIDTH-1:0] data_reg;
    reg                  valid_reg;

    assign in_ready  = !valid_reg || out_ready;
    assign out_data  = data_reg;
    assign out_valid = valid_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            data_reg  <= {DATA_WIDTH{1'b0}};
            valid_reg <= 1'b0;
        end else if (in_ready) begin
            valid_reg <= in_valid;
            if (in_valid)
                data_reg <= in_data;
        end
    end

endmodule
