IVERILOG = iverilog
VVP = vvp
FLAGS = -g2012 -Wall

SRC = src/top.sv src/fetch.sv src/dispatch.sv src/instruction_memory.sv \
      src/register_file.sv src/alu.sv src/alu_decoder.sv \
      src/lsu.sv src/lsu_decoder.sv src/data_memory.sv \
      src/bru.sv src/bru_decoder.sv src/bru_conexion.sv \
      src/crypto_unit.sv src/feist_decoder.sv src/key_vault.sv \
      src/pipeline_reg.sv src/pipeline_control.sv

.PHONY: all fetch dispatch top tb_top test clean

all: test

fetch:
	$(IVERILOG) $(FLAGS) -s tb_fetch -o sim_fetch tb/tb_fetch.sv src/fetch.sv src/instruction_memory.sv
	$(VVP) sim_fetch

dispatch:
	$(IVERILOG) $(FLAGS) -s tb_dispatch -o sim_dispatch tb/tb_dispatch.sv src/dispatch.sv
	$(VVP) sim_dispatch

top:
	$(IVERILOG) $(FLAGS) -s top -o sim_top $(SRC)

tb_top:
	$(IVERILOG) $(FLAGS) -s tb_top -o sim_tb_top tb/tb_top.sv $(SRC)
	$(VVP) sim_tb_top

test: fetch dispatch tb_top

clean:
	rm -f sim_fetch sim_dispatch sim_top sim_tb_top