`timescale 1ns/1ps

// One lossless capture slot per 2x2 tile in a 4x4-tile bank.
//
// The buffer is deliberately format-agnostic.  RAW and CARE use this exact
// storage and handshake; compression begins only after a complete bank
// snapshot has been accepted by the shared regional engine.
module aer_bank_snapshot_buffer (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [15:0]   tile_in_valid,
    input  wire [63:0]   tile_on_flat,
    input  wire [63:0]   tile_off_flat,
    output wire [15:0]   tile_in_ready,
    output wire          snapshot_valid,
    input  wire          snapshot_ready,
    output wire [15:0]   snapshot_mask,
    output wire [127:0]  snapshot_raw_flat,
    output wire [15:0]   pending_debug
);

    reg [15:0]  pending;
    reg [127:0] stored_raw_flat;
    reg [15:0]  accept_mask;

    wire snapshot_take;
    integer tile_index;

    assign snapshot_valid = |pending;
    assign snapshot_take = snapshot_valid && snapshot_ready;
    assign snapshot_mask = pending;
    assign snapshot_raw_flat = stored_raw_flat;
    assign pending_debug = pending;

    // Keep downstream snapshot_ready out of the capture-register write path.
    // A consumed tile becomes ready on the following cycle instead of being
    // replaced on the same edge.  This removes the selected-bank ready decode
    // from accept_mask and stored_raw_flat control with no extra storage bits.
    assign tile_in_ready = ~pending;

    always @* begin
        accept_mask = 16'b0;
        for (tile_index = 0; tile_index < 16;
             tile_index = tile_index + 1) begin
            accept_mask[tile_index] = tile_in_valid[tile_index] &&
                tile_in_ready[tile_index] &&
                (|tile_on_flat[tile_index*4 +: 4] ||
                 |tile_off_flat[tile_index*4 +: 4]);
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pending <= 16'b0;
            stored_raw_flat <= 128'b0;
        end else begin
            pending <= (pending & ~{16{snapshot_take}}) | accept_mask;
            for (tile_index = 0; tile_index < 16;
                 tile_index = tile_index + 1) begin
                if (accept_mask[tile_index]) begin
                    stored_raw_flat[tile_index*8 +: 8] <= {
                        tile_on_flat[tile_index*4 +: 4],
                        tile_off_flat[tile_index*4 +: 4]
                    };
                end
            end
        end
    end

endmodule
