import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge


class AxiMemory:
    def __init__(self, dut, program):
        self.dut, self.mem, self.writes = dut, bytearray(65536), []
        self.mem[:len(program)] = bytes(program)

    async def run(self):
        d = self.dut
        d.arready.value = 1; d.awready.value = 1; d.wready.value = 1
        d.rvalid.value = 0; d.bvalid.value = 0
        read_pending = False
        write_addr = None
        bready_seen = False
        while True:
            await FallingEdge(d.clk)
            if not d.rst_n.value:
                # Do not retain transactions issued while the DUT is in reset.
                d.rvalid.value = 0; d.bvalid.value = 0
                read_pending = False; write_addr = None; bready_seen = False
                continue
            # This BFM keeps a read response for exactly one full cycle.  The
            # DUT's RREADY was asserted during that preceding rising edge.
            if d.rvalid.value:
                d.rvalid.value = 0
                read_pending = False
            # Address and response are deliberately separated by a bus phase:
            # the DUT changes from AR to R state on the intervening rising edge.
            if read_pending and not d.rvalid.value:
                d.rvalid.value = 1
            if d.arvalid.value and d.arready.value and not read_pending:
                d.rdata.value = self.mem[int(d.araddr.value) & 0xffff]
                read_pending = True
            if d.awvalid.value and d.awready.value:
                write_addr = int(d.awaddr.value) & 0xffff
            if d.wvalid.value:
                assert write_addr is not None, "AXI write data arrived before address"
                self.mem[write_addr] = int(d.wdata.value) & 0xff
                self.writes.append((write_addr, self.mem[write_addr]))
                d.bvalid.value = 1
                bready_seen = False
            if d.bvalid.value and d.bready.value:
                # bready is asserted one cycle after W; keep BVALID through
                # the following rising edge, when the master's B state samples it.
                if bready_seen:
                    d.bvalid.value = 0
                bready_seen = True


async def boot(dut, program):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    mem = AxiMemory(dut, program)
    cocotb.start_soon(mem.run())
    dut.rst_n.value = 0
    dut.p0_i.value = 0xff; dut.p1_i.value = 0xff
    dut.p2_i.value = 0xff; dut.p3_i.value = 0xff
    dut.int0_n.value = 1; dut.int1_n.value = 1
    dut.t0_i.value = 1; dut.t1_i.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    return mem


@cocotb.test()
async def immediate_and_direct_moves(dut):
    # MOV A,#42; MOV 20,A; CLR A; MOV A,20; loop
    await boot(dut, [0x74, 0x42, 0xf5, 0x20, 0xe4, 0xe5, 0x20, 0x80, 0xfe])
    for _ in range(80): await RisingEdge(dut.clk)
    assert int(dut.debug_acc.value) == 0x42, f"A={int(dut.debug_acc.value):02x} PC={int(dut.debug_pc.value):04x}"


@cocotb.test()
async def movx_write_uses_axi(dut):
    # DPTR is left at zero; MOV A,#A5; MOVX @DPTR,A; loop
    mem = await boot(dut, [0x74, 0xa5, 0xf0, 0x80, 0xfe])
    for _ in range(60): await RisingEdge(dut.clk)
    assert (0, 0xa5) in mem.writes, f"writes={mem.writes}, PC={int(dut.debug_pc.value):04x}"


@cocotb.test()
async def psw_selects_r0_to_r7_register_bank(dut):
    # Bank 0 R0=11, bank 1 R0=22; select bank 0 again and read R0.
    program = [
        0x75, 0xd0, 0x00,  # MOV PSW,#00h (bank 0)
        0x78, 0x11,        # MOV R0,#11h
        0x75, 0xd0, 0x08,  # MOV PSW,#08h (bank 1)
        0x78, 0x22,        # MOV R0,#22h
        0x75, 0xd0, 0x00,  # MOV PSW,#00h (bank 0)
        0xe8,              # MOV A,R0
        0x80, 0xfe,        # loop
    ]
    await boot(dut, program)
    for _ in range(180): await RisingEdge(dut.clk)
    assert int(dut.debug_acc.value) == 0x11, f"A={int(dut.debug_acc.value):02x} PC={int(dut.debug_pc.value):04x}"


@cocotb.test()
async def gpio_ports_are_visible_as_8051_sfrs(dut):
    # MOV P1,#A5; MOV A,P2; loop. P2 reads the external pin, not its latch.
    await boot(dut, [0x75, 0x90, 0xa5, 0xe5, 0xa0, 0x80, 0xfe])
    dut.p2_i.value = 0x3c
    for _ in range(120): await RisingEdge(dut.clk)
    assert int(dut.p1_o.value) == 0xa5
    assert int(dut.p1_oe.value) == 0x5a
    assert int(dut.debug_acc.value) == 0x3c


@cocotb.test()
async def int0_edge_interrupt_vectors_to_0003(dut):
    # Main: IT0=edge; IE=EA|EX0; spin. Vector 0003: MOV A,#5A; RETI.
    program = [
        0x02, 0x00, 0x20,  # LJMP 0020h
        0x74, 0x5a, 0x32,  # 0003: interrupt handler
    ] + [0x00] * 0x1a + [
        0x75, 0x88, 0x01,  # MOV TCON,#IT0
        0x75, 0xa8, 0x81,  # MOV IE,#EA|EX0
        0x80, 0xfe,
    ]
    await boot(dut, program)
    for _ in range(80): await RisingEdge(dut.clk)
    dut.int0_n.value = 0
    for _ in range(8): await RisingEdge(dut.clk)
    dut.int0_n.value = 1
    for _ in range(80): await RisingEdge(dut.clk)
    assert int(dut.debug_acc.value) == 0x5a


@cocotb.test()
async def timer1_interrupt_vectors_to_001b(dut):
    program = bytearray(0x40)
    program[0:3] = bytes([0x02, 0x00, 0x30])      # LJMP 0030h
    program[0x1b:0x1e] = bytes([0x74, 0x66, 0x32])  # T1 ISR: MOV A,#66; RETI
    program[0x30:0x41] = bytes([
        0x75, 0x89, 0x20,  # MOV TMOD,#20h (T1 mode 2)
        0x75, 0x8d, 0xff,  # MOV TH1,#FFh
        0x75, 0x8b, 0xff,  # MOV TL1,#FFh
        0x75, 0x88, 0x40,  # MOV TCON,#TR1
        0x75, 0xa8, 0x88,  # MOV IE,#EA|ET1
        0x80, 0xfe,
    ])
    await boot(dut, program)
    for _ in range(180): await RisingEdge(dut.clk)
    assert int(dut.debug_acc.value) == 0x66
