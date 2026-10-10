IVERILOG = iverilog
VVP = vvp
FLAGS = -g2012 -Wall

.PHONY: all fetch dispatch test clean

all: test

fetch:
	$(IVERILOG) $(FLAGS) -s tb_fetch -o sim_fetch tb/tb_fetch.sv src/fetch.sv
	$(VVP) sim_fetch

dispatch:
	$(IVERILOG) $(FLAGS) -s tb_dispatch -o sim_dispatch tb/tb_dispatch.sv src/dispatch.sv
	$(VVP) sim_dispatch

test: fetch dispatch

clean:
	rm -f sim_fetch sim_dispatch
