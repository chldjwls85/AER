`timescale 1ns/1ps

// Pipelined packet engine shared by sixteen banks in one spatial region.
//
// Pipeline boundaries:
//   capture snapshot -> classify tiles -> evaluate packet cost -> serialize
//
// ENABLE_COMPRESSION=0 is the fair RAW reference.  It keeps the same capture,
// two-entry snapshot FIFO, arbitration, pipeline latency, packet width, and
// ready/valid path; only the legal packet choice is restricted to RAW8.
module aer_shared_packet_engine #(
    parameter integer ENABLE_COMPRESSION = 1
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [7:0]    snapshot_bank_id,
    input  wire [15:0]   snapshot_mask,
    input  wire [127:0]  snapshot_raw_flat,
    input  wire          snapshot_valid,
    output wire          snapshot_ready,
    input  wire          congestion_high,
    input  wire          congestion_critical,
    output reg  [15:0]   out_data,
    output reg           out_valid,
    input  wire          out_ready,
    output reg           out_last,
    output wire          busy_debug
);

    localparam [2:0] STATE_IDLE         = 3'd0;
    localparam [2:0] STATE_CLASSIFY     = 3'd1;
    localparam [2:0] STATE_DECIDE       = 3'd2;
    localparam [2:0] STATE_SPARSE       = 3'd3;
    localparam [2:0] STATE_HEADER       = 3'd4;
    localparam [2:0] STATE_MASK         = 3'd5;
    localparam [2:0] STATE_BINMASK      = 3'd6;
    localparam [2:0] STATE_DATA         = 3'd7;

    localparam [1:0] FORMAT_RAW8  = 2'b00;
    localparam [1:0] FORMAT_MIXED = 2'b11;

    reg [2:0]   state;
    reg [7:0]   stored_bank_id;
    reg [15:0]  stored_mask;
    reg [127:0] stored_raw_flat;

    wire [15:0] classifier_bin_mask;
    wire [15:0] classifier_bin_polarity;
    wire [15:0] classifier_lossy_mask;
    wire [15:0] classifier_sparse_mask;
    wire [47:0] classifier_sparse_payload_flat;

    reg [15:0] stored_bin_mask;
    reg [15:0] stored_bin_polarity;
    reg [15:0] stored_lossy_mask;
    reg [15:0] stored_sparse_mask;
    reg [47:0] stored_sparse_payload_flat;

    reg [4:0] active_count;
    reg [4:0] bin_count;
    reg [4:0] raw_count;
    reg [3:0] raw_payload_words;
    reg [7:0] mixed_payload_bits;
    reg [3:0] mixed_payload_words;
    reg [5:0] raw_total_words;
    reg [5:0] mixed_total_words;
    reg [5:0] sparse_total_words;
    reg       all_sparse;
    reg       choose_sparse;
    reg       choose_mixed;
    reg       stored_congestion_high;
    reg       stored_congestion_critical;
    reg [15:0] effective_bin_mask;
    reg [15:0] lossless_bin_mask;
    reg [4:0] lossless_bin_count;
    reg [4:0] lossless_raw_count;
    reg [4:0] lossy_tile_count;
    reg [7:0] lossless_mixed_bits;
    reg [3:0] lossless_mixed_payload_words;
    reg [5:0] lossless_mixed_total_words;
    reg [5:0] best_lossless_total_words;
    reg       allow_lossy_group3;

    reg [1:0] packet_mode;
    reg [3:0] packet_count_minus_one;
    reg [3:0] payload_words_remaining;
    reg [15:0] packet_bin_mask;
    reg [15:0] sparse_remaining;

    reg [3:0] sparse_selected_tile;
    reg       sparse_selected_valid;
    reg [15:0] sparse_remaining_after;

    // Four tiles are appended at a time.  This bounded reservoir avoids the
    // original sixteen-tile variable barrel packer.
    reg [47:0] pack_buffer;
    reg [5:0]  pack_bit_count;
    reg [2:0]  pack_group;
    reg        pack_scan_done;
    reg [31:0] pack_chunk_data;
    reg [5:0]  pack_chunk_bits;
    reg [47:0] pack_buffer_next;
    reg [5:0]  pack_bit_count_next;
    reg [2:0]  pack_group_next;
    reg        pack_scan_done_next;
    reg [47:0] pack_base_buffer;
    reg [5:0]  pack_base_count;
    reg        pack_output_fire;
    reg        pack_append;

    integer tile_index;
    integer pack_lane;
    integer pack_tile;
    integer pack_chunk_index;

    function [4:0] popcount16;
        input [15:0] value;
        integer bit_index;
        begin
            popcount16 = 5'd0;
            for (bit_index = 0; bit_index < 16; bit_index = bit_index + 1)
                popcount16 = popcount16 + value[bit_index];
        end
    endfunction

    genvar classifier_tile;
    generate
        for (classifier_tile = 0; classifier_tile < 16;
             classifier_tile = classifier_tile + 1) begin : gen_classifier
            wire unused_has_event;
            aer_tile_combined_classifier classifier_i (
                .on_bitmap        (stored_raw_flat[classifier_tile*8 + 4 +: 4]),
                .off_bitmap       (stored_raw_flat[classifier_tile*8 +: 4]),
                .has_event        (unused_has_event),
                .bin_candidate    (classifier_bin_mask[classifier_tile]),
                .lossy_candidate  (classifier_lossy_mask[classifier_tile]),
                .bin_polarity     (classifier_bin_polarity[classifier_tile]),
                .sparse_candidate (classifier_sparse_mask[classifier_tile]),
                .sparse_payload   (classifier_sparse_payload_flat[
                                      classifier_tile*3 +: 3])
            );
        end
    endgenerate

    assign snapshot_ready = (state == STATE_IDLE);
    assign busy_debug = (state != STATE_IDLE);

    // Cost evaluation is isolated between CLASSIFY and DECIDE registers.
    always @* begin
        active_count = popcount16(stored_mask);
        lossless_bin_mask = stored_bin_mask & stored_mask &
                            ~stored_lossy_mask;
        lossless_bin_count = popcount16(lossless_bin_mask);
        lossless_raw_count = active_count - lossless_bin_count;
        lossy_tile_count = popcount16(stored_lossy_mask & stored_mask);
        lossless_mixed_bits = {3'b0, lossless_bin_count} +
                              ({3'b0, lossless_raw_count} << 3);
        lossless_mixed_payload_words = lossless_mixed_bits[7:4] +
                                       (|lossless_mixed_bits[3:0]);
        lossless_mixed_total_words = 6'd3 +
                                     lossless_mixed_payload_words;

        // A lossy tile inserts one false event.  Enable GROUP3 only under
        // measured queue pressure and only if every inserted event buys at
        // least one complete 16-bit link word versus the best lossless form.
        effective_bin_mask = stored_bin_mask & stored_mask;
        bin_count = popcount16(effective_bin_mask);
        raw_count = active_count - bin_count;
        mixed_payload_bits = {3'b0, bin_count} +
                             ({3'b0, raw_count} << 3);
        mixed_payload_words = mixed_payload_bits[7:4] +
                              (|mixed_payload_bits[3:0]);
        mixed_total_words = 6'd3 + mixed_payload_words;

        raw_payload_words = (active_count + 1'b1) >> 1;
        raw_total_words = 6'd2 + raw_payload_words;
        if (lossless_mixed_total_words < raw_total_words)
            best_lossless_total_words = lossless_mixed_total_words;
        else
            best_lossless_total_words = raw_total_words;
        allow_lossy_group3 = (lossy_tile_count != 0) &&
            (stored_congestion_critical ||
             (stored_congestion_high &&
              ((mixed_total_words + lossy_tile_count) <=
               best_lossless_total_words)));

        if (!allow_lossy_group3)
            effective_bin_mask = lossless_bin_mask;
        bin_count = popcount16(effective_bin_mask);
        raw_count = active_count - bin_count;
        mixed_payload_bits = {3'b0, bin_count} +
                             ({3'b0, raw_count} << 3);
        mixed_payload_words = mixed_payload_bits[7:4] +
                              (|mixed_payload_bits[3:0]);
        mixed_total_words = 6'd3 + mixed_payload_words;
        sparse_total_words = {1'b0, active_count};
        all_sparse = (active_count != 0) &&
                     ((stored_sparse_mask & stored_mask) == stored_mask);

        choose_sparse = 1'b0;
        choose_mixed = 1'b0;
        if (ENABLE_COMPRESSION != 0) begin
            if (all_sparse && (sparse_total_words < raw_total_words) &&
                (sparse_total_words <= mixed_total_words))
                choose_sparse = 1'b1;
            else if ((active_count > 1) &&
                     (mixed_total_words < raw_total_words))
                choose_mixed = 1'b1;
        end
    end

    always @* begin
        sparse_selected_tile = 4'd0;
        sparse_selected_valid = 1'b0;
        for (tile_index = 0; tile_index < 16; tile_index = tile_index + 1) begin
            if (!sparse_selected_valid && sparse_remaining[tile_index]) begin
                sparse_selected_tile = tile_index[3:0];
                sparse_selected_valid = 1'b1;
            end
        end
        sparse_remaining_after = sparse_remaining;
        if (sparse_selected_valid)
            sparse_remaining_after[sparse_selected_tile] = 1'b0;
    end

    always @* begin
        pack_chunk_data = 32'b0;
        pack_chunk_bits = 6'b0;
        pack_chunk_index = 0;
        pack_tile = 0;
        for (pack_lane = 0; pack_lane < 4; pack_lane = pack_lane + 1) begin
            pack_tile = pack_group * 4 + pack_lane;
            if ((pack_group < 4) && stored_mask[pack_tile]) begin
                if ((packet_mode == FORMAT_MIXED) &&
                    packet_bin_mask[pack_tile]) begin
                    pack_chunk_data[pack_chunk_index] =
                        stored_bin_polarity[pack_tile];
                    pack_chunk_index = pack_chunk_index + 1;
                end else begin
                    pack_chunk_data[pack_chunk_index +: 8] =
                        stored_raw_flat[pack_tile*8 +: 8];
                    pack_chunk_index = pack_chunk_index + 8;
                end
            end
        end
        pack_chunk_bits = pack_chunk_index[5:0];
    end

    always @* begin
        pack_buffer_next = pack_buffer;
        pack_bit_count_next = pack_bit_count;
        pack_group_next = pack_group;
        pack_scan_done_next = pack_scan_done;

        pack_output_fire = (state == STATE_DATA) && out_valid && out_ready;
        pack_base_buffer = pack_buffer;
        pack_base_count = pack_bit_count;
        if (pack_output_fire) begin
            pack_base_buffer = pack_buffer >> 16;
            if (pack_bit_count > 16)
                pack_base_count = pack_bit_count - 16;
            else
                pack_base_count = 0;
            pack_buffer_next = pack_base_buffer;
            pack_bit_count_next = pack_base_count;
        end

        pack_append = ((state == STATE_HEADER) ||
                       (state == STATE_MASK) ||
                       (state == STATE_BINMASK) ||
                       (state == STATE_DATA)) &&
                      !pack_scan_done &&
                      (pack_base_count <= 16) &&
                      !(pack_output_fire && out_last);
        if (pack_append) begin
            pack_buffer_next = pack_base_buffer |
                ({16'b0, pack_chunk_data} << pack_base_count);
            pack_bit_count_next = pack_base_count + pack_chunk_bits;
            pack_group_next = pack_group + 1'b1;
            if (pack_group == 3)
                pack_scan_done_next = 1'b1;
        end
    end

    always @* begin
        out_data = 16'b0;
        out_valid = 1'b0;
        out_last = 1'b0;
        case (state)
            STATE_SPARSE: begin
                out_data = {1'b0, stored_bank_id,
                            sparse_selected_tile,
                            stored_sparse_payload_flat[
                                sparse_selected_tile*3 +: 3]};
                out_valid = sparse_selected_valid;
                // Every SPARSE word is a complete packet.
                out_last = sparse_selected_valid;
            end
            STATE_HEADER: begin
                out_data = {2'b10, stored_bank_id, packet_mode,
                            packet_count_minus_one};
                out_valid = 1'b1;
            end
            STATE_MASK: begin
                out_data = stored_mask;
                out_valid = 1'b1;
            end
            STATE_BINMASK: begin
                out_data = packet_bin_mask;
                out_valid = 1'b1;
            end
            STATE_DATA: begin
                out_data = pack_buffer[15:0];
                out_valid = (payload_words_remaining != 0) &&
                    ((pack_bit_count >= 16) ||
                     (pack_scan_done && (pack_bit_count != 0)));
                out_last = (payload_words_remaining == 1);
            end
            default: begin
                out_data = 16'b0;
                out_valid = 1'b0;
                out_last = 1'b0;
            end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            stored_bank_id <= 8'b0;
            stored_mask <= 16'b0;
            stored_raw_flat <= 128'b0;
            stored_bin_mask <= 16'b0;
            stored_bin_polarity <= 16'b0;
            stored_lossy_mask <= 16'b0;
            stored_sparse_mask <= 16'b0;
            stored_sparse_payload_flat <= 48'b0;
            stored_congestion_high <= 1'b0;
            stored_congestion_critical <= 1'b0;
            packet_mode <= FORMAT_RAW8;
            packet_count_minus_one <= 4'b0;
            payload_words_remaining <= 4'b0;
            packet_bin_mask <= 16'b0;
            sparse_remaining <= 16'b0;
            pack_buffer <= 48'b0;
            pack_bit_count <= 6'b0;
            pack_group <= 3'b0;
            pack_scan_done <= 1'b0;
        end else begin
            pack_buffer <= pack_buffer_next;
            pack_bit_count <= pack_bit_count_next;
            pack_group <= pack_group_next;
            pack_scan_done <= pack_scan_done_next;

            case (state)
                STATE_IDLE: begin
                    if (snapshot_valid && snapshot_ready) begin
                        stored_bank_id <= snapshot_bank_id;
                        stored_mask <= snapshot_mask;
                        stored_raw_flat <= snapshot_raw_flat;
                        stored_congestion_high <= congestion_high;
                        stored_congestion_critical <= congestion_critical;
                        state <= STATE_CLASSIFY;
                    end
                end

                STATE_CLASSIFY: begin
                    stored_bin_mask <= classifier_bin_mask & stored_mask;
                    stored_bin_polarity <= classifier_bin_polarity &
                                           stored_mask;
                    stored_lossy_mask <= classifier_lossy_mask & stored_mask;
                    stored_sparse_mask <= classifier_sparse_mask &
                                          stored_mask;
                    stored_sparse_payload_flat <=
                        classifier_sparse_payload_flat;
                    state <= STATE_DECIDE;
                end

                STATE_DECIDE: begin
                    packet_count_minus_one <= active_count - 1'b1;
                    pack_buffer <= 48'b0;
                    pack_bit_count <= 6'b0;
                    pack_group <= 3'b0;
                    pack_scan_done <= 1'b0;
                    if (choose_sparse) begin
                        sparse_remaining <= stored_mask;
                        state <= STATE_SPARSE;
                    end else begin
                        if (choose_mixed) begin
                            packet_mode <= FORMAT_MIXED;
                            packet_bin_mask <= effective_bin_mask;
                            payload_words_remaining <= mixed_payload_words;
                        end else begin
                            packet_mode <= FORMAT_RAW8;
                            packet_bin_mask <= 16'b0;
                            payload_words_remaining <= raw_payload_words;
                        end
                        state <= STATE_HEADER;
                    end
                end

                STATE_SPARSE: begin
                    if (out_valid && out_ready) begin
                        sparse_remaining <= sparse_remaining_after;
                        if (sparse_remaining_after == 16'b0)
                            state <= STATE_IDLE;
                    end
                end

                STATE_HEADER: begin
                    if (out_valid && out_ready)
                        state <= STATE_MASK;
                end

                STATE_MASK: begin
                    if (out_valid && out_ready) begin
                        if (packet_mode == FORMAT_MIXED)
                            state <= STATE_BINMASK;
                        else
                            state <= STATE_DATA;
                    end
                end

                STATE_BINMASK: begin
                    if (out_valid && out_ready)
                        state <= STATE_DATA;
                end

                STATE_DATA: begin
                    if (out_valid && out_ready) begin
                        if (out_last) begin
                            payload_words_remaining <= 4'b0;
                            state <= STATE_IDLE;
                        end else begin
                            payload_words_remaining <=
                                payload_words_remaining - 1'b1;
                        end
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
