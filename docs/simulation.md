# Simulación, ejecución y validación

## Ambiente

Se utiliza Ubuntu o WSL con Ubuntu, Icarus Verilog (`iverilog`, `vvp`), GNU Make, Python 3 y Bash. Para visualizar archivos VCD puede instalarse GTKWave.

```bash
sudo apt update
sudo apt install -y iverilog make python3 gtkwave
```

Todos los comandos se ejecutan desde la raíz del repositorio.

## Elaboración del procesador

```bash
make check
make top
```

El objetivo `check` elabora los módulos de control y las unidades funcionales; `top` comprueba la integración de todas las fuentes SystemVerilog definidas en la variable `SRC` del Makefile.

## Pruebas L2 e integración L1/L2

```bash
bash scripts/run_l2_tests.sh
```

El script ejercita nueve pruebas dirigidas: `tb_cache_l2`, `tb_l2_controller`, `tb_l2_eviction_buffer`, `tb_l2_replacement`, `tb_l2_data_system`, `tb_l2_raw_stall`, `tb_l2_latency`, `tb_l2_buffer_full` y `tb_l1_l2_integration`. Cubren hit/miss, política de víctima, espera por buffer lleno, dependencia RAW y protocolo de respuesta.

## Benchmarks de CPU, cachés y RAM

```bash
bash scripts/run_hardware_benchmarks.sh
```

El script invoca `python/generate_benchmarks.py`, compila `tb_benchmarks_hw.sv`, ejecuta tres simulaciones con `vvp`, comprueba registros finales y genera `build/benchmarks/hardware.csv`. El analizador Python produce `hardware_metrics.csv`, `hardware_report.md` y seis gráficos SVG en `build/benchmarks/analysis-hardware/`.

Para volver a analizar el CSV incluido en el repositorio sin repetir la simulación:

```bash
python3 python/analyze_performance.py \
  --hardware docs/evidencias_rendimiento/hardware.csv \
  --out build/analisis-evidencia
```

## Prueba del programa matriz

```bash
mkdir -p build
mapfile -t RTL < <(sed -n '/^SRC =/,/^$/p' Makefile | grep -oE 'src/[^[:space:]\\]+\.sv')
iverilog -g2012 -Wall -s tb_matriz -o build/tb_matriz.vvp \
  tb/tb_matriz.sv "${RTL[@]}"
vvp build/tb_matriz.vvp
```

El testbench ejecuta `pruebas-compilador/matriz.mem`, reconoce el salto final y verifica el contenido de los arreglos. Su mecanismo de lectura contempla L1, L2 y RAM.

## Ensamblador y ejecución de programas propios

```bash
mkdir -p build
python3 python/assembler.py prueba_cifrado.asm -o build/programa_ejemplo.mem
make run PROGRAM=build/programa_ejemplo.mem DATA=input.mem
```

Los argumentos `PROGRAM` y `DATA` definen los archivos cargados en las memorias simuladas. El flujo de cifrado de archivos se implementa en `python/procesar_archivo_completo.py`, según la documentación del procesador original.

## Criterios de validación

- Elaboración sin errores del módulo `top` y sus dependencias.
- Conclusión de cada testbench sin fallo de aserciones o timeout.
- Coincidencia de los registros finales esperados en los tres benchmarks.
- Conteo coherente de ciclos, retiros, misses y tráfico físico de RAM.
- Verificación funcional de la matriz 10×10 producida por el código del compilador.

Los objetivos `make fetch`, `make dispatch` y el objetivo agregado `make test` conservan referencias antiguas a `src/fetch.sv`, `src/dispatch.sv` y `src/instruction_memory.sv`; el procedimiento oficial reproducible de esta documentación usa `make check`, `make top` y los scripts con las rutas actuales.
