`timescale 1ns/1ps

module aer_bank_row_reader #(
    parameter [7:0] BANK_ID = 8'd0,
    parameter integer ENABLE_BINNING = 1
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

    localparam [1:0] STATE_IDLE   = 2'd0;
    localparam [1:0] STATE_HEADER = 2'd1;
    localparam [1:0] STATE_TIME   = 2'd2;
    localparam [1:0] STATE_DATA   = 2'd3;

    wire [15:0] encoded_has_event;
    wire [31:0] encoded_format_flat;
    wire [127:0] encoded_payload_flat;
    wire [31:0] encoded_flags_flat;

    reg [15:0] pending;
    reg [31:0] stored_format_flat;
    reg [127:0] stored_payload_flat;
    reg [31:0] stored_flags_flat;
    reg [63:0] stored_delta_flat;

    reg [63:0] row_base_time_flat;
    reg [3:0] row_base_valid;
    wire [3:0] row_request;
    wire [3:0] row_grant;
    wire       row_grant_valid;
    wire [1:0] row_grant_index;
    wire       row_advance;

    reg [1:0] state;
    reg [1:0] selected_row;
    reg [3:0] snapshot_columns;
    reg [3:0] remaining_columns;
    reg [15:0] snapshot_time;

    reg [1:0] selected_column;
    reg       selected_column_valid;
    reg       selected_column_last;
    integer   selected_tile_index;

    reg [15:0] accept_mask;
    reg [15:0] clear_mask;
    reg [15:0] pending_after;
    reg [3:0] row_accept_any;
    integer ready_tile_index;
    integer capture_tile_index;
    integer valid_row_index;

    genvar tile_gen;
    generate
        for (tile_gen = 0; tile_gen < 16; tile_gen = tile_gen + 1) begin : gen_encoder
            aer_tile_bitmap_encoder #(
                .ENABLE_BINNING(ENABLE_BINNING)
            ) encoder_i (
                .on_bitmap  (tile_on_flat[tile_gen*4 +: 4]),
                .off_bitmap (tile_off_flat[tile_gen*4 +: 4]),
                .has_event  (encoded_has_event[tile_gen]),
                .format     (encoded_format_flat[tile_gen*2 +: 2]),
                .payload    (encoded_payload_flat[tile_gen*8 +: 8]),
                .flags      (encoded_flags_flat[tile_gen*2 +: 2])
            );
        end
    endgenerate

    assign row_request[0] = |pending[3:0];
    assign row_request[1] = |pending[7:4];
    assign row_request[2] = |pending[11:8];
    assign row_request[3] = |pending[15:12];
    assign pending_debug  = pending;

    aer_locked_rr_arbiter #(
        .REQUESTS(4),
        .INDEX_WIDTH(2)
    ) row_arbiter_i (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (row_request),
        .advance     (row_advance),
        .grant       (row_grant),
        .grant_valid (row_grant_valid),
        .grant_index (row_grant_index)
    );

    always @* begin
        tile_in_ready = 16'b0;
        accept_mask   = 16'b0;
        row_accept_any = 4'b0;

        for (ready_tile_index = 0; ready_tile_index < 16;
             ready_tile_index = ready_tile_index + 1) begin
            tile_in_ready[ready_tile_index] = !pending[ready_tile_index] &&
                (!row_base_valid[ready_tile_index/4] ||
                 ((time_now -
                   row_base_time_flat[(ready_tile_index/4)*16 +: 16]) <=
                  16'd15));
            accept_mask[ready_tile_index] = tile_in_valid[ready_tile_index] &&
                tile_in_ready[ready_tile_index] &&
                encoded_has_event[ready_tile_index];
            row_accept_any[ready_tile_index/4] =
                row_accept_any[ready_tile_index/4] |
                accept_mask[ready_tile_index];
        end
    end

    always @* begin
        selected_column       = 2'd0;
        selected_column_valid = 1'b0;

        if (remaining_columns[0]) begin
            selected_column       = 2'd0;
            selected_column_valid = 1'b1;
        end else if (remaining_columns[1]) begin
            selected_column       = 2'd1;
            selected_column_valid = 1'b1;
        end else if (remaining_columns[2]) begin
            selected_column       = 2'd2;
            selected_column_valid = 1'b1;
        end else if (remaining_columns[3]) begin
            selected_column       = 2'd3;
            selected_column_valid = 1'b1;
        end

        selected_column_last =
            (remaining_columns == 4'b0001) ||
            (remaining_columns == 4'b0010) ||
            (remaining_columns == 4'b0100) ||
            (remaining_columns == 4'b1000);
    end

    always @* begin
        out_data  = 16'b0;
        out_valid = 1'b0;
        out_last  = 1'b0;
        selected_tile_index = selected_row * 4 + selected_column;

        case (state)
            STATE_HEADER: begin
                out_data  = {2'b11, BANK_ID, selected_row, snapshot_columns};
                out_valid = 1'b1;
            end
            STATE_TIME: begin
                out_data  = snapshot_time;
                out_valid = 1'b1;
            end
            STATE_DATA: begin
                out_data = {
                    stored_format_flat[selected_tile_index*2 +: 2],
                    stored_delta_flat[selected_tile_index*4 +: 4],
                    stored_payload_flat[selected_tile_index*8 +: 8],
                    stored_flags_flat[selected_tile_index*2 +: 2]
                };
                out_valid = selected_column_valid;
                out_last  = selected_column_valid && selected_column_last;
            end
            default: begin
                out_data  = 16'b0;
                out_valid = 1'b0;
                out_last  = 1'b0;
            end
        endcase
    end

    always @* begin
        clear_mask = 16'b0;
        if ((state == STATE_DATA) && out_valid && out_ready)
            clear_mask[selected_tile_index] = 1'b1;
        pending_after = (pending & ~clear_mask) | accept_mask;
    end

    assign row_advance = (state == STATE_DATA) && out_valid && out_ready && out_last;

    always @(posedge clk) begin
        if (!rst_n) begin
            pending             <= 16'b0;
            stored_format_flat  <= 32'b0;
            stored_payload_flat <= 128'b0;
            stored_flags_flat   <= 32'b0;
            stored_delta_flat   <= 64'b0;
            row_base_time_flat  <= 64'b0;
            row_base_valid      <= 4'b0;
            state               <= STATE_IDLE;
            selected_row        <= 2'b0;
            snapshot_columns    <= 4'b0;
            remaining_columns   <= 4'b0;
            snapshot_time       <= 16'b0;
        end else begin
            pending <= pending_after;

            for (capture_tile_index = 0; capture_tile_index < 16;
                 capture_tile_index = capture_tile_index + 1) begin
                if (accept_mask[capture_tile_index]) begin
                    stored_format_flat[capture_tile_index*2 +: 2] <=
                        encoded_format_flat[capture_tile_index*2 +: 2];
                    stored_payload_flat[capture_tile_index*8 +: 8] <=
                        encoded_payload_flat[capture_tile_index*8 +: 8];
                    stored_flags_flat[capture_tile_index*2 +: 2] <=
                        encoded_flags_flat[capture_tile_index*2 +: 2];

                    if (row_base_valid[capture_tile_index/4])
                        stored_delta_flat[capture_tile_index*4 +: 4] <=
                            (time_now -
                             row_base_time_flat[(capture_tile_index/4)*16 +: 16]);
                    else
                        stored_delta_flat[capture_tile_index*4 +: 4] <= 4'd0;
                end
            end

            for (valid_row_index = 0; valid_row_index < 4;
                 valid_row_index = valid_row_index + 1) begin
                if (!row_base_valid[valid_row_index] &&
                    row_accept_any[valid_row_index]) begin
                    row_base_valid[valid_row_index] <= 1'b1;
                    row_base_time_flat[valid_row_index*16 +: 16] <= time_now;
                end else if (!(|pending_after[valid_row_index*4 +: 4])) begin
                    row_base_valid[valid_row_index] <= 1'b0;
                end
            end

            case (state)
                STATE_IDLE: begin
                    if (row_grant_valid) begin
                        selected_row      <= row_grant_index;
                        snapshot_columns <= pending[row_grant_index*4 +: 4];
                        remaining_columns <= pending[row_grant_index*4 +: 4];
                        snapshot_time     <=
                            row_base_time_flat[row_grant_index*16 +: 16];
                        state             <= STATE_HEADER;
                    end
                end
                STATE_HEADER: begin
                    if (out_valid && out_ready)
                        state <= STATE_TIME;
                end
                STATE_TIME: begin
                    if (out_valid && out_ready)
                        state <= STATE_DATA;
                end
                STATE_DATA: begin
                    if (out_valid && out_ready) begin
                        remaining_columns[selected_column] <= 1'b0;
                        if (out_last)
                            state <= STATE_IDLE;
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
