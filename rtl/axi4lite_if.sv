// Single-outstanding-transaction AXI4-Lite interface used by the 8051.
// Addresses are byte addresses; instruction and MOVX data occupy bits [7:0].
interface axi4lite_if (
    input logic clk,
    input logic rst_n
);
    logic        arvalid;
    logic        arready;
    logic [31:0] araddr;
    logic        rready;
    logic        rvalid;
    logic [31:0] rdata;
    logic        awvalid;
    logic        awready;
    logic [31:0] awaddr;
    logic        wvalid;
    logic        wready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        bready;
    logic        bvalid;

    modport master (
        output arvalid, araddr, rready, awvalid, awaddr, wvalid, wdata, wstrb, bready,
        input  arready, rvalid, rdata, awready, wready, bvalid
    );

    modport slave (
        input  arvalid, araddr, rready, awvalid, awaddr, wvalid, wdata, wstrb, bready,
        output arready, rvalid, rdata, awready, wready, bvalid
    );
endinterface
