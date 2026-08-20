`timescale 1ns/1ps

module aer_event_capture #(
    parameter integer TIME_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  req_async,
    input  wire                  polarity_async,
    input  wire [TIME_WIDTH-1:0] time_now,
    input  wire                  consume,
    output reg                   pending,
    output reg                   stored_polarity,
    output reg  [TIME_WIDTH-1:0] stored_time,
    output reg                   ack
);

    reg req_meta;
    reg req_sync;
    reg polarity_meta;
    reg polarity_sync;
    reg armed;

    always @(posedge clk) begin
        if (!rst_n) begin
            req_meta        <= 1'b0;
            req_sync        <= 1'b0;
            polarity_meta   <= 1'b0;
            polarity_sync   <= 1'b0;
            armed           <= 1'b1;
            pending         <= 1'b0;
            stored_polarity <= 1'b0;
            stored_time     <= {TIME_WIDTH{1'b0}};
            ack             <= 1'b0;
        end else begin
            req_meta      <= req_async;
            req_sync      <= req_meta;
            polarity_meta <= polarity_async;
            polarity_sync <= polarity_meta;
            ack           <= 1'b0;

            // A new request is accepted only after the previous request went low.
            if (!req_sync)
                armed <= 1'b1;

            if (armed && req_sync && !pending) begin
                pending         <= 1'b1;
                stored_polarity <= polarity_sync;
                stored_time     <= time_now;
                armed           <= 1'b0;
            end

            // consume means that the event was stored in the tile FIFO.
            if (consume && pending) begin
                pending <= 1'b0;
                ack     <= 1'b1;
            end
        end
    end

endmodule
