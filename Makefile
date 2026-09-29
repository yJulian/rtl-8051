TOPLEVEL_LANG = verilog
.DEFAULT_GOAL := sim
export CCACHE_DISABLE = 1
export PYTHONPATH := $(PWD)/test:$(PYTHONPATH)
SIM ?= verilator
TOPLEVEL = mcs51_top
MODULE = test_mcs51
VERILOG_SOURCES = $(PWD)/rtl/axi4lite_if.sv $(PWD)/rtl/mcs51_timer.sv $(PWD)/rtl/mcs51_core.sv $(PWD)/rtl/mcs51_top.sv
COMPILE_ARGS += -Wall --trace -Wno-fatal

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: test
test: sim
