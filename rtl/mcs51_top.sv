module mcs51_top (
    input logic clk, input logic rst_n,
    output logic arvalid, input logic arready, output logic [31:0] araddr,
    output logic rready, input logic rvalid, input logic [31:0] rdata,
    output logic awvalid, input logic awready, output logic [31:0] awaddr,
    output logic wvalid, input logic wready, output logic [31:0] wdata, output logic [3:0] wstrb,
    output logic bready, input logic bvalid,
    input logic [7:0] p0_i, p1_i, p2_i, p3_i,
    input logic int0_n, int1_n, t0_i, t1_i,
    output logic [7:0] p0_o, p1_o, p2_o, p3_o,
    output logic [7:0] p0_oe, p1_oe, p2_oe, p3_oe,
    output logic [15:0] debug_pc, output logic [7:0] debug_acc,
    output logic [7:0] debug_tcon, output logic [7:0] debug_ie
);
    axi4lite_if axi (.clk, .rst_n);

    assign axi.arready = arready;
    assign axi.rvalid  = rvalid;
    assign axi.rdata   = rdata;
    assign axi.awready = awready;
    assign axi.wready  = wready;
    assign axi.bvalid  = bvalid;
    assign arvalid = axi.arvalid;
    assign araddr  = axi.araddr;
    assign rready  = axi.rready;
    assign awvalid = axi.awvalid;
    assign awaddr  = axi.awaddr;
    assign wvalid  = axi.wvalid;
    assign wdata   = axi.wdata;
    assign wstrb   = axi.wstrb;
    assign bready  = axi.bready;

    mcs51_core u_core (.clk, .rst_n, .axi,
                       .p0_i, .p1_i, .p2_i, .p3_i,
                       .int0_n, .int1_n, .t0_i, .t1_i,
                       .p0_o, .p1_o, .p2_o, .p3_o,
                       .p0_oe, .p1_oe, .p2_oe, .p3_oe,
                       .debug_pc, .debug_acc, .debug_tcon, .debug_ie);
endmodule
