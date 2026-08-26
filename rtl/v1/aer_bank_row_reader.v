`timescale 1ns/1ps

module aer_bank_row_reader #(
    parameter [15:0] BANK_ID = 16'd0,
    parameter integer EXTENDED_BANK_ID = 0,
    parameter integer ENABLE_BINNING = 1,
    parameter integer ENABLE_ROW_FUSION = 0,
    parameter integer ENABLE_BANK_FUSION = 0,
    parameter integer ENABLE_LOSSY_BINNING = 0,
    parameter integer EXTERNAL_RX_TIMESTAMP = 0
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

    localparam [2:0] STATE_IDLE        = 3'd0;
    localparam [2:0] STATE_HEADER_HOLD = 3'd1;
    localparam [2:0] STATE_BANK_EXT    = 3'd2;
    localparam [2:0] STATE_TIME        = 3'd3;
    localparam [2:0] STATE_DATA        = 3'd4;
    localparam [2:0] STATE_BANK_MASK   = 3'd5;
    localparam [2:0] STATE_BANK_DATA   = 3'd6;
    localparam [2:0] STATE_BANK_BINMASK = 3'd7;

    localparam [1:0] FORMAT_RAW8   = 2'b00;
    localparam [1:0] FORMAT_GROUP3 = 2'b01;
    localparam [1:0] FORMAT_BIN4   = 2'b10;
    localparam [1:0] FORMAT_ROW    = 2'b11;

    wire [15:0]  encoded_has_event;
    wire [31:0]  encoded_format_flat;
    wire [127:0] encoded_payload_flat;
    wire [31:0]  encoded_flags_flat;

    reg [15:0]  pending;
    reg [31:0]  stored_format_flat;
    reg [127:0] stored_payload_flat;
    reg [127:0] stored_raw_flat;
    reg [31:0]  stored_flags_flat;
    reg [63:0]  stored_delta_flat;

    reg [63:0] row_base_time_flat;
    reg [3:0]  row_base_valid;
    wire [3:0] row_request;
    wire [3:0] row_grant;
    wire       row_grant_valid;
    wire [1:0] row_grant_index;
    wire       row_advance;

    reg [2:0]  state;
    reg [1:0]  selected_row;
    reg [3:0]  snapshot_columns;
    reg [3:0]  remaining_columns;
    reg [15:0] snapshot_time;

    // Cost-gated bank packet.  A snapshot remains pending until the final
    // payload word so bank fusion does not gain hidden buffering capacity.
    reg         packet_bank_fusion;
    reg [15:0]  bank_snapshot_mask;
    reg [15:0]  bank_snapshot_bin_mask;
    reg [1:0]   bank_snapshot_mode;
    reg [3:0]   bank_snapshot_count_minus_one;
    reg [127:0] bank_payload_shift;
    reg [3:0]   bank_payload_words_remaining;

    reg [15:0]  bank_candidate_mask;
    reg [31:0]  bank_candidate_format_flat;
    reg [127:0] bank_candidate_payload_flat;
    reg [127:0] bank_candidate_raw_flat;
    reg [31:0]  bank_candidate_flags_flat;
    reg [1:0]   bank_candidate_mode;
    reg [3:0]   bank_candidate_count_minus_one;
    reg [127:0] bank_candidate_payload;
    reg [127:0] bank_candidate_raw_payload;
    reg [127:0] bank_candidate_lossy_payload;
    reg [15:0]  bank_candidate_bin_mask;
    reg [3:0]   bank_candidate_payload_words;
    reg         bank_candidate_use;
    reg         bank_all_raw8;
    reg         bank_all_group3;
    reg         bank_all_bin4;
    reg         bank_all_flags_clear;
    integer     bank_candidate_count;
    integer     bank_row_cost;
    integer     bank_packet_cost;
    integer     bank_raw_packet_cost;
    integer     bank_lossy_packet_cost;
    integer     bank_lossy_payload_words;
    integer     bank_row_tile_count;
    integer     bank_pack_bit_index;
    integer     bank_raw_pack_bit_index;
    integer     bank_lossy_pack_bit_index;
    integer     bank_tile_index;
    integer     bank_row_index;
    integer     bank_column_index;

    reg [1:0] selected_column;
    reg       selected_column_valid;
    reg [1:0] paired_column;
    reg       paired_column_valid;
    reg       pack_bin_pair;
    reg [3:0] emit_column_mask;
    reg       selected_column_last;
    reg [3:0] remaining_without_first;
    reg       row_all_bin4;
    reg       row_all_group3;
    reg       row_fusion_active;
    reg [3:0] row_bin4_polarities;
    reg [11:0] row_group3_tokens;
    integer   selected_tile_index;
    integer   paired_tile_index;
    integer   fusion_column_index;
    integer   fusion_tile_index;

    reg [15:0] accept_mask;
    reg [15:0] clear_mask;
    reg [15:0] pending_after;
    reg [3:0]  row_accept_any;
    integer    ready_tile_index;
    integer    capture_tile_index;
    integer    valid_row_index;

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

    // One pending slot per tile is intentionally retained.  This change does
    // not add the deferred per-tile FIFO storage.
    always @* begin
        tile_in_ready = 16'b0;
        accept_mask = 16'b0;
        row_accept_any = 4'b0;

        for (ready_tile_index = 0; ready_tile_index < 16;
             ready_tile_index = ready_tile_index + 1) begin
            tile_in_ready[ready_tile_index] = !pending[ready_tile_index] &&
                ((EXTERNAL_RX_TIMESTAMP != 0) ||
                 !row_base_valid[ready_tile_index/4] ||
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

    // Consider all currently pending tiles in this bank, including tiles
    // accepted on the packet-start cycle.  The lossless path requires one
    // common format.  The lossy path may mix one-bit BIN and RAW8 tokens, but
    // is selected only when its exact word cost beats both lossless choices.
    always @* begin
        bank_candidate_mask = pending | accept_mask;
        bank_candidate_format_flat = stored_format_flat;
        bank_candidate_payload_flat = stored_payload_flat;
        bank_candidate_raw_flat = stored_raw_flat;
        bank_candidate_flags_flat = stored_flags_flat;
        bank_candidate_count = 0;
        bank_all_raw8 = (bank_candidate_mask != 16'b0);
        bank_all_group3 = (bank_candidate_mask != 16'b0);
        bank_all_bin4 = (bank_candidate_mask != 16'b0);
        bank_all_flags_clear = 1'b1;

        for (bank_tile_index = 0; bank_tile_index < 16;
             bank_tile_index = bank_tile_index + 1) begin
            if (accept_mask[bank_tile_index]) begin
                bank_candidate_format_flat[bank_tile_index*2 +: 2] =
                    encoded_format_flat[bank_tile_index*2 +: 2];
                bank_candidate_payload_flat[bank_tile_index*8 +: 8] =
                    encoded_payload_flat[bank_tile_index*8 +: 8];
                bank_candidate_raw_flat[bank_tile_index*8 +: 8] = {
                    tile_on_flat[bank_tile_index*4 +: 4],
                    tile_off_flat[bank_tile_index*4 +: 4]
                };
                bank_candidate_flags_flat[bank_tile_index*2 +: 2] =
                    encoded_flags_flat[bank_tile_index*2 +: 2];
            end
            if (bank_candidate_mask[bank_tile_index]) begin
                bank_candidate_count = bank_candidate_count + 1;
                if (bank_candidate_format_flat[bank_tile_index*2 +: 2] !=
                    FORMAT_RAW8)
                    bank_all_raw8 = 1'b0;
                if (bank_candidate_format_flat[bank_tile_index*2 +: 2] !=
                    FORMAT_GROUP3)
                    bank_all_group3 = 1'b0;
                if (bank_candidate_format_flat[bank_tile_index*2 +: 2] !=
                    FORMAT_BIN4)
                    bank_all_bin4 = 1'b0;
                if (bank_candidate_flags_flat[bank_tile_index*2 +: 2] != 2'b0)
                    bank_all_flags_clear = 1'b0;
            end
        end

        bank_candidate_mode = FORMAT_RAW8;
        if (bank_all_group3)
            bank_candidate_mode = FORMAT_GROUP3;
        else if (bank_all_bin4)
            bank_candidate_mode = FORMAT_BIN4;

        bank_candidate_payload = 128'b0;
        bank_candidate_raw_payload = 128'b0;
        bank_candidate_lossy_payload = 128'b0;
        bank_candidate_bin_mask = 16'b0;
        bank_pack_bit_index = 0;
        bank_raw_pack_bit_index = 0;
        bank_lossy_pack_bit_index = 0;
        for (bank_tile_index = 0; bank_tile_index < 16;
             bank_tile_index = bank_tile_index + 1) begin
            if (bank_candidate_mask[bank_tile_index]) begin
                bank_candidate_raw_payload[bank_raw_pack_bit_index +: 8] =
                    bank_candidate_raw_flat[bank_tile_index*8 +: 8];
                bank_raw_pack_bit_index = bank_raw_pack_bit_index + 8;

                if ((bank_candidate_format_flat[bank_tile_index*2 +: 2] ==
                     FORMAT_GROUP3) ||
                    (bank_candidate_format_flat[bank_tile_index*2 +: 2] ==
                     FORMAT_BIN4)) begin
                    bank_candidate_bin_mask[bank_tile_index] = 1'b1;
                    bank_candidate_lossy_payload[bank_lossy_pack_bit_index] =
                        bank_candidate_payload_flat[bank_tile_index*8 + 7];
                    bank_lossy_pack_bit_index = bank_lossy_pack_bit_index + 1;
                end else begin
                    bank_candidate_lossy_payload[
                        bank_lossy_pack_bit_index +: 8] =
                        bank_candidate_raw_flat[bank_tile_index*8 +: 8];
                    bank_lossy_pack_bit_index = bank_lossy_pack_bit_index + 8;
                end

                case (bank_candidate_mode)
                    FORMAT_RAW8: begin
                        bank_candidate_payload[bank_pack_bit_index +: 8] =
                            bank_candidate_payload_flat[bank_tile_index*8 +: 8];
                        bank_pack_bit_index = bank_pack_bit_index + 8;
                    end
                    FORMAT_GROUP3: begin
                        bank_candidate_payload[bank_pack_bit_index +: 3] = {
                            bank_candidate_payload_flat[bank_tile_index*8 + 7],
                            bank_candidate_payload_flat[bank_tile_index*8 + 6 -: 2]
                        };
                        bank_pack_bit_index = bank_pack_bit_index + 3;
                    end
                    default: begin
                        bank_candidate_payload[bank_pack_bit_index] =
                            bank_candidate_payload_flat[bank_tile_index*8 + 7];
                        bank_pack_bit_index = bank_pack_bit_index + 1;
                    end
                endcase
            end
        end

        bank_candidate_payload_words = 4'd0;
        case (bank_candidate_mode)
            FORMAT_RAW8:
                bank_candidate_payload_words = (bank_candidate_count + 1) / 2;
            FORMAT_GROUP3:
                bank_candidate_payload_words =
                    ((bank_candidate_count * 3) + 15) / 16;
            FORMAT_BIN4:
                bank_candidate_payload_words = 4'd1;
            default:
                bank_candidate_payload_words = 4'd0;
        endcase

        bank_row_cost = 0;
        for (bank_row_index = 0; bank_row_index < 4;
             bank_row_index = bank_row_index + 1) begin
            bank_row_tile_count = 0;
            for (bank_column_index = 0; bank_column_index < 4;
                 bank_column_index = bank_column_index + 1) begin
                if (bank_candidate_mask[bank_row_index*4 + bank_column_index])
                    bank_row_tile_count = bank_row_tile_count + 1;
            end
            if (bank_row_tile_count != 0) begin
                // One row header plus the existing data-path word count.
                bank_row_cost = bank_row_cost + 1;
                if (ENABLE_LOSSY_BINNING != 0)
                    bank_row_cost = bank_row_cost + bank_row_tile_count;
                else if ((ENABLE_ROW_FUSION != 0) &&
                    (bank_all_group3 || bank_all_bin4))
                    bank_row_cost = bank_row_cost + 1;
                else if (bank_all_bin4)
                    bank_row_cost = bank_row_cost +
                        ((bank_row_tile_count + 1) / 2);
                else
                    bank_row_cost = bank_row_cost + bank_row_tile_count;
            end
        end

        bank_packet_cost = 2 + bank_candidate_payload_words;
        bank_raw_packet_cost = 2 + ((bank_candidate_count + 1) / 2);
        bank_lossy_payload_words = (bank_lossy_pack_bit_index + 15) / 16;
        bank_lossy_packet_cost = 3 + bank_lossy_payload_words;
        bank_candidate_count_minus_one = 4'b0;
        if (bank_candidate_count != 0)
            bank_candidate_count_minus_one = bank_candidate_count - 1;
        bank_candidate_use = 1'b0;
        if ((ENABLE_BANK_FUSION != 0) &&
            (EXTERNAL_RX_TIMESTAMP != 0) &&
            (EXTENDED_BANK_ID == 0) &&
            (bank_candidate_count != 0)) begin
            if (ENABLE_LOSSY_BINNING != 0) begin
                // Match the Python policy exactly: compare a mixed lossy
                // packet against both RAW-bank packing and row RAW.  A tie
                // falls back to the lossless choice.
                if ((bank_candidate_count > 1) &&
                    (bank_lossy_packet_cost < bank_raw_packet_cost) &&
                    (bank_lossy_packet_cost < bank_row_cost)) begin
                    bank_candidate_mode = FORMAT_ROW;
                    bank_candidate_payload = bank_candidate_lossy_payload;
                    bank_candidate_payload_words =
                        bank_lossy_payload_words[3:0];
                    bank_candidate_use = 1'b1;
                end else if ((bank_candidate_count > 1) &&
                             (bank_raw_packet_cost < bank_row_cost)) begin
                    bank_candidate_mode = FORMAT_RAW8;
                    bank_candidate_payload = bank_candidate_raw_payload;
                    bank_candidate_payload_words =
                        (bank_candidate_count + 1) / 2;
                    bank_candidate_bin_mask = 16'b0;
                    bank_candidate_use = 1'b1;
                end
            end else begin
                bank_candidate_use =
                    (bank_all_raw8 || bank_all_group3 || bank_all_bin4) &&
                    bank_all_flags_clear &&
                    (bank_packet_cost < bank_row_cost);
            end
        end
    end

    // Select the next active column.  Row fusion never changes arbitration or
    // waits for more input: it only replaces the data words of an already
    // selected row when every active tile has the same compressible format.
    always @* begin
        selected_column = 2'd0;
        selected_column_valid = 1'b0;

        if (remaining_columns[0]) begin
            selected_column = 2'd0;
            selected_column_valid = 1'b1;
        end else if (remaining_columns[1]) begin
            selected_column = 2'd1;
            selected_column_valid = 1'b1;
        end else if (remaining_columns[2]) begin
            selected_column = 2'd2;
            selected_column_valid = 1'b1;
        end else if (remaining_columns[3]) begin
            selected_column = 2'd3;
            selected_column_valid = 1'b1;
        end

        remaining_without_first = remaining_columns;
        if (selected_column_valid)
            remaining_without_first[selected_column] = 1'b0;

        paired_column = 2'd0;
        paired_column_valid = 1'b0;
        if (remaining_without_first[0]) begin
            paired_column = 2'd0;
            paired_column_valid = 1'b1;
        end else if (remaining_without_first[1]) begin
            paired_column = 2'd1;
            paired_column_valid = 1'b1;
        end else if (remaining_without_first[2]) begin
            paired_column = 2'd2;
            paired_column_valid = 1'b1;
        end else if (remaining_without_first[3]) begin
            paired_column = 2'd3;
            paired_column_valid = 1'b1;
        end

        selected_tile_index = selected_row * 4 + selected_column;
        paired_tile_index = selected_row * 4 + paired_column;
        pack_bin_pair = (ENABLE_LOSSY_BINNING == 0) &&
            selected_column_valid && paired_column_valid &&
            (stored_format_flat[selected_tile_index*2 +: 2] == FORMAT_BIN4) &&
            (stored_format_flat[paired_tile_index*2 +: 2] == FORMAT_BIN4);

        row_all_bin4 = (remaining_columns != 4'b0);
        row_all_group3 = (remaining_columns != 4'b0);
        row_bin4_polarities = 4'b0;
        row_group3_tokens = 12'b0;
        for (fusion_column_index = 0; fusion_column_index < 4;
             fusion_column_index = fusion_column_index + 1) begin
            fusion_tile_index = selected_row * 4 + fusion_column_index;
            if (remaining_columns[fusion_column_index]) begin
                if (stored_format_flat[fusion_tile_index*2 +: 2] != FORMAT_BIN4)
                    row_all_bin4 = 1'b0;
                if (stored_format_flat[fusion_tile_index*2 +: 2] != FORMAT_GROUP3)
                    row_all_group3 = 1'b0;
                row_bin4_polarities[fusion_column_index] =
                    stored_payload_flat[fusion_tile_index*8 + 7];
                row_group3_tokens[fusion_column_index*3 +: 3] = {
                    stored_payload_flat[fusion_tile_index*8 + 7],
                    stored_payload_flat[fusion_tile_index*8 + 6 -: 2]
                };
            end
        end
        row_fusion_active = (ENABLE_LOSSY_BINNING == 0) &&
            (ENABLE_ROW_FUSION != 0) &&
            (EXTERNAL_RX_TIMESTAMP != 0) &&
            (remaining_columns == snapshot_columns) &&
            (row_all_bin4 || row_all_group3);

        emit_column_mask = 4'b0;
        if (row_fusion_active)
            emit_column_mask = remaining_columns;
        else if (selected_column_valid)
            emit_column_mask[selected_column] = 1'b1;
        if (!row_fusion_active && pack_bin_pair)
            emit_column_mask[paired_column] = 1'b1;

        selected_column_last = selected_column_valid &&
            ((remaining_columns & ~emit_column_mask) == 4'b0);
    end

    always @* begin
        out_data = 16'b0;
        out_valid = 1'b0;
        out_last = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (row_grant_valid) begin
                    if (bank_candidate_use)
                        // Bank header: type, bank, mode, active-count-minus-one.
                        out_data = {2'b10, BANK_ID[7:0],
                                    bank_candidate_mode,
                                    bank_candidate_count_minus_one};
                    else
                        out_data = {
                            2'b11,
                            BANK_ID[7:0],
                            row_grant_index,
                            (pending[row_grant_index*4 +: 4] |
                             accept_mask[row_grant_index*4 +: 4])
                        };
                    out_valid = 1'b1;
                end
            end
            STATE_HEADER_HOLD: begin
                if (packet_bank_fusion)
                    out_data = {2'b10, BANK_ID[7:0], bank_snapshot_mode,
                                bank_snapshot_count_minus_one};
                else
                    out_data = {2'b11, BANK_ID[7:0], selected_row,
                                snapshot_columns};
                out_valid = 1'b1;
            end
            STATE_BANK_EXT: begin
                // Present only when a configured sensor needs more than eight
                // bank-address bits.  The decoder knows this from configuration.
                out_data = {8'b0, BANK_ID[15:8]};
                out_valid = 1'b1;
            end
            STATE_TIME: begin
                out_data = snapshot_time;
                out_valid = 1'b1;
            end
            STATE_DATA: begin
                out_valid = selected_column_valid;
                out_last = selected_column_last;

                if (ENABLE_LOSSY_BINNING != 0) begin
                    // Cost fallback for the lossy policy is always exact RAW8.
                    out_data = {
                        FORMAT_RAW8,
                        stored_delta_flat[selected_tile_index*4 +: 4],
                        stored_raw_flat[selected_tile_index*8 +: 8],
                        stored_flags_flat[selected_tile_index*2 +: 2]
                    };
                end else if (row_fusion_active && row_all_bin4) begin
                    // Data-phase-only row format.  Header column bits identify
                    // which of the four fixed polarity positions are valid.
                    // [15:14]=11, [13]=0, [12:9]=polarity[col3:col0].
                    out_data = {
                        FORMAT_ROW,
                        1'b0,
                        row_bin4_polarities,
                        9'b0
                    };
                end else if (row_fusion_active && row_all_group3) begin
                    // [15:14]=11, [13]=1.  Bits [12:1] contain four fixed
                    // {polarity, missing_pixel[1:0]} tokens, one per column.
                    out_data = {
                        FORMAT_ROW,
                        1'b1,
                        row_group3_tokens,
                        1'b0
                    };
                end else if (pack_bin_pair) begin
                    // [15:14] BIN4, [13] pair, then two {delta, polarity}
                    // tokens in ascending active-column order.
                    out_data = {
                        FORMAT_BIN4,
                        1'b1,
                        stored_delta_flat[selected_tile_index*4 +: 4],
                        stored_payload_flat[selected_tile_index*8 + 7],
                        stored_delta_flat[paired_tile_index*4 +: 4],
                        stored_payload_flat[paired_tile_index*8 + 7],
                        3'b000
                    };
                end else if (stored_format_flat[selected_tile_index*2 +: 2] ==
                             FORMAT_BIN4) begin
                    // [15:14] BIN4, [13] single, [12:9] delta, [8] polarity.
                    out_data = {
                        FORMAT_BIN4,
                        1'b0,
                        stored_delta_flat[selected_tile_index*4 +: 4],
                        stored_payload_flat[selected_tile_index*8 + 7],
                        8'b0
                    };
                end else begin
                    out_data = {
                        stored_format_flat[selected_tile_index*2 +: 2],
                        stored_delta_flat[selected_tile_index*4 +: 4],
                        stored_payload_flat[selected_tile_index*8 +: 8],
                        stored_flags_flat[selected_tile_index*2 +: 2]
                    };
                end
            end
            STATE_BANK_MASK: begin
                out_data = bank_snapshot_mask;
                out_valid = 1'b1;
            end
            STATE_BANK_BINMASK: begin
                out_data = bank_snapshot_bin_mask;
                out_valid = 1'b1;
            end
            STATE_BANK_DATA: begin
                out_data = bank_payload_shift[15:0];
                out_valid = (bank_payload_words_remaining != 0);
                out_last = (bank_payload_words_remaining == 1);
            end
            default: begin
                out_data = 16'b0;
                out_valid = 1'b0;
                out_last = 1'b0;
            end
        endcase
    end

    always @* begin
        clear_mask = 16'b0;
        if ((state == STATE_DATA) && out_valid && out_ready) begin
            if (row_fusion_active)
                clear_mask[selected_row*4 +: 4] = remaining_columns;
            else
                clear_mask[selected_row*4 + selected_column] = 1'b1;
            if (!row_fusion_active && pack_bin_pair)
                clear_mask[selected_row*4 + paired_column] = 1'b1;
        end else if ((state == STATE_BANK_DATA) && out_valid && out_ready &&
                     out_last) begin
            clear_mask = bank_snapshot_mask;
        end
        pending_after = (pending & ~clear_mask) | accept_mask;
    end

    assign row_advance = out_valid && out_ready && out_last &&
        ((state == STATE_DATA) || (state == STATE_BANK_DATA));

    always @(posedge clk) begin
        if (!rst_n) begin
            pending             <= 16'b0;
            stored_format_flat  <= 32'b0;
            stored_payload_flat <= 128'b0;
            stored_raw_flat      <= 128'b0;
            stored_flags_flat   <= 32'b0;
            stored_delta_flat   <= 64'b0;
            row_base_time_flat  <= 64'b0;
            row_base_valid      <= 4'b0;
            state               <= STATE_IDLE;
            selected_row        <= 2'b0;
            snapshot_columns    <= 4'b0;
            remaining_columns   <= 4'b0;
            snapshot_time       <= 16'b0;
            packet_bank_fusion  <= 1'b0;
            bank_snapshot_mask  <= 16'b0;
            bank_snapshot_bin_mask <= 16'b0;
            bank_snapshot_mode  <= FORMAT_RAW8;
            bank_snapshot_count_minus_one <= 4'b0;
            bank_payload_shift  <= 128'b0;
            bank_payload_words_remaining <= 4'b0;
        end else begin
            pending <= pending_after;

            for (capture_tile_index = 0; capture_tile_index < 16;
                 capture_tile_index = capture_tile_index + 1) begin
                if (accept_mask[capture_tile_index]) begin
                    stored_format_flat[capture_tile_index*2 +: 2] <=
                        encoded_format_flat[capture_tile_index*2 +: 2];
                    stored_payload_flat[capture_tile_index*8 +: 8] <=
                        encoded_payload_flat[capture_tile_index*8 +: 8];
                    stored_raw_flat[capture_tile_index*8 +: 8] <= {
                        tile_on_flat[capture_tile_index*4 +: 4],
                        tile_off_flat[capture_tile_index*4 +: 4]
                    };
                    stored_flags_flat[capture_tile_index*2 +: 2] <=
                        encoded_flags_flat[capture_tile_index*2 +: 2];

                    if (EXTERNAL_RX_TIMESTAMP != 0)
                        stored_delta_flat[capture_tile_index*4 +: 4] <= 4'd0;
                    else if (row_base_valid[capture_tile_index/4])
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
                        selected_row <= row_grant_index;
                        snapshot_columns <=
                            pending[row_grant_index*4 +: 4] |
                            accept_mask[row_grant_index*4 +: 4];
                        remaining_columns <=
                            pending[row_grant_index*4 +: 4] |
                            accept_mask[row_grant_index*4 +: 4];
                        snapshot_time <=
                            row_base_time_flat[row_grant_index*16 +: 16];
                        packet_bank_fusion <= bank_candidate_use;
                        bank_snapshot_mask <= bank_candidate_mask;
                        bank_snapshot_bin_mask <= bank_candidate_bin_mask;
                        bank_snapshot_mode <= bank_candidate_mode;
                        bank_snapshot_count_minus_one <=
                            bank_candidate_count_minus_one;
                        bank_payload_shift <= bank_candidate_payload;
                        bank_payload_words_remaining <=
                            bank_candidate_payload_words;

                        if (out_valid && out_ready) begin
                            if (bank_candidate_use)
                                state <= STATE_BANK_MASK;
                            else if (EXTENDED_BANK_ID != 0)
                                state <= STATE_BANK_EXT;
                            else if (EXTERNAL_RX_TIMESTAMP != 0)
                                state <= STATE_DATA;
                            else
                                state <= STATE_TIME;
                        end else begin
                            state <= STATE_HEADER_HOLD;
                        end
                    end
                end
                STATE_HEADER_HOLD: begin
                    if (out_valid && out_ready) begin
                        if (packet_bank_fusion)
                            state <= STATE_BANK_MASK;
                        else if (EXTENDED_BANK_ID != 0)
                            state <= STATE_BANK_EXT;
                        else if (EXTERNAL_RX_TIMESTAMP != 0)
                            state <= STATE_DATA;
                        else
                            state <= STATE_TIME;
                    end
                end
                STATE_BANK_EXT: begin
                    if (out_valid && out_ready) begin
                        if (EXTERNAL_RX_TIMESTAMP != 0)
                            state <= STATE_DATA;
                        else
                            state <= STATE_TIME;
                    end
                end
                STATE_TIME: begin
                    if (out_valid && out_ready)
                        state <= STATE_DATA;
                end
                STATE_DATA: begin
                    if (out_valid && out_ready) begin
                        remaining_columns <=
                            remaining_columns & ~emit_column_mask;
                        if (out_last)
                            state <= STATE_IDLE;
                    end
                end
                STATE_BANK_MASK: begin
                    if (out_valid && out_ready) begin
                        if (bank_snapshot_mode == FORMAT_ROW)
                            state <= STATE_BANK_BINMASK;
                        else
                            state <= STATE_BANK_DATA;
                    end
                end
                STATE_BANK_BINMASK: begin
                    if (out_valid && out_ready)
                        state <= STATE_BANK_DATA;
                end
                STATE_BANK_DATA: begin
                    if (out_valid && out_ready) begin
                        if (out_last) begin
                            bank_payload_words_remaining <= 4'b0;
                            state <= STATE_IDLE;
                        end else begin
                            bank_payload_shift <= bank_payload_shift >> 16;
                            bank_payload_words_remaining <=
                                bank_payload_words_remaining - 1'b1;
                        end
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
