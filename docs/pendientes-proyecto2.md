# Estado, limitaciones y pendientes antes de defensa

Este archivo evita que una función mencionada en el enunciado sea presentada como validada sin una prueba concreta. Se elaboró leyendo los módulos del ZIP `feature-integracion-metricas-final`, la documentación que lo acompaña y el enunciado conjunto de Proyecto II. **No es una lista de fallos confirmados de ejecución**: distingue observaciones directas, verificaciones y trabajo pendiente.

## 1. Situación observada

| Tema | Evidencia disponible | Estado documental |
| --- | --- | --- |
| ISA VLIW | `top.sv`, decodificadores, `docs/isa.md`, `assembler.py` | Se mantiene el bundle 128 bits; no se documentan extensiones ISA de caché. |
| Pipeline con stall de caché | `top.sv`, `pipeline_control.sv`, `tb_cache_stall_*` | Conectado; requiere logs definitivos de regresión. |
| L1 4 KiB / 2 vías | `cache_l1.sv`, `l1_data_system.sv` | Identificados LRU, write-through, no-write-allocate y FIFO 4. |
| L2 16 KiB / 4 vías | `cache_l2.sv`, `l2_controller.sv` | Identificados write-back/write-allocate, LFSR y hit de 8 ciclos. |
| Inclusión | Ausencia de invalidación inversa y comportamiento de refill | Documentar como NINE; no afirmar inclusión. |
| Buffers obligatorios | `l1_write_buffer.sv`, `l2_eviction_buffer.sv`, `mem_subsystem.sv` | Presentes; RAW resuelto por stall. |
| Memoria 64 KiB y CDC | `mem_controller.sv`, `mem_subsystem.sv`, `flop_sync.sv` | Presente con 25 MHz en los benchmarks. |
| Contadores integrados | `performance_counters.sv`, `top.sv`, `tb_benchmarks_hw.sv` | Integrados; las tres filas guardadas se analizaron correctamente. |
| Benchmarks | CSV + seis gráficas SVG versionadas | Comparación entre patrones para la configuración `l1_l2_ram`. |
| Integración compilador | `pruebas-compilador/matriz.mem`, `tb_matriz.sv` | Existe programa y testbench; repetir prueba antes de defensa. |

## 2. Comprobaciones prioritarias

1. **Latencia de primera palabra RAM.** El enunciado requiere 25 ciclos de CPU desde la emisión hasta la primera palabra, más 7 transferencias a razón de 1 palabra por ciclo de memoria. `top.sv` usa `MEM_FIRST_LAT=3` por defecto y `mem_controller.sv` interpreta `FIRST_LAT` en ciclos de memoria. Medir la latencia **observada** entre el request y la primera transferencia y comprobar que se ajuste al enunciado, separando cruces de dominio, arbitraje y retardo de RAM. El `Tmem=53` del script de análisis es nominal, no verificación temporal de RTL.
2. **Objetivos obsoletos del Makefile.** Los targets `fetch` y `dispatch` utilizan rutas de módulos que se movieron. Corregir recetas para que `make test` sea ejecutable desde cero; no se modificó código en este paquete de documentación.
3. **Política NINE bajo reemplazo.** Ejecutar prueba de línea residente en L1 y desalojo en L2. La ausencia de backward invalidation implica que el diseño no debe presentarse como inclusivo; validar que la política se respete con tráfico real.
4. **Backpressure y hazards de memoria.** Repetir testbenches de FIFO llena, hit/miss de STORE, evictions dirty y lectura tras STORE, verificando coherencia entre L1, L2 y RAM incluso si las escrituras no se han drenado.
5. **Comparación sin caché.** El enunciado pide análisis de mejora sobre una línea base con latencias realistas, y comparaciones de configuraciones. El CSV actual solo registra una configuración.
6. **Optimizaciones compilador/hardware.** Medir el mismo benchmark generado por CE1108 con optimizaciones habilitadas/deshabilitadas y resultados funcionales idénticos. Las tres pruebas de patrón no permiten asignar un porcentaje de mejora a una optimización.
7. **Repetibilidad en `main`.** Antes de actualizar las gráficas finales, comprobar que la rama `main` incorpore el RTL del ZIP y repetir las pruebas desde esa revisión. Guardar hash de commit y logs.

## 3. Precauciones en redacción

- El CSV en `docs/evidencias_rendimiento/` es **evidencia previamente incluida**, no una simulación ejecutada al escribir este documento.
- El valor de AMAT es el de un **modelo teórico** calculado con hit/miss y la latencia del enunciado.
- `tb_run` puede finalizar por 40 NOP consecutivos; `tb_matriz` usa terminación por JMP. No equiparar sus ventanas de medición.
- Los resultados `sequential`, `random` y `stride` son pruebas predominantemente de lectura y no prueban por sí solos write-back de datos sucios.
- Un ZIP de GitHub no contiene necesariamente `.git`, historial ni el hash del commit. Obtener ese dato únicamente desde la copia Git original.

## 4. Lista de comprobación previa al push

- [ ] Confirmar que la rama `main` contiene la integración de cachés y contadores.
- [ ] Inspeccionar `git status` y `git diff` antes del commit.
- [ ] Repetir `make check`, `make top`, pruebas L2 y benchmarks desde `main`.
- [ ] Repetir el programa matriz y las pruebas especializadas de stall/RAW.
- [ ] Corregir y volver a comprobar los objetivos obsoletos del Makefile.
- [ ] Comprobar latencias reales de RAM respecto de la especificación.
- [ ] Definir y registrar comparativas de configuraciones/optimizaciones si van a presentarse.
- [ ] Guardar logs, CSV, gráficas y hash final coherentes entre sí.
