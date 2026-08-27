`timescale 1ns/1ps

module tb_aer_locked_rr_arbiter;

    reg         clk;
    reg         rst_n;
    reg  [3:0]  request;
    reg         advance;
    wire [3:0]  grant;
    wire        grant_valid;
    wire [1:0]  grant_index;

    aer_locked_rr_arbiter #(
        .REQUESTS(4),
        .INDEX_WIDTH(2)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (request),
        .advance     (advance),
        .grant       (grant),
        .grant_valid (grant_valid),
        .grant_index (grant_index)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        request = 4'b0;
        advance = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        request = 4'b0001;

        // The candidate is registered before it becomes a grant.
        @(posedge clk);
        @(negedge clk);
        if (!grant_valid || grant_index != 2'd0 || grant != 4'b0001)
            $fatal(1, "RR_REGISTERED_GRANT_FAIL");

        // A valid gap within a multi-word packet must not release the lock or
        // allow another requester to interleave before advance(last).
        request = 4'b0010;
        repeat (2) begin
            @(posedge clk);
            @(negedge clk);
            if (!grant_valid || grant_index != 2'd0 || grant != 4'b0001)
                $fatal(1, "RR_PACKET_GAP_LOCK_FAIL");
        end

        request = 4'b0011;
        advance = 1'b1;
        @(posedge clk);
        @(negedge clk);
        advance = 1'b0;
        request = 4'b0010;

        // One selection cycle later, requester 1 receives the next packet.
        @(posedge clk);
        @(negedge clk);
        if (!grant_valid || grant_index != 2'd1 || grant != 4'b0010)
            $fatal(1, "RR_NEXT_PACKET_FAIL");

        $display("AER_LOCKED_RR_ARBITER_PASS registered_grant=1 packet_gap_lock=1");
        $finish;
    end

endmodule
