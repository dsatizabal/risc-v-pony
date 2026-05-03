`default_nettype none

module timer (
    input  wire        clk,
    input  wire        rst_n,
    output reg  [31:0] timer_value
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_value <= 32'd0;
        end else begin
            timer_value <= timer_value + 32'd1;
        end
    end

endmodule
