`timescale 1ns/1ps

module tb_aer_rr_arbiter;

    reg        clk;
    reg        rst_n;
    reg  [3:0] request;
    reg        advance;
    wire [3:0] grant;
    wire       grant_valid;
    wire [1:0] grant_index;

    integer errors;
    integer expected_index;
    integer step;
    reg [1:0] stalled_index;

    aer_rr_arbiter #(
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
        request = 4'b0000;
        advance = 1'b0;
        errors = 0;
        expected_index = 0;
        stalled_index = 2'b00;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        request = 4'b1111;
        advance = 1'b0;

        for (step = 0; step < 12; step = step + 1) begin
            @(negedge clk);
            if (!grant_valid || (grant_index !== expected_index[1:0])) begin
                $display("ERROR: round-robin step=%0d expected=%0d got=%0d grant=%b",
                         step, expected_index, grant_index, grant);
                errors = errors + 1;
            end
            advance = 1'b1;
            @(posedge clk);
            #1;
            advance = 1'b0;
            expected_index = (expected_index + 1) % 4;
        end

        @(negedge clk);
        stalled_index = grant_index;
        repeat (4) begin
            @(negedge clk);
            if (!grant_valid || (grant_index !== stalled_index)) begin
                $display("ERROR: grant changed without advance expected=%0d got=%0d",
                         stalled_index, grant_index);
                errors = errors + 1;
            end
        end

        request = 4'b1010;
        #1;
        if (!grant_valid || !grant[grant_index] || !request[grant_index]) begin
            $display("ERROR: sparse request grant is invalid request=%b grant=%b", request, grant);
            errors = errors + 1;
        end

        request = 4'b0000;
        #1;
        if (grant_valid || (grant !== 4'b0000)) begin
            $display("ERROR: grant asserted without a request grant=%b", grant);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("AER_RR_ARBITER_PASS");
        else
            $display("AER_RR_ARBITER_FAIL errors=%0d", errors);

        $finish;
    end

endmodule
