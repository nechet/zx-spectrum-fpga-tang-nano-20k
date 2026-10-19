# Krasnodar-48 -- Verilog simulation
#
#   make sim     build with Icarus Verilog
#   make run     run the smoke test
#   make wave    run and write tb_krasnodar48.vcd

IVERILOG ?= iverilog
VVP      ?= vvp
SRC       = krasnodar48.v lib/ttl.v lib/cmos4000.v lib/i8255.v lib/memory.v \
            lib/analog.v lib/z80_chip.v third_party/tv80/tv80n.v \
            third_party/tv80/tv80_core.v third_party/tv80/tv80_alu.v \
            third_party/tv80/tv80_mcode.v third_party/tv80/tv80_reg.v
TB        = tb/tb_krasnodar48.v
ROM      ?= tb/rom_test.hex

sim: $(SRC) $(TB)
	$(IVERILOG) -g2005 -Wall -o sim $(TB) $(SRC)

run: sim
	$(VVP) sim +ROMFILE=$(ROM)

wave: sim
	$(VVP) sim +ROMFILE=$(ROM) +VCD

# regenerate the netlist from the EasyEDA source
krasnodar48.v: ../../Krasnodar-48/Sources/Schematic_Krasnodar-48_v1.0.1.json \
               ../Tools/easyeda_to_verilog.py ../Tools/easyeda_netlist.py
	PYTHONPATH=../Tools python3 ../Tools/easyeda_to_verilog.py $< $@

clean:
	rm -f sim tb_krasnodar48.vcd

.PHONY: run wave clean
