IVERILOG = iverilog
VVP = vvp
FLAGS = -g2012 -Wall

SRC = src/top.sv \
      src/fetch.sv \
      src/dispatch.sv \
      src/instruction_memory.sv \
      src/register_file.sv \
      src/alu.sv \
      src/alu_decoder.sv \
      src/lsu.sv \
      src/lsu_decoder.sv \
      src/data_memory.sv \
      src/bru.sv \
      src/bru_decoder.sv \
      src/crypto_unit.sv \
      src/feist_decoder.sv \
      src/key_vault.sv \
      src/pipeline_reg.sv \
      src/pipeline_control.sv

.PHONY: all check check-modules fetch dispatch top tb_top test clean

all: test

# Comprueba que todos los modulos puedan elaborarse.
check: check-modules

check-modules:
	@set -e; \
	for module in top fetch instruction_memory dispatch \
	              register_file alu alu_decoder \
	              lsu lsu_decoder data_memory \
	              bru bru_decoder \
	              crypto_unit feist_decoder key_vault \
	              pipeline_reg pipeline_control; do \
	    echo ""; \
	    echo "=== Comprobando $$module ==="; \
	    $(IVERILOG) $(FLAGS) -s $$module -tnull $(SRC); \
	done
	@echo ""
	@echo "Todos los modulos compilaron correctamente."

# Ejecuta el testbench de Fetch.
fetch:
	$(IVERILOG) $(FLAGS) -s tb_fetch -o sim_fetch \
	    tb/tb_fetch.sv src/fetch.sv src/instruction_memory.sv
	$(VVP) sim_fetch

# Ejecuta el testbench de Dispatch.
dispatch:
	$(IVERILOG) $(FLAGS) -s tb_dispatch -o sim_dispatch \
	    tb/tb_dispatch.sv src/dispatch.sv
	$(VVP) sim_dispatch

# Comprueba que top y sus dependencias compilen.
top:
	$(IVERILOG) $(FLAGS) -s top -tnull $(SRC)

# Ejecuta el procesador con un programa arbitrario del compilador.
#   make run PROGRAM=salida_compilador.mem DATA=mis_datos.mem
PROGRAM ?= program_test.mem
DATA    ?= input.mem

run:
	@mkdir -p build
	$(IVERILOG) $(FLAGS) -s tb_run -o sim_run \
	    -DPROGRAM_FILE=\"$(PROGRAM)\" -DDATA_FILE=\"$(DATA)\" \
	    tb/tb_run.sv $(SRC)
	$(VVP) sim_run

# Ejecuta el testbench de integración.
tb_top:
	$(IVERILOG) $(FLAGS) -s tb_top -o sim_tb_top \
	    tb/tb_top.sv $(SRC)
	$(VVP) sim_tb_top

feistel:
	$(IVERILOG) $(FLAGS) -s tb_feistel -o sim_feistel tb/tb_feistel.sv $(SRC)
	$(VVP) sim_feistel

test: fetch dispatch tb_top feistel

# Elimina los ejecutables de simulación.
clean:
	rm -f sim_fetch sim_dispatch sim_top sim_tb_top sim_feistel