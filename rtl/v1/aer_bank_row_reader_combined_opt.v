`timescale 1ns/1ps

// Area-oriented fixed-mode bank reader for the submitted CARE-AER policy.
//
// Fixed assumptions:
//   * 16 tiles per bank, four tiles per row
//   * external receive timestamp (no per-tile timestamp/delta storage)
//   * lossless SPARSE + lossy GROUP3/BIN4 + RAW fallback
//   * 8-bit bank identifier
//
// Keeping this core separate from the feature-complete legacy reader lets the
// synthesis tool remove unused formats and timestamp paths by construction.
module aer_bank_row_reader_combined_opt #(
    parameter [15:0] BANK_ID = 16'd0
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

    localparam [2:0] STATE_IDLE         = 3'd0;
    localparam [2:0] STATE_HEADER_HOLD  = 3'd1;
    localparam [2:0] STATE_ROW_DATA     = 3'd2;
    localparam [2:0] STATE_BANK_MASK    = 3'd3;
    localparam [2:0] STATE_BANK_BINMASK = 3'd4;
    localparam [2:0] STATE_BANK_DATA    = 3'd5;

    localparam [1:0] FORMAT_RAW8 = 2'b00;
    localparam [1:0] FORMAT_MIXED = 2'b11;

    // The input classifier produces only the masks required by this mode.
    wire [15:0] encoded_has_event;
    wire [15:0] encoded_bin_candidate;
    wire [15:0] encoded_lossy_candidate;
    wire [15:0] encoded_bin_polarity;
    wire [15:0] encoded_sparse_candidate;
    wire [47:0] encoded_sparse_payload_flat;

    // One RAW8 copy is retained.  Format payloads, flags, deltas, and row base
    // timestamps from the generic reader are deliberately not duplicated.
    reg [15:0]  pending;
    reg [127:0] stored_raw_flat;
    reg [15:0]  stored_bin_mask;
    reg [15:0]  stored_bin_polarity;
    reg [15:0]  stored_sparse_mask;

    reg [15:0] accept_mask;
    reg [15:0] clear_mask;
    reg [15:0] pending_after;

    wire [3:0] row_request;
    wire [3:0] row_grant;
    wire       row_grant_valid;
    wire [1:0] row_grant_index;
    wire       row_advance;

    reg [2:0] state;
    reg [1:0] selected_row;
    reg [3:0] snapshot_columns;
    reg [3:0] remaining_columns;
    reg       packet_bank_fusion;
    reg       packet_sparse;
    reg [3:0] sparse_snapshot_tile;
    reg [2:0] sparse_snapshot_payload;

    reg [15:0] bank_snapshot_mask;
    reg [15:0] bank_snapshot_bin_mask;
    reg [1:0]  bank_snapshot_mode;
    reg [3:0]  bank_snapshot_count_minus_one;
    reg [3:0]  bank_payload_words_remaining;

    // Four fixed tile positions are scanned per cycle.  The reservoir is
    // bounded to 48 bits: at most 32 new bits plus at most 16 retained bits.
    reg [47:0] bank_pack_buffer;
    reg [5:0]  bank_pack_bit_count;
    reg [2:0]  bank_pack_group;
    reg        bank_pack_scan_done;
    reg [31:0] bank_pack_chunk_data;
    reg [5:0]  bank_pack_chunk_bits;
    reg [47:0] bank_pack_buffer_next;
    reg [5:0]  bank_pack_bit_count_next;
    reg [2:0]  bank_pack_group_next;
    reg        bank_pack_scan_done_next;
    reg [47:0] bank_pack_base_buffer;
    reg [5:0]  bank_pack_base_count;
    reg        bank_pack_output_fire;
    reg        bank_pack_append;

    reg [15:0] candidate_mask;
    reg [15:0] candidate_bin_mask;
    reg [15:0] candidate_bin_polarity;
    reg [15:0] candidate_sparse_mask;
    reg [4:0]  active_count;
    reg [4:0]  bin_count;
    reg [4:0]  raw_count;
    reg [2:0]  nonsparse_row_count;
    reg [5:0]  row_cost;
    reg [7:0]  lossy_bits;
    reg [3:0]  raw_payload_words;
    reg [3:0]  lossy_payload_words;
    reg [5:0]  raw_bank_cost;
    reg [5:0]  lossy_bank_cost;
    reg        bank_candidate_use;
    reg [1:0]  bank_candidate_mode;
    reg [3:0]  bank_candidate_count_minus_one;
    reg [3:0]  bank_candidate_payload_words;

    reg        sparse_candidate_use;
    reg        sparse_candidate_found;
    reg [3:0]  sparse_candidate_tile;
    reg [2:0]  sparse_candidate_payload;
    reg [7:0]  sparse_candidate_raw;

    reg [1:0] selected_column;
    reg       selected_column_valid;
    reg [3:0] selected_column_mask;
    reg       selected_column_last;
    reg [3:0] remaining_without_selected;
    reg [7:0] selected_raw;
    reg       selected_conflict;

    integer tile_index;
    integer sparse_column;
    integer sparse_index;
    integer pack_lane;
    integer pack_tile;
    integer pack_chunk_index;
    integer capture_tile;

    // time_now is part of the drop-in interface but is intentionally unused:
    // this fixed core timestamps once at the receiver above the sensor array.
    wire unused_time_now;
    wire unused_lossy_candidate;
    assign unused_time_now = ^time_now;
    assign unused_lossy_candidate = ^encoded_lossy_candidate;

    function [4:0] popcount16;
        input [15:0] value;
        integer bit_index;
        begin
            popcount16 = 5'd0;
            for (bit_index = 0; bit_index < 16; bit_index = bit_index + 1)
                popcount16 = popcount16 + value[bit_index];
        end
    endfunction

    function [2:0] sparse_payload_from_raw8;
        input [7:0] raw8;
        begin
            case (raw8[7:4])
                4'b0001: sparse_payload_from_raw8 = {2'd0, 1'b1};
                4'b0010: sparse_payload_from_raw8 = {2'd1, 1'b1};
                4'b0100: sparse_payload_from_raw8 = {2'd2, 1'b1};
                4'b1000: sparse_payload_from_raw8 = {2'd3, 1'b1};
                default: begin
                    case (raw8[3:0])
                        4'b0001: sparse_payload_from_raw8 = {2'd0, 1'b0};
                        4'b0010: sparse_payload_from_raw8 = {2'd1, 1'b0};
                        4'b0100: sparse_payload_from_raw8 = {2'd2, 1'b0};
                        4'b1000: sparse_payload_from_raw8 = {2'd3, 1'b0};
                        default: sparse_payload_from_raw8 = 3'b000;
                    endcase
                end
            endcase
        end
    endfunction

    genvar classifier_tile;
    generate
        for (classifier_tile = 0; classifier_tile < 16;
             classifier_tile = classifier_tile + 1) begin : gen_classifier
            aer_tile_combined_classifier classifier_i (
                .on_bitmap        (tile_on_flat[classifier_tile*4 +: 4]),
                .off_bitmap       (tile_off_flat[classifier_tile*4 +: 4]),
                .has_event        (encoded_has_event[classifier_tile]),
                .bin_candidate    (encoded_bin_candidate[classifier_tile]),
                .lossy_candidate  (encoded_lossy_candidate[classifier_tile]),
                .bin_polarity     (encoded_bin_polarity[classifier_tile]),
                .sparse_candidate (encoded_sparse_candidate[classifier_tile]),
                .sparse_payload   (encoded_sparse_payload_flat[
                                      classifier_tile*3 +: 3])
            );
        end
    endgenerate

    assign row_request[0] = |pending[3:0];
    assign row_request[1] = |pending[7:4];
    assign row_request[2] = |pending[11:8];
    assign row_request[3] = |pending[15:12];
    assign pending_debug = pending;

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

    // One pending slot per tile.  New data is accepted only when the existing
    // RAW8 snapshot for that tile cannot be overwritten.
    always @* begin
        tile_in_ready = ~pending;
        accept_mask = 16'b0;
        for (tile_index = 0; tile_index < 16; tile_index = tile_index + 1) begin
            accept_mask[tile_index] = tile_in_valid[tile_index] &&
                                      tile_in_ready[tile_index] &&
                                      encoded_has_event[tile_index];
        end
    end

    // Candidate metadata is formed from compact masks.  Exact packet costs
    // use bounded counters rather than 32-bit integer accumulators.
    always @* begin
        candidate_mask = pending | accept_mask;
        candidate_bin_mask = (stored_bin_mask & pending) |
                             (encoded_bin_candidate & accept_mask);
        candidate_bin_polarity = (stored_bin_polarity & pending) |
                                 (encoded_bin_polarity & accept_mask);
        candidate_sparse_mask = (stored_sparse_mask & pending) |
                                (encoded_sparse_candidate & accept_mask);

        active_count = popcount16(candidate_mask);
        bin_count = popcount16(candidate_bin_mask);
        raw_count = active_count - bin_count;

        nonsparse_row_count = 3'd0;
        if (|(candidate_mask[3:0] & ~candidate_sparse_mask[3:0]))
            nonsparse_row_count = nonsparse_row_count + 1'b1;
        if (|(candidate_mask[7:4] & ~candidate_sparse_mask[7:4]))
            nonsparse_row_count = nonsparse_row_count + 1'b1;
        if (|(candidate_mask[11:8] & ~candidate_sparse_mask[11:8]))
            nonsparse_row_count = nonsparse_row_count + 1'b1;
        if (|(candidate_mask[15:12] & ~candidate_sparse_mask[15:12]))
            nonsparse_row_count = nonsparse_row_count + 1'b1;

        // With an external receive timestamp, a row costs one word per active
        // tile plus one header only when the row contains a non-SPARSE tile.
        row_cost = {1'b0, active_count} + nonsparse_row_count;

        raw_payload_words = (active_count + 1'b1) >> 1;
        lossy_bits = {3'b0, bin_count} + ({3'b0, raw_count} << 3);
        lossy_payload_words = lossy_bits[7:4] + (|lossy_bits[3:0]);
        raw_bank_cost = 6'd2 + raw_payload_words;
        lossy_bank_cost = 6'd3 + lossy_payload_words;

        bank_candidate_use = 1'b0;
        bank_candidate_mode = FORMAT_RAW8;
        bank_candidate_payload_words = 4'd0;
        if ((active_count > 1) &&
            (lossy_bank_cost < raw_bank_cost) &&
            (lossy_bank_cost < row_cost)) begin
            bank_candidate_use = 1'b1;
            bank_candidate_mode = FORMAT_MIXED;
            bank_candidate_payload_words = lossy_payload_words;
        end else if ((active_count > 1) &&
                     (raw_bank_cost < row_cost)) begin
            bank_candidate_use = 1'b1;
            bank_candidate_mode = FORMAT_RAW8;
            bank_candidate_payload_words = raw_payload_words;
        end

        bank_candidate_count_minus_one = 4'd0;
        if (active_count != 0)
            bank_candidate_count_minus_one = active_count - 1'b1;

        // First SPARSE tile in the granted row.  It is used only when the bank
        // packet is not cheaper, matching the legacy combined policy.
        sparse_candidate_use = 1'b0;
        sparse_candidate_found = 1'b0;
        sparse_candidate_tile = 4'd0;
        sparse_candidate_payload = 3'd0;
        sparse_candidate_raw = 8'd0;
        sparse_index = 0;
        for (sparse_column = 0; sparse_column < 4;
             sparse_column = sparse_column + 1) begin
            sparse_index = (row_grant_valid ? row_grant_index : 0) * 4 +
                           sparse_column;
            if (!sparse_candidate_found && row_grant_valid &&
                candidate_mask[sparse_index] &&
                candidate_sparse_mask[sparse_index]) begin
                sparse_candidate_found = 1'b1;
                sparse_candidate_tile = sparse_index[3:0];
                if (accept_mask[sparse_index])
                    sparse_candidate_raw = {
                        tile_on_flat[sparse_index*4 +: 4],
                        tile_off_flat[sparse_index*4 +: 4]
                    };
                else
                    sparse_candidate_raw =
                        stored_raw_flat[sparse_index*8 +: 8];
            end
        end
        sparse_candidate_payload =
            sparse_payload_from_raw8(sparse_candidate_raw);
        sparse_candidate_use = sparse_candidate_found &&
                               !bank_candidate_use;
    end

    // Select the next active tile in the already-selected row.
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

        selected_column_mask = 4'b0;
        if (selected_column_valid)
            selected_column_mask[selected_column] = 1'b1;
        remaining_without_selected =
            remaining_columns & ~selected_column_mask;
        selected_column_last = selected_column_valid &&
                               (remaining_without_selected == 4'b0);
        selected_raw = stored_raw_flat[
            (selected_row*4 + selected_column)*8 +: 8];
        selected_conflict = |(selected_raw[7:4] & selected_raw[3:0]);
    end

    // Fixed four-tile scan step used only by the selected bank packet.
    always @* begin
        bank_pack_chunk_data = 32'b0;
        bank_pack_chunk_bits = 6'b0;
        pack_chunk_index = 0;
        pack_tile = 0;

        for (pack_lane = 0; pack_lane < 4; pack_lane = pack_lane + 1) begin
            pack_tile = bank_pack_group * 4 + pack_lane;
            if ((bank_pack_group < 4) && bank_snapshot_mask[pack_tile]) begin
                if ((bank_snapshot_mode == FORMAT_MIXED) &&
                    bank_snapshot_bin_mask[pack_tile]) begin
                    bank_pack_chunk_data[pack_chunk_index] =
                        stored_bin_polarity[pack_tile];
                    pack_chunk_index = pack_chunk_index + 1;
                end else begin
                    bank_pack_chunk_data[pack_chunk_index +: 8] =
                        stored_raw_flat[pack_tile*8 +: 8];
                    pack_chunk_index = pack_chunk_index + 8;
                end
            end
        end
        bank_pack_chunk_bits = pack_chunk_index[5:0];
    end

    always @* begin
        bank_pack_buffer_next = bank_pack_buffer;
        bank_pack_bit_count_next = bank_pack_bit_count;
        bank_pack_group_next = bank_pack_group;
        bank_pack_scan_done_next = bank_pack_scan_done;

        bank_pack_output_fire = (state == STATE_BANK_DATA) &&
                                out_valid && out_ready;
        bank_pack_base_buffer = bank_pack_buffer;
        bank_pack_base_count = bank_pack_bit_count;
        if (bank_pack_output_fire) begin
            bank_pack_base_buffer = bank_pack_buffer >> 16;
            if (bank_pack_bit_count > 16)
                bank_pack_base_count = bank_pack_bit_count - 16;
            else
                bank_pack_base_count = 0;
            bank_pack_buffer_next = bank_pack_base_buffer;
            bank_pack_bit_count_next = bank_pack_base_count;
        end

        bank_pack_append = packet_bank_fusion &&
                           !bank_pack_scan_done &&
                           (state != STATE_IDLE) &&
                           (bank_pack_base_count <= 16) &&
                           !(bank_pack_output_fire && out_last);
        if (bank_pack_append) begin
            bank_pack_buffer_next = bank_pack_base_buffer |
                ({16'b0, bank_pack_chunk_data} << bank_pack_base_count);
            bank_pack_bit_count_next = bank_pack_base_count +
                                       bank_pack_chunk_bits;
            bank_pack_group_next = bank_pack_group + 1'b1;
            if (bank_pack_group == 3)
                bank_pack_scan_done_next = 1'b1;
        end
    end

    always @* begin
        out_data = 16'b0;
        out_valid = 1'b0;
        out_last = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (row_grant_valid) begin
                    if (bank_candidate_use)
                        out_data = {2'b10, BANK_ID[7:0],
                                    bank_candidate_mode,
                                    bank_candidate_count_minus_one};
                    else if (sparse_candidate_use)
                        out_data = {1'b0, BANK_ID[7:0],
                                    sparse_candidate_tile,
                                    sparse_candidate_payload};
                    else
                        out_data = {
                            2'b11,
                            BANK_ID[7:0],
                            row_grant_index,
                            candidate_mask[row_grant_index*4 +: 4]
                        };
                    out_valid = 1'b1;
                    out_last = sparse_candidate_use;
                end
            end

            STATE_HEADER_HOLD: begin
                if (packet_bank_fusion)
                    out_data = {2'b10, BANK_ID[7:0],
                                bank_snapshot_mode,
                                bank_snapshot_count_minus_one};
                else if (packet_sparse)
                    out_data = {1'b0, BANK_ID[7:0],
                                sparse_snapshot_tile,
                                sparse_snapshot_payload};
                else
                    out_data = {2'b11, BANK_ID[7:0], selected_row,
                                snapshot_columns};
                out_valid = 1'b1;
                out_last = packet_sparse;
            end

            STATE_ROW_DATA: begin
                out_data = {
                    FORMAT_RAW8,
                    4'b0,
                    selected_raw,
                    selected_conflict,
                    1'b0
                };
                out_valid = selected_column_valid;
                out_last = selected_column_last;
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
                out_data = bank_pack_buffer[15:0];
                out_valid = (bank_payload_words_remaining != 0) &&
                    ((bank_pack_bit_count >= 16) ||
                     (bank_pack_scan_done && (bank_pack_bit_count != 0)));
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
        if ((state == STATE_IDLE) && sparse_candidate_use &&
            out_valid && out_ready) begin
            clear_mask[sparse_candidate_tile] = 1'b1;
        end else if ((state == STATE_HEADER_HOLD) && packet_sparse &&
                     out_valid && out_ready) begin
            clear_mask[sparse_snapshot_tile] = 1'b1;
        end else if ((state == STATE_ROW_DATA) && out_valid && out_ready) begin
            clear_mask[selected_row*4 + selected_column] = 1'b1;
        end else if ((state == STATE_BANK_DATA) && out_valid && out_ready &&
                     out_last) begin
            clear_mask = bank_snapshot_mask;
        end
        pending_after = (pending | accept_mask) & ~clear_mask;
    end

    assign row_advance = out_valid && out_ready && out_last &&
        ((state == STATE_ROW_DATA) ||
         (state == STATE_BANK_DATA) ||
         ((state == STATE_IDLE) && sparse_candidate_use) ||
         ((state == STATE_HEADER_HOLD) && packet_sparse));

    always @(posedge clk) begin
        if (!rst_n) begin
            pending <= 16'b0;
            stored_raw_flat <= 128'b0;
            stored_bin_mask <= 16'b0;
            stored_bin_polarity <= 16'b0;
            stored_sparse_mask <= 16'b0;
            state <= STATE_IDLE;
            selected_row <= 2'b0;
            snapshot_columns <= 4'b0;
            remaining_columns <= 4'b0;
            packet_bank_fusion <= 1'b0;
            packet_sparse <= 1'b0;
            sparse_snapshot_tile <= 4'b0;
            sparse_snapshot_payload <= 3'b0;
            bank_snapshot_mask <= 16'b0;
            bank_snapshot_bin_mask <= 16'b0;
            bank_snapshot_mode <= FORMAT_RAW8;
            bank_snapshot_count_minus_one <= 4'b0;
            bank_payload_words_remaining <= 4'b0;
            bank_pack_buffer <= 48'b0;
            bank_pack_bit_count <= 6'b0;
            bank_pack_group <= 3'b0;
            bank_pack_scan_done <= 1'b0;
        end else begin
            pending <= pending_after;
            bank_pack_buffer <= bank_pack_buffer_next;
            bank_pack_bit_count <= bank_pack_bit_count_next;
            bank_pack_group <= bank_pack_group_next;
            bank_pack_scan_done <= bank_pack_scan_done_next;

            for (capture_tile = 0; capture_tile < 16;
                 capture_tile = capture_tile + 1) begin
                if (accept_mask[capture_tile]) begin
                    stored_raw_flat[capture_tile*8 +: 8] <= {
                        tile_on_flat[capture_tile*4 +: 4],
                        tile_off_flat[capture_tile*4 +: 4]
                    };
                    stored_bin_mask[capture_tile] <=
                        encoded_bin_candidate[capture_tile];
                    stored_bin_polarity[capture_tile] <=
                        encoded_bin_polarity[capture_tile];
                    stored_sparse_mask[capture_tile] <=
                        encoded_sparse_candidate[capture_tile];
                end
            end

            case (state)
                STATE_IDLE: begin
                    if (row_grant_valid) begin
                        selected_row <= row_grant_index;
                        snapshot_columns <=
                            candidate_mask[row_grant_index*4 +: 4];
                        remaining_columns <=
                            candidate_mask[row_grant_index*4 +: 4];
                        packet_bank_fusion <= bank_candidate_use;
                        packet_sparse <= sparse_candidate_use;
                        sparse_snapshot_tile <= sparse_candidate_tile;
                        sparse_snapshot_payload <= sparse_candidate_payload;

                        if (bank_candidate_use) begin
                            bank_snapshot_mask <= candidate_mask;
                            bank_snapshot_bin_mask <=
                                (bank_candidate_mode == FORMAT_MIXED) ?
                                candidate_bin_mask : 16'b0;
                            bank_snapshot_mode <= bank_candidate_mode;
                            bank_snapshot_count_minus_one <=
                                bank_candidate_count_minus_one;
                            bank_payload_words_remaining <=
                                bank_candidate_payload_words;
                            bank_pack_buffer <= 48'b0;
                            bank_pack_bit_count <= 6'b0;
                            bank_pack_group <= 3'b0;
                            bank_pack_scan_done <= 1'b0;
                        end

                        if (out_valid && out_ready) begin
                            if (bank_candidate_use)
                                state <= STATE_BANK_MASK;
                            else if (sparse_candidate_use)
                                state <= STATE_IDLE;
                            else
                                state <= STATE_ROW_DATA;
                        end else begin
                            state <= STATE_HEADER_HOLD;
                        end
                    end
                end

                STATE_HEADER_HOLD: begin
                    if (out_valid && out_ready) begin
                        if (packet_bank_fusion)
                            state <= STATE_BANK_MASK;
                        else if (packet_sparse)
                            state <= STATE_IDLE;
                        else
                            state <= STATE_ROW_DATA;
                    end
                end

                STATE_ROW_DATA: begin
                    if (out_valid && out_ready) begin
                        remaining_columns <= remaining_without_selected;
                        if (selected_column_last)
                            state <= STATE_IDLE;
                    end
                end

                STATE_BANK_MASK: begin
                    if (out_valid && out_ready) begin
                        if (bank_snapshot_mode == FORMAT_MIXED)
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
