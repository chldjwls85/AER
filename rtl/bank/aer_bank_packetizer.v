`timescale 1ns/1ps

// 8x8-pixel bank packetizer.
// Input granularity is sixteen 2x2-pixel tiles arranged as 4 rows x 4 columns.
//
// Three lossless packet formats are selected automatically:
//   SPARSE packet: one polarity bit in one tile, full timestamp in two words.
//   ROW packet  : used when pending events occupy one tile-row.
//   BANK packet : used when >=2 rows are active and all timestamps are within
//                 MAX_BANK_DELTA clocks. Bank ID/timestamp are then shared.
//
// Tile identity inside a BANK packet is implicit from the 16-bit tile mask and
// ascending tile-ID data order. No binning or position loss is performed.
module aer_bank_packetizer #(
    parameter [7:0] BANK_ID = 8'd0,
    parameter integer MAX_BANK_DELTA = 31
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [15:0]   tile_in_valid,
    input  wire [63:0]   tile_on_flat,
    input  wire [63:0]   tile_off_flat,
    output reg  [15:0]   tile_in_ready,
    input  wire [15:0]   time_now,
    output reg  [15:0]   out_data,
    output reg           out_valid,
    input  wire          out_ready,
    output reg           out_last,
    output wire [15:0]   pending_debug,
    output wire          bank_mode_debug
);
    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_ANALYZE     = 4'd1;
    localparam [3:0] ST_ROW_HEADER  = 4'd2;
    localparam [3:0] ST_ROW_TIME    = 4'd3;
    localparam [3:0] ST_ROW_DATA    = 4'd4;
    localparam [3:0] ST_BANK_HEADER = 4'd5;
    localparam [3:0] ST_BANK_MASK   = 4'd6;
    localparam [3:0] ST_BANK_TIME   = 4'd7;
    localparam [3:0] ST_BANK_DATA   = 4'd8;
    localparam [3:0] ST_SPARSE_ADDR = 4'd9;
    localparam [3:0] ST_SPARSE_TIME = 4'd10;

    reg [3:0] state;
    reg [15:0] pending;
    reg [3:0] stored_on [0:15];
    reg [3:0] stored_off [0:15];
    reg [15:0] stored_time [0:15];

    reg [15:0] snapshot_mask;
    reg [15:0] remaining_mask;
    reg [15:0] packet_base_time;
    reg [1:0]  selected_row;
    reg [4:0]  packet_tile_count;
    reg        packet_bank_mode;
    reg [1:0]  sparse_pixel;
    reg        sparse_polarity;

    reg [15:0] accept_mask;
    reg [15:0] clear_mask;
    reg [15:0] pending_after;

    integer ready_index;
    integer capture_index;
    integer scan_index;
    integer row_index;

    // Combinational analysis of currently pending tiles.
    reg [4:0] analysis_tile_count;
    reg [2:0] analysis_row_count;
    reg [15:0] analysis_min_time;
    reg [15:0] analysis_max_time;
    reg analysis_first_time;
    reg [1:0] analysis_selected_row;
    reg analysis_row_found;
    reg [15:0] analysis_row_min_time;
    reg analysis_row_first_time;
    reg [15:0] analysis_row_mask;
    reg analysis_use_bank;
    reg analysis_use_sparse;
    reg [3:0] analysis_sparse_tile;
    reg [7:0] analysis_nonbank_cost;
    reg [7:0] analysis_bank_cost;
    integer analysis_row_tiles;
    integer analysis_row_sparse;
    integer analysis_row_nonsparse;
    integer analysis_row_cost;
    integer analysis_hybrid_cost;
    integer analysis_event_bits;

    // Current DATA-word selection.
    reg [3:0] selected_tile;
    reg selected_tile_valid;
    reg [15:0] remaining_without_selected;
    reg [3:0] snapshot_columns;
    reg [15:0] selected_delta_full;

    function [3:0] count_ones8;
        input [7:0] bits;
        integer bit_index;
        begin
            count_ones8 = 4'd0;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                count_ones8 = count_ones8 + bits[bit_index];
        end
    endfunction

    assign pending_debug = pending;
    assign bank_mode_debug = packet_bank_mode;

    // One pending storage slot per tile. The raw ON/OFF bitmap is preserved.
    always @* begin
        tile_in_ready = 16'b0;
        accept_mask = 16'b0;
        for (ready_index = 0; ready_index < 16; ready_index = ready_index + 1) begin
            tile_in_ready[ready_index] = !pending[ready_index];
            accept_mask[ready_index] = tile_in_valid[ready_index] &&
                                       tile_in_ready[ready_index] &&
                                       (|tile_on_flat[ready_index*4 +: 4] ||
                                        |tile_off_flat[ready_index*4 +: 4]);
        end
    end

    // Find active rows, global timestamp span, and the oldest pending row.
    always @* begin
        analysis_tile_count = 5'd0;
        analysis_row_count = 3'd0;
        analysis_min_time = 16'hffff;
        analysis_max_time = 16'h0000;
        analysis_first_time = 1'b1;
        analysis_selected_row = 2'd0;
        analysis_row_found = 1'b0;
        analysis_row_min_time = 16'hffff;
        analysis_row_first_time = 1'b1;
        analysis_row_mask = 16'b0;
        analysis_use_sparse = 1'b0;
        analysis_sparse_tile = 4'd0;
        analysis_nonbank_cost = 8'd0;
        analysis_bank_cost = 8'd0;

        for (scan_index = 0; scan_index < 16; scan_index = scan_index + 1) begin
            if (pending[scan_index]) begin
                analysis_tile_count = analysis_tile_count + 1'b1;
                if (analysis_first_time) begin
                    analysis_min_time = stored_time[scan_index];
                    analysis_max_time = stored_time[scan_index];
                    analysis_first_time = 1'b0;
                end else begin
                    if (stored_time[scan_index] < analysis_min_time)
                        analysis_min_time = stored_time[scan_index];
                    if (stored_time[scan_index] > analysis_max_time)
                        analysis_max_time = stored_time[scan_index];
                end
            end
        end

        for (row_index = 0; row_index < 4; row_index = row_index + 1) begin
            if (|pending[row_index*4 +: 4]) begin
                analysis_row_count = analysis_row_count + 1'b1;
                if (!analysis_row_found) begin
                    analysis_selected_row = row_index[1:0];
                    analysis_row_found = 1'b1;
                end

                // Exact alternative cost for this row when BANK is legal:
                // either one ROW packet, or two-word SPARSE packets plus one
                // ROW packet for the remaining non-sparse transactions.
                analysis_row_tiles = 0;
                analysis_row_sparse = 0;
                analysis_row_nonsparse = 0;
                for (scan_index = 0; scan_index < 16; scan_index = scan_index + 1) begin
                    if (pending[scan_index] && ((scan_index / 4) == row_index)) begin
                        analysis_event_bits = count_ones8({stored_on[scan_index],
                                                          stored_off[scan_index]});
                        analysis_row_tiles = analysis_row_tiles + 1;
                        if (analysis_event_bits == 1)
                            analysis_row_sparse = analysis_row_sparse + 1;
                        else
                            analysis_row_nonsparse = analysis_row_nonsparse + 1;
                    end
                end
                analysis_row_cost = analysis_row_tiles + 2;
                analysis_hybrid_cost = analysis_row_sparse * 2;
                if (analysis_row_nonsparse != 0)
                    analysis_hybrid_cost = analysis_hybrid_cost +
                                           analysis_row_nonsparse + 2;
                if (analysis_hybrid_cost <= analysis_row_cost)
                    analysis_nonbank_cost = analysis_nonbank_cost + analysis_hybrid_cost;
                else
                    analysis_nonbank_cost = analysis_nonbank_cost + analysis_row_cost;
            end
        end

        // Base time for ROW mode is the oldest event in the first active row.
        for (scan_index = 0; scan_index < 16; scan_index = scan_index + 1) begin
            if (pending[scan_index] && ((scan_index / 4) == analysis_selected_row)) begin
                if (analysis_row_first_time) begin
                    analysis_row_min_time = stored_time[scan_index];
                    analysis_row_first_time = 1'b0;
                end else if (stored_time[scan_index] < analysis_row_min_time) begin
                    analysis_row_min_time = stored_time[scan_index];
                end
            end
        end

        // A ROW packet carries tiles whose 5-bit delta fits this packet.
        for (scan_index = 0; scan_index < 16; scan_index = scan_index + 1) begin
            if (pending[scan_index] && ((scan_index / 4) == analysis_selected_row) &&
                ((stored_time[scan_index] - analysis_row_min_time) <= MAX_BANK_DELTA)) begin
                analysis_row_mask[scan_index] = 1'b1;
            end
        end


        // For the first active row, choose a two-word SPARSE packet only when
        // it is part of the minimum-cost non-BANK encoding.  A tie prefers the
        // shorter packet lock.
        analysis_row_tiles = 0;
        analysis_row_sparse = 0;
        analysis_row_nonsparse = 0;
        for (scan_index = 0; scan_index < 16; scan_index = scan_index + 1) begin
            if (analysis_row_mask[scan_index]) begin
                analysis_event_bits = count_ones8({stored_on[scan_index],
                                                    stored_off[scan_index]});
                analysis_row_tiles = analysis_row_tiles + 1;
                if (analysis_event_bits == 1) begin
                    analysis_row_sparse = analysis_row_sparse + 1;
                    if (!analysis_use_sparse) begin
                        analysis_sparse_tile = scan_index[3:0];
                        analysis_use_sparse = 1'b1;
                    end
                end else begin
                    analysis_row_nonsparse = analysis_row_nonsparse + 1;
                end
            end
        end
        analysis_row_cost = analysis_row_tiles + 2;
        analysis_hybrid_cost = analysis_row_sparse * 2;
        if (analysis_row_nonsparse != 0)
            analysis_hybrid_cost = analysis_hybrid_cost + analysis_row_nonsparse + 2;
        analysis_use_sparse = analysis_use_sparse &&
                              (analysis_hybrid_cost <= analysis_row_cost);

        // BANK is selected only for a strict word saving over the best
        // SPARSE/ROW mixture.  Equal cost keeps the shorter packet lock.
        analysis_bank_cost = analysis_tile_count + 3;
        analysis_use_bank = (analysis_row_count >= 2) &&
                            !analysis_first_time &&
                            ((analysis_max_time - analysis_min_time) <= MAX_BANK_DELTA) &&
                            (analysis_bank_cost < analysis_nonbank_cost);
    end

    // Pick the lowest remaining tile. Tile address is implicit from mask/order.
    always @* begin
        selected_tile = 4'd0;
        selected_tile_valid = 1'b0;
        for (scan_index = 0; scan_index < 16; scan_index = scan_index + 1) begin
            if (!selected_tile_valid && remaining_mask[scan_index]) begin
                selected_tile = scan_index[3:0];
                selected_tile_valid = 1'b1;
            end
        end

        remaining_without_selected = remaining_mask;
        if (selected_tile_valid)
            remaining_without_selected[selected_tile] = 1'b0;

        case (selected_row)
            2'd0: snapshot_columns = snapshot_mask[3:0];
            2'd1: snapshot_columns = snapshot_mask[7:4];
            2'd2: snapshot_columns = snapshot_mask[11:8];
            default: snapshot_columns = snapshot_mask[15:12];
        endcase

        selected_delta_full = stored_time[selected_tile] - packet_base_time;
    end

    // Packet stream. DATA = {delta[4:0], ON[3:0], OFF[3:0], reserved[2:0]}.
    always @* begin
        out_data = 16'b0;
        out_valid = 1'b0;
        out_last = 1'b0;
        case (state)
            ST_ROW_HEADER: begin
                // 11 | bank[7:0] | row[1:0] | active-column mask[3:0]
                out_data = {2'b11, BANK_ID, selected_row, snapshot_columns};
                out_valid = 1'b1;
            end
            ST_ROW_TIME: begin
                out_data = packet_base_time;
                out_valid = 1'b1;
            end
            ST_ROW_DATA: begin
                if (selected_tile_valid) begin
                    out_data = {selected_delta_full[4:0],
                                stored_on[selected_tile],
                                stored_off[selected_tile],
                                3'b000};
                    out_valid = 1'b1;
                    out_last = (remaining_without_selected == 16'b0);
                end
            end
            ST_BANK_HEADER: begin
                // 10 | bank[7:0] | tile_count[4:0] | reserved
                out_data = {2'b10, BANK_ID, packet_tile_count, 1'b0};
                out_valid = 1'b1;
            end
            ST_BANK_MASK: begin
                out_data = snapshot_mask;
                out_valid = 1'b1;
            end
            ST_BANK_TIME: begin
                out_data = packet_base_time;
                out_valid = 1'b1;
            end
            ST_BANK_DATA: begin
                if (selected_tile_valid) begin
                    out_data = {selected_delta_full[4:0],
                                stored_on[selected_tile],
                                stored_off[selected_tile],
                                3'b000};
                    out_valid = 1'b1;
                    out_last = (remaining_without_selected == 16'b0);
                end
            end
            ST_SPARSE_ADDR: begin
                // 0 | bank[7:0] | local tile[3:0] | pixel[1:0] | polarity
                // polarity: 1=ON, 0=OFF
                out_data = {1'b0, BANK_ID, selected_tile,
                            sparse_pixel, sparse_polarity};
                out_valid = 1'b1;
            end
            ST_SPARSE_TIME: begin
                out_data = stored_time[selected_tile];
                out_valid = 1'b1;
                out_last = 1'b1;
            end
            default: begin
                out_data = 16'b0;
                out_valid = 1'b0;
                out_last = 1'b0;
            end
        endcase
    end

    // A tile is released when its DATA word is accepted.
    always @* begin
        clear_mask = 16'b0;
        if ((state == ST_ROW_DATA || state == ST_BANK_DATA ||
             state == ST_SPARSE_TIME) &&
            out_valid && out_ready && selected_tile_valid) begin
            clear_mask[selected_tile] = 1'b1;
        end
        pending_after = (pending & ~clear_mask) | accept_mask;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            pending <= 16'b0;
            snapshot_mask <= 16'b0;
            remaining_mask <= 16'b0;
            packet_base_time <= 16'b0;
            selected_row <= 2'b0;
            packet_tile_count <= 5'b0;
            packet_bank_mode <= 1'b0;
            sparse_pixel <= 2'b0;
            sparse_polarity <= 1'b0;
        end else begin
            pending <= pending_after;

            for (capture_index = 0; capture_index < 16; capture_index = capture_index + 1) begin
                if (accept_mask[capture_index]) begin
                    stored_on[capture_index] <= tile_on_flat[capture_index*4 +: 4];
                    stored_off[capture_index] <= tile_off_flat[capture_index*4 +: 4];
                    stored_time[capture_index] <= time_now;
                end
            end

            case (state)
                ST_IDLE: begin
                    if (|(pending | accept_mask))
                        state <= ST_ANALYZE;
                end

                ST_ANALYZE: begin
                    if (!(|pending)) begin
                        state <= ST_IDLE;
                    end else if (analysis_use_bank) begin
                        snapshot_mask <= pending;
                        remaining_mask <= pending;
                        packet_base_time <= analysis_min_time;
                        packet_tile_count <= analysis_tile_count;
                        packet_bank_mode <= 1'b1;
                        state <= ST_BANK_HEADER;
                    end else if (analysis_use_sparse) begin
                        snapshot_mask <= (16'b1 << analysis_sparse_tile);
                        remaining_mask <= (16'b1 << analysis_sparse_tile);
                        packet_bank_mode <= 1'b0;
                        if (stored_on[analysis_sparse_tile] != 4'b0) begin
                            sparse_polarity <= 1'b1;
                            if (stored_on[analysis_sparse_tile][0])
                                sparse_pixel <= 2'd0;
                            else if (stored_on[analysis_sparse_tile][1])
                                sparse_pixel <= 2'd1;
                            else if (stored_on[analysis_sparse_tile][2])
                                sparse_pixel <= 2'd2;
                            else
                                sparse_pixel <= 2'd3;
                        end else begin
                            sparse_polarity <= 1'b0;
                            if (stored_off[analysis_sparse_tile][0])
                                sparse_pixel <= 2'd0;
                            else if (stored_off[analysis_sparse_tile][1])
                                sparse_pixel <= 2'd1;
                            else if (stored_off[analysis_sparse_tile][2])
                                sparse_pixel <= 2'd2;
                            else
                                sparse_pixel <= 2'd3;
                        end
                        state <= ST_SPARSE_ADDR;
                    end else begin
                        snapshot_mask <= analysis_row_mask;
                        remaining_mask <= analysis_row_mask;
                        packet_base_time <= analysis_row_min_time;
                        selected_row <= analysis_selected_row;
                        packet_tile_count <= analysis_tile_count;
                        packet_bank_mode <= 1'b0;
                        state <= ST_ROW_HEADER;
                    end
                end

                ST_ROW_HEADER: begin
                    if (out_valid && out_ready)
                        state <= ST_ROW_TIME;
                end

                ST_ROW_TIME: begin
                    if (out_valid && out_ready)
                        state <= ST_ROW_DATA;
                end

                ST_ROW_DATA: begin
                    if (out_valid && out_ready) begin
                        remaining_mask <= remaining_without_selected;
                        if (out_last) begin
                            if (|pending_after)
                                state <= ST_ANALYZE;
                            else
                                state <= ST_IDLE;
                        end
                    end
                end

                ST_BANK_HEADER: begin
                    if (out_valid && out_ready)
                        state <= ST_BANK_MASK;
                end

                ST_BANK_MASK: begin
                    if (out_valid && out_ready)
                        state <= ST_BANK_TIME;
                end

                ST_BANK_TIME: begin
                    if (out_valid && out_ready)
                        state <= ST_BANK_DATA;
                end

                ST_BANK_DATA: begin
                    if (out_valid && out_ready) begin
                        remaining_mask <= remaining_without_selected;
                        if (out_last) begin
                            if (|pending_after)
                                state <= ST_ANALYZE;
                            else
                                state <= ST_IDLE;
                        end
                    end
                end

                ST_SPARSE_ADDR: begin
                    if (out_valid && out_ready)
                        state <= ST_SPARSE_TIME;
                end

                ST_SPARSE_TIME: begin
                    if (out_valid && out_ready) begin
                        remaining_mask <= 16'b0;
                        if (|pending_after)
                            state <= ST_ANALYZE;
                        else
                            state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
