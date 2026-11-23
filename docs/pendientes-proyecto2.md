# Matriz de trazabilidad y evidencias del Proyecto II

La siguiente matriz vincula los componentes exigidos en CE4301 con los módulos presentes en el repositorio y con la evidencia disponible.

| Componente | Implementación | Evidencia |
|:---|:---|:---|
| Bundle VLIW de cuatro slots y pipeline | `top.sv`, `pipeline/`, `functional-units/` | `tb_top.sv`, `tb_vliw_cuatro_unidades.sv` |
| Stall de bundle completo por caché | `top.sv`, `pipeline_control.sv` | `tb_cache_stall_pipeline.sv`, `tb_cache_stall_store.sv` |
| Caché L1-D 4 KiB, 2-way, LRU | `cache_l1.sv`, `l1_data_system.sv` | `tb_cache_l1.sv`, `tb_l1_data_system.sv` |
| FIFO de escritura L1→L2 | `l1_write_buffer.sv` | `tb_l1_write_buffer.sv`, `tb_l1_raw_hazard.sv` |
| Caché L2 16 KiB, 4-way, write-back | `cache_l2.sv`, `l2_controller.sv` | `tb_cache_l2.sv`, `tb_l2_controller.sv` |
| Reemplazo, RAW y backpressure | `l2_data_system.sv`, `l2_eviction_buffer.sv` | `tb_l2_replacement.sv`, `tb_l2_raw_stall.sv`, `tb_l2_buffer_full.sv` |
| Memoria 64 KiB y segundo dominio de reloj | `mem_subsystem.sv`, `mem_controller.sv`, `flop_sync.sv` | `tb_mem.sv`, `tb_benchmarks_hw.sv` |
| Contadores de métricas | `performance_counters.sv`, `top.sv` | `tb_metricas.sv`, `hardware.csv` |
| Benchmarks secuencial, aleatorio y stride | `generate_benchmarks.py`, `tb_benchmarks_hw.sv` | Tres filas PASS de `evidencias_rendimiento/hardware.csv` |
| Integración con Compiladores | `assembler.py`, `pruebas-compilador/matriz.mem` | `tb_matriz.sv`, resultados reportados en el informe |

**Interpretación de resultados:** el conjunto guardado corresponde a una sola configuración L1/L2/RAM, no a una comparativa medida de políticas alternativas ni de optimizaciones CE1108 activadas/desactivadas. El AMAT se calcula con latencia nominal del enunciado; el controlador RTL dispone de su propia latencia parametrizada y sincronización entre relojes.

La documentación de diseño y los resultados cuantitativos están reunidos en [informe-final-proyecto2.md](informe-final-proyecto2.md).
