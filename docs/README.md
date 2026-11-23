# Documentación de diseño — Proyecto II (CE4301)

Esta carpeta cubre los tres bloques de documentación exigidos para la ampliación del VLIW: **jerarquía de memoria**, **organización/microarquitectura** y **análisis de rendimiento y validación**. Está elaborada a partir de la instantánea del repositorio entregada como `feature-integracion-metricas-final`; no representa un commit certificado de `main`.

| Documento | Qué contiene | Archivos fuente que lo sustentan |
| --- | --- | --- |
| [integracion-l1-l2.md](integracion-l1-l2.md) | Capacidades, organización por conjuntos, políticas L1/L2, buffers, RAW, inclusión NINE y diagrama | `src/memory/*.sv`, `src/top.sv` |
| [microarchitecture.md](microarchitecture.md) | Pipeline VLIW, stalls de bundle, unidades, reloj de RAM y contadores; diagrama del sistema | `src/top.sv`, `src/pipeline/*.sv`, `src/performance_counters.sv` |
| [performance.md](performance.md) | Método experimental, fórmulas, CSV, 3 benchmarks, gráficos y limitaciones | `tb/tb_benchmarks_hw.sv`, `python/analyze_performance.py`, `docs/evidencias_rendimiento/` |
| [simulation.md](simulation.md) | Ambiente WSL, comandos de reproducción, testbenches y criterios de éxito | `Makefile`, `scripts/*.sh`, `tb/*.sv` |
| [pendientes-proyecto2.md](pendientes-proyecto2.md) | Requisitos por validar y diferencias detectadas en el código/documentación | Enunciado del Proyecto II y repositorio |
| [isa.md](isa.md) | Codificación ISA preservada desde el Proyecto I | `python/assembler.py`, decodificadores |
| [compiler-integration.md](compiler-integration.md) | Contrato con CE1108; programas ensamblados y pruebas conjuntas | ISA y backend de integración |

## Evidencia disponible

Los archivos `evidencias_rendimiento/hardware.csv` y `evidencias_rendimiento/*.svg` están incluidos en el repositorio. Se volvieron a **procesar y validar estructuralmente** las tres filas CSV mediante `python/analyze_performance.py` sin errores. No se infiere por ello que se hayan recompilado los testbenches en esta revisión.

## Criterio de actualización

Actualizar primero el código y sus pruebas; luego generar de nuevo los resultados experimentales; por último sincronizar las tablas de `performance.md`, los diagramas y los comandos de este README. No atribuir al simulador valores teóricos calculados por Python.
