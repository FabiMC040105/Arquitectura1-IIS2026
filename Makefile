IVERILOG = iverilog
VVP = vvp
FLAGS = -g2012 -Wall

.PHONY: all fetch dispatch top test clean

all: test

fetch:
	$(IVERILOG) $(FLAGS) -s tb_fetch -o sim_fetch tb/tb_fetch.sv src/fetch.sv
	$(VVP) sim_fetch

dispatch:
	$(IVERILOG) $(FLAGS) -s tb_dispatch -o sim_dispatch tb/tb_dispatch.sv src/dispatch.sv
	$(VVP) sim_dispatch

top:
	$(IVERILOG) $(FLAGS) -s tb_top -o sim_top tb/tb_top.sv src/top.sv src/fetch.sv src/dispatch.sv
	$(VVP) sim_top

test: fetch dispatch

clean:
	rm -f sim_fetch sim_dispatch sim_top