`timescale 1ns/1ps

// V4 lightweight packetizer for one 8x8-pixel bank.
// Only the selected 4-tile row is analyzed. BANK packets and bank-wide
// timestamp/cost optimization are intentionally absent.
module aer_bank_packetizer_v4 #(
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
    output wire [15:0]   pending_debug
);
    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_ANALYZE     = 3'd1;
    localparam [2:0] ST_ROW_HEADER  = 3'd2;
    localparam [2:0] ST_ROW_TIME    = 3'd3;
    localparam [2:0] ST_ROW_DATA    = 3'd4;
    localparam [2:0] ST_SPARSE_ADDR = 3'd5;
    localparam [2:0] ST_SPARSE_TIME = 3'd6;

    reg [2:0] state;
    reg [15:0] pending;
    reg [3:0] stored_on [0:15];
    reg [3:0] stored_off [0:15];
    reg [15:0] stored_time [0:15];

    reg [1:0] selected_row;
    reg [3:0] packet_columns;
    reg [3:0] remaining_columns;
    reg [15:0] packet_base_time;
    reg [1:0] sparse_pixel;
    reg sparse_polarity;

    reg [15:0] accept_mask;
    reg [15:0] clear_mask;
    reg [15:0] pending_after;

    integer ready_index;
    integer capture_index;
    integer analysis_col;
    integer analysis_index;

    // Only one selected row is examined for mode selection.
    reg [1:0] analysis_selected_row;
    reg [3:0] analysis_row_base;
    reg [3:0] analysis_row_pending;
    reg [15:0] analysis_min_time;
    reg analysis_first_time;
    reg [3:0] analysis_columns;
    reg [2:0] analysis_tile_count;
    reg [3:0] analysis_individual_cost;
    reg [3:0] analysis_row_cost;
    reg analysis_use_row;
    reg [1:0] analysis_first_col;
    reg analysis_first_valid;
    reg analysis_first_singleton;
    reg [7:0] analysis_event_bits;

    // Current ROW DATA-word selection.
    reg [1:0] selected_column;
    reg [3:0] selected_tile;
    reg selected_tile_valid;
    reg [3:0] remaining_without_selected;
    reg [15:0] selected_delta_full;

    function is_singleton8;
        input [7:0] bits;
        begin
            case (bits)
                8'h01, 8'h02, 8'h04, 8'h08,
                8'h10, 8'h20, 8'h40, 8'h80:
                    is_singleton8 = 1'b1;
                default:
                    is_singleton8 = 1'b0;
            endcase
        end
    endfunction

    function [1:0] first_pixel4;
        input [3:0] bits;
        begin
            if (bits[0])
                first_pixel4 = 2'd0;
            else if (bits[1])
                first_pixel4 = 2'd1;
            else if (bits[2])
                first_pixel4 = 2'd2;
            else
                first_pixel4 = 2'd3;
        end
    endfunction

    assign pending_debug = pending;

    // One pending slot per tile. Empty bitmap inputs are not accepted.
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

    // Select the lowest active row, then analyze only its four tiles.
    always @* begin
        analysis_selected_row = 2'd0;
        analysis_row_base = 4'd0;
        analysis_row_pending = pending[3:0];
        if (|pending[3:0]) begin
            analysis_selected_row = 2'd0;
            analysis_row_base = 4'd0;
            analysis_row_pending = pending[3:0];
        end else if (|pending[7:4]) begin
            analysis_selected_row = 2'd1;
            analysis_row_base = 4'd4;
            analysis_row_pending = pending[7:4];
        end else if (|pending[11:8]) begin
            analysis_selected_row = 2'd2;
            analysis_row_base = 4'd8;
            analysis_row_pending = pending[11:8];
        end else begin
            analysis_selected_row = 2'd3;
            analysis_row_base = 4'd12;
            analysis_row_pending = pending[15:12];
        end

        analysis_min_time = 16'hffff;
        analysis_first_time = 1'b1;
        for (analysis_col = 0; analysis_col < 4; analysis_col = analysis_col + 1) begin
            analysis_index = analysis_row_base + analysis_col;
            if (analysis_row_pending[analysis_col]) begin
                if (analysis_first_time) begin
                    analysis_min_time = stored_time[analysis_index];
                    analysis_first_time = 1'b0;
                end else if (stored_time[analysis_index] < analysis_min_time) begin
                    analysis_min_time = stored_time[analysis_index];
                end
            end
        end

        analysis_columns = 4'b0;
        analysis_tile_count = 3'd0;
        analysis_individual_cost = 4'd0;
        analysis_first_col = 2'd0;
        analysis_first_valid = 1'b0;
        analysis_first_singleton = 1'b0;
        analysis_event_bits = 8'b0;
        for (analysis_col = 0; analysis_col < 4; analysis_col = analysis_col + 1) begin
            analysis_index = analysis_row_base + analysis_col;
            if (analysis_row_pending[analysis_col] &&
                ((stored_time[analysis_index] - analysis_min_time) <=
                 MAX_BANK_DELTA)) begin
                analysis_columns[analysis_col] = 1'b1;
                analysis_tile_count = analysis_tile_count + 1'b1;
                analysis_event_bits = {stored_on[analysis_index],
                                       stored_off[analysis_index]};
                if (is_singleton8(analysis_event_bits))
                    analysis_individual_cost = analysis_individual_cost + 4'd2;
                else
                    analysis_individual_cost = analysis_individual_cost + 4'd3;

                // Individual mode sends the oldest eligible tile first.
                if (!analysis_first_valid &&
                    (stored_time[analysis_index] == analysis_min_time)) begin
                    analysis_first_col = analysis_col[1:0];
                    analysis_first_valid = 1'b1;
                    analysis_first_singleton =
                        is_singleton8(analysis_event_bits);
                end
            end
        end

        analysis_row_cost = analysis_tile_count + 4'd2;
        analysis_use_row = (analysis_row_cost < analysis_individual_cost);
    end

    // Remaining data is always confined to the selected four-tile row.
    always @* begin
        selected_column = 2'd0;
        selected_tile_valid = |remaining_columns;
        if (remaining_columns[0])
            selected_column = 2'd0;
        else if (remaining_columns[1])
            selected_column = 2'd1;
        else if (remaining_columns[2])
            selected_column = 2'd2;
        else
            selected_column = 2'd3;

        selected_tile = {selected_row, selected_column};
        remaining_without_selected = remaining_columns;
        if (selected_tile_valid)
            remaining_without_selected[selected_column] = 1'b0;
        selected_delta_full = stored_time[selected_tile] - packet_base_time;
    end

    // SPARSE and ROW words retain the V3 bit layout.
    always @* begin
        out_data = 16'b0;
        out_valid = 1'b0;
        out_last = 1'b0;
        case (state)
            ST_ROW_HEADER: begin
                // 11 | bank[7:0] | row[1:0] | active-column mask[3:0]
                out_data = {2'b11, BANK_ID, selected_row, packet_columns};
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
                    out_last = (remaining_without_selected == 4'b0);
                end
            end
            ST_SPARSE_ADDR: begin
                // 0 | bank[7:0] | local tile[3:0] | pixel[1:0] | polarity
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

    // Pending storage is released only on the final word handshake.
    always @* begin
        clear_mask = 16'b0;
        if ((state == ST_ROW_DATA || state == ST_SPARSE_TIME) &&
            out_valid && out_ready && selected_tile_valid) begin
            clear_mask[selected_tile] = 1'b1;
        end
        pending_after = (pending & ~clear_mask) | accept_mask;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            pending <= 16'b0;
            selected_row <= 2'b0;
            packet_columns <= 4'b0;
            remaining_columns <= 4'b0;
            packet_base_time <= 16'b0;
            sparse_pixel <= 2'b0;
            sparse_polarity <= 1'b0;
        end else begin
            pending <= pending_after;

            for (capture_index = 0; capture_index < 16;
                 capture_index = capture_index + 1) begin
                if (accept_mask[capture_index]) begin
                    stored_on[capture_index] <=
                        tile_on_flat[capture_index*4 +: 4];
                    stored_off[capture_index] <=
                        tile_off_flat[capture_index*4 +: 4];
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
                    end else if (analysis_use_row) begin
                        selected_row <= analysis_selected_row;
                        packet_columns <= analysis_columns;
                        remaining_columns <= analysis_columns;
                        packet_base_time <= analysis_min_time;
                        state <= ST_ROW_HEADER;
                    end else begin
                        selected_row <= analysis_selected_row;
                        packet_columns <= (4'b0001 << analysis_first_col);
                        remaining_columns <= (4'b0001 << analysis_first_col);
                        packet_base_time <=
                            stored_time[analysis_row_base + analysis_first_col];
                        if (analysis_first_singleton) begin
                            if (stored_on[analysis_row_base +
                                          analysis_first_col] != 4'b0) begin
                                sparse_polarity <= 1'b1;
                                sparse_pixel <=
                                    first_pixel4(stored_on[analysis_row_base +
                                                           analysis_first_col]);
                            end else begin
                                sparse_polarity <= 1'b0;
                                sparse_pixel <=
                                    first_pixel4(stored_off[analysis_row_base +
                                                            analysis_first_col]);
                            end
                            state <= ST_SPARSE_ADDR;
                        end else begin
                            // Lossless single-tile ROW fallback for multi-bit.
                            state <= ST_ROW_HEADER;
                        end
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
                        remaining_columns <= remaining_without_selected;
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
                        remaining_columns <= 4'b0;
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
