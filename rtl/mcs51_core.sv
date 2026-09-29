module mcs51_core (
    input  logic        clk, rst_n,
    axi4lite_if.master  axi,
    input  logic [7:0]  p0_i, p1_i, p2_i, p3_i,
    input  logic        int0_n, int1_n, t0_i, t1_i,
    output logic [7:0]  p0_o, p1_o, p2_o, p3_o,
    output logic [7:0]  p0_oe, p1_oe, p2_oe, p3_oe,
    output logic [15:0] debug_pc,
    output logic [7:0]  debug_acc,
    output logic [7:0]  debug_tcon,
    output logic [7:0]  debug_ie
);
    typedef enum logic [3:0] {FETCH_AR, FETCH_R, EXEC, MOVX_R_AR, MOVX_R_R,
                              MOVX_W_AW, MOVX_W_W, MOVX_W_B} state_t;
    state_t state;
    logic [15:0] pc;
    logic [7:0] acc, dpl, dph, psw, sp, ir, operand;
    logic [7:0] iram [0:127];
    logic [7:0] tcon, tmod, ie, ip;
    logic [7:0] p0_latch, p1_latch, p2_latch, p3_latch;
    logic [7:0] th0, tl0, th1, tl1;
    logic operand_pending, second_byte_pending;
    logic [7:0] direct_addr;
    logic timer_tf0, timer_tf1, timer_tf0_clear, timer_tf1_clear;
    logic th0_we, tl0_we, th1_we, tl1_we;
    logic [7:0] th0_wdata, tl0_wdata, th1_wdata, tl1_wdata;
    logic int0_q, int1_q, ie0_flag, ie1_flag, ie0_clear, ie1_clear;
    logic [15:0] irq_vector;
    logic [1:0] irq_prio, active_prio, irq_depth;
    logic [1:0] prio_stack [0:1];
    logic irq_take;
    logic [3:0] irq_req;

    assign debug_pc = pc;
    assign debug_acc = acc;
    assign debug_tcon = {timer_tf1, tcon[6], timer_tf0, tcon[4], ie1_flag, tcon[2], ie0_flag, tcon[0]};
    assign debug_ie = ie;
    // P0 is open drain; P1--P3 are quasi-bidirectional. A zero in a port
    // latch drives low; a one releases the pin so the input can be sampled.
    assign p0_o = p0_latch; assign p1_o = p1_latch;
    assign p2_o = p2_latch; assign p3_o = p3_latch;
    assign p0_oe = ~p0_latch; assign p1_oe = ~p1_latch;
    assign p2_oe = ~p2_latch; assign p3_oe = ~p3_latch;
    assign axi.araddr = (state == MOVX_R_AR) ? {16'h0, dph, dpl} : {16'h0, pc};
    assign axi.arvalid = (state == FETCH_AR) || (state == MOVX_R_AR);
    assign axi.rready = (state == FETCH_R) || (state == MOVX_R_R);
    assign axi.awaddr = {16'h0, dph, dpl};
    assign axi.awvalid = state == MOVX_W_AW;
    assign axi.wvalid = state == MOVX_W_W;
    assign axi.wdata = {24'h0, acc};
    assign axi.wstrb = 4'b0001;
    assign axi.bready = state == MOVX_W_B;

    mcs51_timer timer0 (
        .clk, .rst_n, .tick_en(1'b1), .mode(tmod[1:0]), .gate(tmod[3]),
        .counter_mode(tmod[2]), .tr(tcon[4]), .int_gate_i(int0_n), .count_i(t0_i),
        .tf_clear(timer_tf0_clear), .th_write(th0_wdata), .th_we(th0_we),
        .tl_write(tl0_wdata), .tl_we(tl0_we), .th(th0), .tl(tl0), .tf(timer_tf0)
    );
    mcs51_timer timer1 (
        .clk, .rst_n, .tick_en(1'b1), .mode(tmod[5:4]), .gate(tmod[7]),
        .counter_mode(tmod[6]), .tr(tcon[6]), .int_gate_i(int1_n), .count_i(t1_i),
        .tf_clear(timer_tf1_clear), .th_write(th1_wdata), .th_we(th1_we),
        .tl_write(tl1_wdata), .tl_we(tl1_we), .th(th1), .tl(tl1), .tf(timer_tf1)
    );

    // Classic priority: EX0, T0, EX1, T1. A high-priority source can
    // pre-empt a low-priority ISR; equal and lower priorities cannot.
    always_comb begin
        irq_req[0] = ie[0] && (tcon[0] ? ie0_flag : !int0_n);
        irq_req[1] = ie[1] && timer_tf0;
        irq_req[2] = ie[2] && (tcon[2] ? ie1_flag : !int1_n);
        irq_req[3] = ie[3] && timer_tf1;
        irq_take = 1'b0; irq_vector = 16'h0000; irq_prio = 2'd0;
        if (ie[7] && active_prio < 2'd2) begin
            if (irq_req[0] && ip[0]) begin irq_take = 1; irq_vector = 16'h0003; irq_prio = 2'd2; end
            else if (irq_req[1] && ip[1]) begin irq_take = 1; irq_vector = 16'h000b; irq_prio = 2'd2; end
            else if (irq_req[2] && ip[2]) begin irq_take = 1; irq_vector = 16'h0013; irq_prio = 2'd2; end
            else if (irq_req[3] && ip[3]) begin irq_take = 1; irq_vector = 16'h001b; irq_prio = 2'd2; end
        end
        if (ie[7] && !irq_take && active_prio == 2'd0) begin
            if (irq_req[0]) begin irq_take = 1; irq_vector = 16'h0003; irq_prio = 2'd1; end
            else if (irq_req[1]) begin irq_take = 1; irq_vector = 16'h000b; irq_prio = 2'd1; end
            else if (irq_req[2]) begin irq_take = 1; irq_vector = 16'h0013; irq_prio = 2'd1; end
            else if (irq_req[3]) begin irq_take = 1; irq_vector = 16'h001b; irq_prio = 2'd1; end
        end
    end

    function automatic logic [7:0] read_direct(input logic [7:0] a);
        if (a < 8'h80) read_direct = iram[a[6:0]];
        else case (a)
            8'h80: read_direct = p0_i;
            8'h81: read_direct = sp;
            8'h82: read_direct = dpl;
            8'h83: read_direct = dph;
            8'h88: read_direct = {timer_tf1, tcon[6], timer_tf0, tcon[4], ie1_flag, tcon[2], ie0_flag, tcon[0]};
            8'h89: read_direct = tmod;
            8'h8a: read_direct = tl0;
            8'h8b: read_direct = tl1;
            8'h8c: read_direct = th0;
            8'h8d: read_direct = th1;
            8'h90: read_direct = p1_i;
            8'ha0: read_direct = p2_i;
            8'hb0: read_direct = p3_i;
            8'hd0: read_direct = psw;
            8'he0: read_direct = acc;
            8'ha8: read_direct = ie;
            8'hb8: read_direct = ip;
            default: read_direct = 8'h00;
        endcase
    endfunction

    // R0..R7 are aliases onto one of four physical 8-byte regions in the
    // lower internal RAM.  Direct accesses to 00h..1fh do not bank-switch.
    function automatic logic [6:0] reg_addr(input logic [2:0] reg_num);
        reg_addr = {2'b00, psw[4:3], reg_num};
    endfunction

    task automatic write_direct(input logic [7:0] a, input logic [7:0] d);
        if (a < 8'h80) iram[a[6:0]] <= d;
        else case (a)
            8'h80: p0_latch <= d;
            8'h82: dpl <= d;
            8'h83: dph <= d;
            8'h81: sp <= d;
            8'h88: begin
                tcon <= {1'b0, d[6], 1'b0, d[4], 1'b0, d[2], 1'b0, d[0]};
                timer_tf1_clear <= !d[7]; timer_tf0_clear <= !d[5];
                ie1_clear <= !d[3]; ie0_clear <= !d[1];
            end
            8'h89: tmod <= d;
            8'h8a: begin tl0_wdata <= d; tl0_we <= 1'b1; end
            8'h8b: begin tl1_wdata <= d; tl1_we <= 1'b1; end
            8'h8c: begin th0_wdata <= d; th0_we <= 1'b1; end
            8'h8d: begin th1_wdata <= d; th1_we <= 1'b1; end
            8'h90: p1_latch <= d;
            8'ha0: p2_latch <= d;
            8'hb0: p3_latch <= d;
            8'hd0: psw <= d;
            8'he0: acc <= d;
            8'ha8: ie <= d;
            8'hb8: ip <= d;
            default: ;
        endcase
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= FETCH_AR; pc <= 0; acc <= 0; dpl <= 0; dph <= 0; psw <= 0; sp <= 8'h07;
            tcon <= 0; tmod <= 0; ie <= 0; ip <= 0; ir <= 0; operand <= 0;
            p0_latch <= 8'hff; p1_latch <= 8'hff; p2_latch <= 8'hff; p3_latch <= 8'hff;
            operand_pending <= 0; second_byte_pending <= 0;
            active_prio <= 0; irq_depth <= 0; prio_stack[0] <= 0; prio_stack[1] <= 0;
            int0_q <= 1; int1_q <= 1;
            ie0_flag <= 0; ie1_flag <= 0;
            timer_tf0_clear <= 0; timer_tf1_clear <= 0; ie0_clear <= 0; ie1_clear <= 0;
            th0_we <= 0; tl0_we <= 0; th1_we <= 0; tl1_we <= 0;
            th0_wdata <= 0; tl0_wdata <= 0; th1_wdata <= 0; tl1_wdata <= 0;
        end else begin
            timer_tf0_clear <= 0; timer_tf1_clear <= 0; ie0_clear <= 0; ie1_clear <= 0;
            th0_we <= 0; tl0_we <= 0; th1_we <= 0; tl1_we <= 0;
            int0_q <= int0_n; int1_q <= int1_n;
            if (tcon[0] && int0_q && !int0_n) ie0_flag <= 1'b1;
            if (tcon[2] && int1_q && !int1_n) ie1_flag <= 1'b1;
            if (ie0_clear) ie0_flag <= 1'b0;
            if (ie1_clear) ie1_flag <= 1'b0;
            case (state)
                FETCH_AR: if (axi.arready) state <= FETCH_R;
                FETCH_R: if (axi.rvalid) begin
                    pc <= pc + 1'b1;
                    if (operand_pending) begin
                        operand <= axi.rdata[7:0]; operand_pending <= 0; state <= EXEC;
                    end else begin
                        ir <= axi.rdata[7:0];
                        case (axi.rdata[7:0])
                            8'h74, 8'h75, 8'h80, 8'h02, 8'he5, 8'hf5,
                            8'h78, 8'h79, 8'h7a, 8'h7b, 8'h7c, 8'h7d, 8'h7e, 8'h7f:
                                begin operand_pending <= 1; state <= FETCH_AR; end
                            default: state <= EXEC;
                        endcase
                    end
                end
                EXEC: begin
                    if (irq_take) begin
                        iram[sp[6:0] + 7'd1] <= pc[7:0];
                        iram[sp[6:0] + 7'd2] <= pc[15:8];
                        sp <= sp + 8'd2; pc <= irq_vector;
                        prio_stack[irq_depth[0]] <= active_prio;
                        irq_depth <= irq_depth + 1'b1; active_prio <= irq_prio;
                        if (irq_vector == 16'h0003 && tcon[0]) ie0_flag <= 0;
                        if (irq_vector == 16'h0013 && tcon[2]) ie1_flag <= 0;
                        if (irq_vector == 16'h000b) timer_tf0_clear <= 1'b1;
                        if (irq_vector == 16'h001b) timer_tf1_clear <= 1'b1;
                        state <= FETCH_AR;
                    end else begin
                        case (ir)
                            8'h00: state <= FETCH_AR;
                            8'h04: begin acc <= acc + 1'b1; state <= FETCH_AR; end
                            8'he4: begin acc <= 0; state <= FETCH_AR; end
                            8'h74: begin acc <= operand; state <= FETCH_AR; end
                            8'h78: begin iram[reg_addr(3'd0)] <= operand; state <= FETCH_AR; end
                            8'h79: begin iram[reg_addr(3'd1)] <= operand; state <= FETCH_AR; end
                            8'h7a: begin iram[reg_addr(3'd2)] <= operand; state <= FETCH_AR; end
                            8'h7b: begin iram[reg_addr(3'd3)] <= operand; state <= FETCH_AR; end
                            8'h7c: begin iram[reg_addr(3'd4)] <= operand; state <= FETCH_AR; end
                            8'h7d: begin iram[reg_addr(3'd5)] <= operand; state <= FETCH_AR; end
                            8'h7e: begin iram[reg_addr(3'd6)] <= operand; state <= FETCH_AR; end
                            8'h7f: begin iram[reg_addr(3'd7)] <= operand; state <= FETCH_AR; end
                            8'he5: begin acc <= read_direct(operand); state <= FETCH_AR; end
                            8'he8: begin acc <= iram[reg_addr(3'd0)]; state <= FETCH_AR; end
                            8'he9: begin acc <= iram[reg_addr(3'd1)]; state <= FETCH_AR; end
                            8'hea: begin acc <= iram[reg_addr(3'd2)]; state <= FETCH_AR; end
                            8'heb: begin acc <= iram[reg_addr(3'd3)]; state <= FETCH_AR; end
                            8'hec: begin acc <= iram[reg_addr(3'd4)]; state <= FETCH_AR; end
                            8'hed: begin acc <= iram[reg_addr(3'd5)]; state <= FETCH_AR; end
                            8'hee: begin acc <= iram[reg_addr(3'd6)]; state <= FETCH_AR; end
                            8'hef: begin acc <= iram[reg_addr(3'd7)]; state <= FETCH_AR; end
                            8'hf5: begin write_direct(operand, acc); state <= FETCH_AR; end
                            8'hf8: begin iram[reg_addr(3'd0)] <= acc; state <= FETCH_AR; end
                            8'hf9: begin iram[reg_addr(3'd1)] <= acc; state <= FETCH_AR; end
                            8'hfa: begin iram[reg_addr(3'd2)] <= acc; state <= FETCH_AR; end
                            8'hfb: begin iram[reg_addr(3'd3)] <= acc; state <= FETCH_AR; end
                            8'hfc: begin iram[reg_addr(3'd4)] <= acc; state <= FETCH_AR; end
                            8'hfd: begin iram[reg_addr(3'd5)] <= acc; state <= FETCH_AR; end
                            8'hfe: begin iram[reg_addr(3'd6)] <= acc; state <= FETCH_AR; end
                            8'hff: begin iram[reg_addr(3'd7)] <= acc; state <= FETCH_AR; end
                            8'h75: begin
                                if (second_byte_pending) begin
                                    write_direct(direct_addr, operand);
                                    second_byte_pending <= 0;
                                    state <= FETCH_AR;
                                end else begin
                                    direct_addr <= operand;
                                    second_byte_pending <= 1;
                                    operand_pending <= 1;
                                    state <= FETCH_AR;
                                end
                            end
                            8'h80: begin pc <= pc + {{8{operand[7]}}, operand}; state <= FETCH_AR; end
                            8'h02: begin
                                if (second_byte_pending) begin
                                    pc <= {direct_addr, operand};
                                    second_byte_pending <= 0;
                                    state <= FETCH_AR;
                                end else begin
                                    direct_addr <= operand;
                                    second_byte_pending <= 1;
                                    operand_pending <= 1;
                                    state <= FETCH_AR;
                                end
                            end
                            8'he0: state <= MOVX_R_AR;
                            8'hf0: state <= MOVX_W_AW;
                            8'h32: begin
                                pc <= {iram[sp[6:0]], iram[sp[6:0] - 7'd1]};
                                sp <= sp - 8'd2;
                                active_prio <= prio_stack[(irq_depth == 2'd2) ? 1'b1 : 1'b0];
                                irq_depth <= irq_depth - 1'b1;
                                state <= FETCH_AR;
                            end
                            default: state <= FETCH_AR;
                        endcase
                    end
                end
                MOVX_R_AR: if (axi.arready) state <= MOVX_R_R;
                MOVX_R_R: if (axi.rvalid) begin acc <= axi.rdata[7:0]; state <= FETCH_AR; end
                MOVX_W_AW: if (axi.awready) state <= MOVX_W_W;
                MOVX_W_W: if (axi.wready) state <= MOVX_W_B;
                MOVX_W_B: if (axi.bvalid) state <= FETCH_AR;
                default: state <= FETCH_AR;
            endcase
        end
    end
endmodule
