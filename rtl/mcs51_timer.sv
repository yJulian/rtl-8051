module mcs51_timer (
    input  logic       clk, rst_n,
    input  logic       tick_en,
    input  logic [1:0] mode,
    input  logic       gate, counter_mode, tr, int_gate_i, count_i,
    input  logic       tf_clear,
    input  logic [7:0] th_write, input logic th_we,
    input  logic [7:0] tl_write, input logic tl_we,
    output logic [7:0] th, tl,
    output logic       tf
);
    logic count_i_q;
    logic enabled, count_tick;
    logic [12:0] next13;
    logic [15:0] next16;

    always_comb begin
        enabled = tr && (!gate || int_gate_i);
        // The classic counter input increments on a high-to-low transition.
        count_tick = counter_mode ? (count_i_q && !count_i) : tick_en;
        next13 = {th, tl[4:0]} + 13'd1;
        next16 = {th, tl} + 16'd1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            th <= 0; tl <= 0; tf <= 0; count_i_q <= 1'b1;
        end else begin
            count_i_q <= count_i;
            if (th_we) th <= th_write;
            if (tl_we) tl <= tl_write;
            if (tf_clear) tf <= 1'b0;
            if (enabled && count_tick) begin
                case (mode)
                    2'd0: begin
                        {th, tl[4:0]} <= next13;
                        if (next13 == 13'd0) tf <= 1'b1;
                    end
                    2'd1: begin
                        {th, tl} <= next16;
                        if (next16 == 16'd0) tf <= 1'b1;
                    end
                    2'd2: begin
                        if (tl == 8'hff) begin tl <= th; tf <= 1'b1; end
                        else tl <= tl + 1'b1;
                    end
                    default: ; // Timer 0 split mode is intentionally deferred.
                endcase
            end
        end
    end
endmodule
