# Guía de simulación y validación — Proyecto II

Este documento describe rutas y comandos del ZIP `feature-integracion-metricas-final`. No supone que los tests ya se hayan corrido en la máquina donde se prepara esta documentación.

## 1. Ambiente WSL

```bash
sudo apt update
sudo apt install -y iverilog make python3
cd /ruta/a/Arquitectura1-IIS2026
```

Trabajar desde la raíz del repositorio es importante: `top.sv` carga `PROGRAM_FILE` y `DATA_FILE` por rutas relativas, y los scripts escriben archivos bajo `build/`. Para visualizar ondas (opcional): `sudo apt install -y gtkwave`.

## 2. Verificación de compilación

```bash
make check
make top
```

`make check` comprueba la elaboración de los módulos principales indicados en el objetivo. `make top` elabora la instancia integrada `top` utilizando la lista `SRC` (29 módulos en el avance revisado).

**Importante:** `make fetch`, `make dispatch` y, por dependencia, `make test` hacen referencia a rutas antiguas (`src/fetch.sv`, `src/dispatch.sv`, `src/instruction_memory.sv`) que ahora se encuentran bajo `src/pipeline/` y `src/memory/`. No deben presentarse como un procedimiento de regresión válido hasta corregir esas recetas en el Makefile. La actualización documental no modifica ese archivo.

## 3. Jerarquía L2 e integración L1/L2

```bash
bash scripts/run_l2_tests.sh
```

El script compila y ejecuta, por separado:

| Testbench | Propósito |
| --- | --- |
| `tb_cache_l2` | Almacenamiento y consulta de líneas en L2. |
| `tb_l2_controller` | Handshakes y clasificación hit/miss. |
| `tb_l2_eviction_buffer` | FIFO de líneas sucias y conflictos RAW. |
| `tb_l2_replacement` | Congelamiento y selección de víctima. |
| `tb_l2_data_system` | Controlador L2, write-back e interfaz de memoria. |
| `tb_l2_raw_stall` | Espera ante lectura de línea pendiente de drenaje. |
| `tb_l2_latency` | Latencia de respuesta de hit de L2. |
| `tb_l2_buffer_full` | Backpressure cuando FIFO de desalojo se llena. |
| `tb_l1_l2_integration` | Funcionamiento conjunto de L1 y L2. |

La ejecución se detiene al primer error por `set -euo pipefail`.

## 4. Benchmarks en CPU completa

```bash
bash scripts/run_hardware_benchmarks.sh
```

El flujo automatizado:

1. Genera programas y datos (`python/generate_benchmarks.py`).
2. Extrae los archivos `SRC` del Makefile.
3. Compila `tb_benchmarks_hw.sv` junto al RTL para `sequential`, `random`, `stride`.
4. Ejecuta `vvp` y guarda logs `build/benchmarks/hw_*.log`.
5. Verifica los registros de salida mediante `--check-log`.
6. Consolida solo los tres casos correctos en `build/benchmarks/hardware.csv`.
7. Produce `hardware_metrics.csv`, `hardware_report.md` y gráficos SVG con el analizador.

**Criterio de prueba:** 40 bundles NOP consecutivos. El conteo CSV de ciclos y de instrucciones incluye la ventana de observación definida por el testbench; debe usarse el mismo criterio para las configuraciones comparadas.

## 5. Contadores y pruebas de integración especializadas

Para ejecutar pruebas de un archivo en `tb/` que use `top`:

```bash
mkdir -p build
mapfile -t RTL < <(sed -n '/^SRC =/,/^$/p' Makefile | grep -oE 'src/[^[:space:]\\]+\.sv')
iverilog -g2012 -Wall -s tb_metricas -o build/tb_metricas.vvp tb/tb_metricas.sv "${RTL[@]}"
vvp build/tb_metricas.vvp
```

Otras pruebas representativas:

```bash
iverilog -g2012 -Wall -s tb_pipeline_performance_integration \
  -o build/tb_pipeline_performance_integration.vvp \
  tb/tb_pipeline_performance_integration.sv "${RTL[@]}"
vvp build/tb_pipeline_performance_integration.vvp

iverilog -g2012 -Wall -s tb_matriz -o build/tb_matriz.vvp \
  tb/tb_matriz.sv "${RTL[@]}"
vvp build/tb_matriz.vvp
```

`tb_matriz.sv` usa explícitamente el programa compilado `pruebas-compilador/matriz.mem` y `DATA_FILE=""`. Detecta la terminación por salto, no por NOP. La verificación de estado examina valores visibles en los tres niveles, respetando la presencia posible de datos sucios aún en caché.

## 6. Ejecución con programa propio

```bash
python3 python/assembler.py prueba_cifrado.asm -o build/programa_ejemplo.mem
make run PROGRAM=build/programa_ejemplo.mem DATA=input.mem
```

`make run` compila `tb_run` y las fuentes actuales. La compatibilidad de terminación depende del programa; si termina con bucle de salto debe usarse un testbench apropiado.

## 7. Reutilización de evidencias guardadas

```bash
python3 python/analyze_performance.py \
  --hardware docs/evidencias_rendimiento/hardware.csv \
  --out build/analisis-evidencia
cat build/analisis-evidencia/hardware_report.md
```

Esto **solo analiza el CSV almacenado**. Los valores numéricos y gráficas se explican en [performance.md](performance.md); no equivalen a una recompilación del hardware.

## 8. Qué guardar en la entrega

- Último commit y su hash: `git rev-parse HEAD`.
- Evidencia de compilación: salida de `make check` y `make top`.
- Logs de `run_l2_tests.sh`, `run_hardware_benchmarks.sh` y pruebas relevantes.
- CSV validado y gráficos reproducidos desde el mismo commit.
- Identificación clara de cualquier fallo, warning o diferencia con el enunciado.

No subir productos temporales de `build/` a menos que el profesor los solicite expresamente; el repositorio ya conserva resultados finales bajo `docs/evidencias_rendimiento/`.
