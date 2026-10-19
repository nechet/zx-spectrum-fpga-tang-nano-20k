# Resource estimation for an FPGA port.  Requires yosys.
#   make glue   board logic only (CPU and memories black-boxed)
#   make cpu    the TV80 Z80 core on its own
#   make all    both
YOSYS  ?= yosys
FAMILY ?= gw2a
V      = ../krasnodar48_synth.v lib_sync.v ../lib/i8255.v \
         synth_parts.v counters_sync.v mem_blackbox.v
TV80   = ../third_party/tv80/tv80_reg.v ../third_party/tv80/tv80_alu.v \
         ../third_party/tv80/tv80_mcode.v ../third_party/tv80/tv80_core.v \
         ../third_party/tv80/tv80n.v

lib_sync.v: ../lib/ttl.v ../lib/cmos4000.v mk_synth_lib.py
	python3 mk_synth_lib.py lib_sync.v

glue: lib_sync.v
	$(YOSYS) -p "read_verilog $(V); hierarchy -check -top krasnodar48_synth; \
	  proc; tribuf -logic; opt; synth_gowin -family $(FAMILY) -top krasnodar48_synth; stat"

cpu:
	$(YOSYS) -p "read_verilog $(TV80); hierarchy -check -top tv80n; \
	  synth_gowin -family $(FAMILY) -top tv80n; stat"

all: glue cpu
clean:
	rm -f lib_sync.v
.PHONY: glue cpu all clean
