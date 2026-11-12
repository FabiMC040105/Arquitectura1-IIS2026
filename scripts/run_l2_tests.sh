#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
l2_src=(src/cache_l2.sv src/l2_controller.sv src/l2_eviction_buffer.sv src/l2_data_system.sv)
l1_src=(src/cache_l1.sv src/l1_data_system.sv src/l1_miss_controller.sv src/l1_write_buffer.sv)
for tb in tb_cache_l2 tb_l2_controller tb_l2_eviction_buffer tb_l2_replacement tb_l2_data_system tb_l2_raw_stall tb_l2_latency tb_l2_buffer_full tb_l1_l2_integration; do
  echo "================== $tb =================="
  if [[ "$tb" == tb_l1_l2_integration ]]; then
    iverilog -g2012 -s "$tb" -o "build/${tb}.vvp" "${l1_src[@]}" "${l2_src[@]}" "tb/${tb}.sv"
  else
    iverilog -g2012 -s "$tb" -o "build/${tb}.vvp" "${l2_src[@]}" "tb/${tb}.sv"
  fi
  vvp "build/${tb}.vvp"
done
