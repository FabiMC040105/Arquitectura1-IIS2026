# Arquitectura de Computadores I — Proyecto Grupal II

**Instituto Tecnológico de Costa Rica · CE4301 · II semestre de 2026**

**Análisis de impacto de memoria caché y optimizaciones de compilador en un procesador VLIW propio**

El repositorio contiene el procesador VLIW de cuatro slots desarrollado para el Proyecto I, extendido en el Proyecto II con una jerarquía de memoria de datos L1-D/L2, buffers de escritura, RAM simulada en un dominio de reloj más lento y contadores de rendimiento. El diseño está implementado en SystemVerilog y se simula con Icarus Verilog. Incluye un ensamblador propio, pruebas de integración y benchmarks de memoria.

[**Leer informe final del Proyecto II**](docs/informe-final-proyecto2.md) · [**Índice de documentación técnica**](docs/README.md)

## Características

| Elemento | Implementación |
|:---|:---|
| ISA | VLIW de 128 bits, cuatro slots de 32 bits |
| Unidades | ALU, LSU, BRU y FEIST con bóveda de llaves |
| Pipeline | IF, ID, RR, EX, WB |
| Registros | 16 registros de 32 bits |
| ROM de instrucciones | 64 KiB, bundles completos |
| L1-D | 4 KiB, dos vías, línea de 32 bytes, LRU |
| Política L1 | Write-through / no-write-allocate; FIFO de 4 STORE |
| L2 | 16 KiB, cuatro vías, línea de 32 bytes, LFSR |
| Política L2 | Write-back / write-allocate; FIFO de 8 líneas sucias |
| Inclusión | NINE (no inclusiva, no exclusiva) |
| RAM de datos | 64 KiB, ráfaga de ocho palabras |
| Relojes de benchmark | CPU a 100 MHz; RAM a 25 MHz |
| Métricas | Ciclos, bundles, instrucciones, stalls, hits/misses y transferencias |

Los accesos de LSU detienen el bundle completo cuando la jerarquía necesita esperar. La calendarización entre bundles es estática y debe resolver las dependencias en el programa generado; el hardware no utiliza forwarding/scoreboarding general.

## Estructura

```text
.
├── README.md
├── Makefile
├── src/
│   ├── top.sv
│   ├── performance_counters.sv
│   ├── pipeline/
│   ├── functional-units/
│   ├── memory/
│   │   ├── cache_l1.sv
│   │   ├── l1_data_system.sv
│   │   ├── l1_write_buffer.sv
│   │   ├── cache_l2.sv
│   │   ├── l2_data_system.sv
│   │   ├── l2_eviction_buffer.sv
│   │   ├── l2_mem_bridge.sv
│   │   ├── mem_subsystem.sv
│   │   └── mem_controller.sv
├── tb/
├── python/
├── scripts/
├── benchmarks/
├── pruebas-compilador/
└── docs/
    ├── README.md
    ├── informe-final-proyecto2.md
    ├── integracion-l1-l2.md
    ├── microarchitecture.md
    ├── performance.md
    ├── simulation.md
    ├── isa.md
    ├── compiler-integration.md
    ├── diagramas/
    └── evidencias_rendimiento/
```

## Dependencias

En Ubuntu o Ubuntu sobre WSL:

```bash
sudo apt update
sudo apt install -y iverilog make python3
```

GTKWave es opcional para visualizar archivos VCD:

```bash
sudo apt install -y gtkwave
```

## Elaboración y ejecución

Comprobar los módulos y la instancia integrada:

```bash
make check
make top
```

Ejecutar las pruebas dirigidas L2 e integración L1/L2:

```bash
bash scripts/run_l2_tests.sh
```

Ejecutar los benchmarks de hardware completos, con generación, simulación y validación de resultados:

```bash
bash scripts/run_hardware_benchmarks.sh
```

Las mediciones quedan bajo `build/benchmarks/`. Para procesar el CSV guardado en el repositorio y volver a generar tablas y gráficas:

```bash
python3 python/analyze_performance.py \
  --hardware docs/evidencias_rendimiento/hardware.csv \
  --out build/analisis-evidencia
```

## Ensamblador y programas propios

El ensamblador `python/assembler.py` traduce instrucciones de la ISA a líneas de 128 bits en hexadecimal, cargables mediante `$readmemh`. Cada línea representa un bundle con cuatro slots, completados con NOP cuando no se utilizan.

```bash
mkdir -p build
python3 python/assembler.py prueba_cifrado.asm -o build/programa_ejemplo.mem
make run PROGRAM=build/programa_ejemplo.mem DATA=input.mem
```

La herramienta `python/procesar_archivo_completo.py` prepara archivos de entrada para el cifrado/descifrado de demostración con la unidad Feistel4 de la arquitectura.

## Benchmarks de rendimiento

Los archivos en `docs/evidencias_rendimiento/` incluyen un CSV con las tres pruebas de lectura sobre la misma configuración `l1_l2_ram`:

| Patrón | Ciclos | IPC | Hit L1 de lectura |
|:---|---:|---:|---:|
| Secuencial | 2 867 | 0,1817 | 93,75 % |
| Aleatorio | 13 848 | 0,0376 | 44,53 % |
| Stride | 22 068 | 0,0236 | 0,00 % |

Cada programa registra 521 instrucciones retiradas y 512 LOAD. La explicación de la metodología, los contadores, el AMAT teórico y la interpretación de resultados se encuentra en [docs/performance.md](docs/performance.md).

## Integración con Compiladores

El procesador recibe código conforme al contrato ISA–Compilador del curso CE1108. La prueba `tb/tb_matriz.sv` utiliza `pruebas-compilador/matriz.mem` y verifica las matrices 10×10 mediante lectura de los valores visibles en L1, L2 o RAM.

Documentos: [ISA](docs/isa.md) y [contrato de integración](docs/compiler-integration.md).

## Documentación de entrega

La documentación del Proyecto II está íntegramente en `docs/` y contiene la arquitectura de la jerarquía, organización del pipeline, políticas y buffers, metodología, benchmarks y resultados. El informe unificado puede consultarse en [docs/informe-final-proyecto2.md](docs/informe-final-proyecto2.md).
