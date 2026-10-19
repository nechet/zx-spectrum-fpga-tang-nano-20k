# The board netlist, rewritten for synthesis:  make   (or: make gen/krasnodar48_synth.v)
#
# ../Krasnodar-48-fpga generates the board's Verilog netlist from the EasyEDA
# schematic.  The board's shared data bus has five drivers per bit, which
# synthesis cannot resolve, so bus_resolve.py rewrites it into explicit logic
# and swaps in the FPGA memories (fpga_memory.v).  The result is gen/, which
# is committed: the builds and testbenches use it as it is, and only a change
# to the schematic conversion or to the part models needs this rule again.
# The testbench scripts run it too; it does nothing while gen/ is up to date.
KR  = ../Krasnodar-48-fpga/Verilog
SYN = $(KR)/synth

GEN = gen/krasnodar48_synth.v gen/fpga_memory.v gen/lib_sync.v \
      gen/i8255.v gen/z80_chip.v

all: $(GEN)

$(SYN)/lib_sync.v: $(KR)/lib/ttl.v $(KR)/lib/cmos4000.v $(SYN)/mk_synth_lib.py $(SYN)/sync_overrides.v
	cd $(SYN) && python3 mk_synth_lib.py lib_sync.v

$(GEN): $(KR)/krasnodar48_synth.v fpga_memory.v $(SYN)/lib_sync.v \
        $(SYN)/i8255.v $(SYN)/z80_chip.v ../Krasnodar-48-fpga/Tools/bus_resolve.py
	python3 ../Krasnodar-48-fpga/Tools/bus_resolve.py $(KR)/krasnodar48_synth.v -o gen \
	    --relax-z fpga_memory.v --relax-z $(SYN)/lib_sync.v \
	    --relax-z $(SYN)/i8255.v --relax-z $(SYN)/z80_chip.v \
	    --lib $(SYN)/counters_sync.v --lib $(SYN)/synth_parts.v \
	    --sys-clock clk_sys --model-input rom_bank \
	    --export A8 --export A9 --export A10 --export A11 \
	    --export A12 --export A13 --export A14 --export A15 \
	    $(foreach p,A B C,$(foreach b,0 1 2 3 4 5 6 7,--connector P$(p)$(b)))

.PHONY: all
