`timescale 1ns/1ps

module aer_sync_fifo #(
    parameter integer DATA_WIDTH = 32,
    parameter integer DEPTH      = 8,
    parameter integer ADDR_WIDTH = 3
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [DATA_WIDTH-1:0] in_data,
    input  wire                  in_valid,
    output wire                  in_ready,
    output wire [DATA_WIDTH-1:0] out_data,
    output wire                  out_valid,
    input  wire                  out_ready,
    output wire [ADDR_WIDTH:0]   level
);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] write_pointer;
    reg [ADDR_WIDTH-1:0] read_pointer;
    reg [ADDR_WIDTH:0]   count;

    wire push;
    wire pop;

    assign out_valid = (count != 0);
    assign out_data  = memory[read_pointer];
    assign pop       = out_valid && out_ready;
    assign in_ready  = (count < DEPTH) || pop;
    assign push      = in_valid && in_ready;
    assign level     = count;

    always @(posedge clk) begin
        if (!rst_n) begin
            write_pointer <= {ADDR_WIDTH{1'b0}};
            read_pointer  <= {ADDR_WIDTH{1'b0}};
            count         <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            if (push) begin
                memory[write_pointer] <= in_data;
                if (write_pointer == DEPTH - 1)
                    write_pointer <= {ADDR_WIDTH{1'b0}};
                else
                    write_pointer <= write_pointer + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
            end

            if (pop) begin
                if (read_pointer == DEPTH - 1)
                    read_pointer <= {ADDR_WIDTH{1'b0}};
                else
                    read_pointer <= read_pointer + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
            end

            case ({push, pop})
                2'b10: count <= count + {{ADDR_WIDTH{1'b0}}, 1'b1};
                2'b01: count <= count - {{ADDR_WIDTH{1'b0}}, 1'b1};
                default: count <= count;
            endcase
        end
    end

endmodule
