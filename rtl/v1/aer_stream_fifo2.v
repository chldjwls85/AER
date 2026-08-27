`timescale 1ns/1ps

module aer_stream_fifo2 #(
    parameter integer DATA_WIDTH = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [DATA_WIDTH-1:0] in_data,
    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire                  in_last,
    output wire [DATA_WIDTH-1:0] out_data,
    output wire                  out_valid,
    input  wire                  out_ready,
    output wire                  out_last,
    output wire [1:0]            level
);

    reg [DATA_WIDTH-1:0] data_mem [0:1];
    reg                  last_mem [0:1];
    reg                  read_pointer;
    reg                  write_pointer;
    reg [1:0]            count;

    wire push;
    wire pop;

    assign out_valid = (count != 2'd0);
    assign level = count;
    assign out_data  = data_mem[read_pointer];
    assign out_last  = last_mem[read_pointer];
    assign pop       = out_valid && out_ready;

    // Do not let downstream out_ready look through a full FIFO into the
    // upstream arbiter and capture registers.  A full FIFO becomes ready on
    // the cycle after its pop.  This may insert one bubble only at the full
    // boundary, while cutting the long combinational backpressure path.
    assign in_ready = (count != 2'd2);
    assign push     = in_valid && in_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            data_mem[0]  <= {DATA_WIDTH{1'b0}};
            data_mem[1]  <= {DATA_WIDTH{1'b0}};
            last_mem[0]  <= 1'b0;
            last_mem[1]  <= 1'b0;
            read_pointer <= 1'b0;
            write_pointer <= 1'b0;
            count        <= 2'd0;
        end else begin
            if (push) begin
                data_mem[write_pointer] <= in_data;
                last_mem[write_pointer] <= in_last;
                write_pointer <= ~write_pointer;
            end

            if (pop)
                read_pointer <= ~read_pointer;

            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
