IVERILOG = iverilog
VVP = vvp
FLAGS = -g2012 -Wall

SRC = src/top.sv \
      src/register_file.sv \
	  src/performance_counters.sv \
      src/functional-units/alu.sv \
      src/functional-units/alu_decoder.sv \
      src/functional-units/lsu.sv \
      src/functional-units/lsu_decoder.sv \
      src/functional-units/bru.sv \
      src/functional-units/bru_decoder.sv \
      src/functional-units/crypto_unit.sv \
      src/functional-units/feist_decoder.sv \
      src/functional-units/key_vault.sv \
      src/pipeline/pipeline_reg.sv \
      src/pipeline/pipeline_control.sv \
	  src/pipeline/fetch.sv \
      src/pipeline/dispatch.sv \
	  src/memory/instruction_memory.sv \
	  src/memory/data_memory.sv \
      src/memory/l1_data_system.sv \
      src/memory/cache_l1.sv \
      src/memory/l1_write_buffer.sv \
      src/memory/l1_miss_controller.sv \
      src/memory/l2_data_system.sv \
      src/memory/l2_controller.sv \
      src/memory/cache_l2.sv \
      src/memory/l2_eviction_buffer.sv \
      src/memory/l2_mem_bridge.sv \
      src/memory/mem_subsystem.sv \
      src/memory/mem_controller.sv \
      src/memory/flop_sync.sv

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

mem:
	$(IVERILOG) $(FLAGS) -o sim src/flop_sync.sv src/mem_controller.sv src/mem_subsystem.sv tb/tb_mem.sv && \
	$(VVP) sim

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