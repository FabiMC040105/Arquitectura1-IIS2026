# Análisis de rendimiento y validación experimental

## Método

Se utilizaron los programas `sequential`, `random` y `stride` generados por `python/generate_benchmarks.py`. Cada uno ejecuta 512 LOAD organizados en dos pasadas de 256 accesos, con datos y semilla fija. El testbench `tb_benchmarks_hw.sv` simula la CPU y la jerarquía real L1-D/L2/RAM, comprueba registros de salida y exporta los contadores; el script `run_hardware_benchmarks.sh` consolida filas PASS en CSV.

La configuración medida es `l1_l2_ram`, con CPU de 100 MHz y RAM de 25 MHz. El cálculo del AMAT usa una penalidad **nominal** de RAM de `Tmem = 25 + 7 * 4 = 53` ciclos CPU. La latencia efectiva del RTL debe interpretarse aparte de esa estimación.

## Resultados registrados

| Indicador | `sequential` | `random` | `stride` |
|:---|---:|---:|---:|
| Ciclos | 2 867 | 13 848 | 22 068 |
| Bundles retirados | 560 | 560 | 560 |
| Instrucciones retiradas | 521 | 521 | 521 |
| IPC | 0,1817 | 0,0376 | 0,0236 |
| Stalls de caché | 2 302 | 13 283 | 21 503 |
| Hits L1 | 480 | 228 | 0 |
| Misses L1 | 32 | 284 | 512 |
| Hit rate L1 | 93,75 % | 44,53 % | 0,00 % |
| Hits L2 | 0 | 118 | 256 |
| Misses L2 | 32 | 166 | 256 |
| Hit rate L2 | 0,00 % | 41,55 % | 50,00 % |
| Lecturas RAM | 32 | 166 | 256 |
| Palabras RAM | 256 | 1 328 | 2 048 |
| AMAT teórico | 4,8125 | 22,6211 | 35,5000 |

Fuente de datos: [`evidencias_rendimiento/hardware.csv`](evidencias_rendimiento/hardware.csv). Las filas fueron analizadas con `python/analyze_performance.py`.

![Ciclos totales](evidencias_rendimiento/cycles.svg)

![IPC](evidencias_rendimiento/ipc.svg)

![Tasa de aciertos L1](evidencias_rendimiento/l1_total_hit_rate.svg)

![Tasa de aciertos L2](evidencias_rendimiento/l2_total_hit_rate.svg)

![Ciclos de espera de caché](evidencias_rendimiento/cache_stall_cycles.svg)

![AMAT teórico](evidencias_rendimiento/amat_read_model_cycles.svg)

## Fórmulas

- `IPC = instrucciones no-NOP retiradas / ciclos CPU`.
- `Hit rate = hits / (hits + misses)` para cada nivel y tipo de operación.
- `Tmem nominal = 25 + 7 * ceil(100 / frecuencia_RAM_MHz)`.
- `AMAT modelo lectura = 1 + MR_L1 * (8 + MR_L2 * Tmem nominal)`.
- `Ancho de banda = palabras transferidas * 4 bytes * 100 MHz / ciclos CPU`.

Las tasas de L2 se calculan sobre sus propios accesos y no sobre todas las lecturas de CPU. Los subcontadores de stall son partes del stall total. El AMAT es un modelo de lectura que no incluye esperas adicionales por contención ni conflicto RAW.

## Discusión de resultados

`sequential` mostró la mejor localidad: 480 lecturas resueltas en L1 y solo 32 líneas solicitadas a RAM. `random` disminuyó el acierto en L1 a 44,53 % y requirió 166 líneas de RAM. `stride` falló en L1 en sus 512 lecturas; L2 sirvió 256 líneas y otras 256 debieron transferirse desde RAM. El patrón aleatorio utilizó 4,83 veces los ciclos del secuencial, y stride 7,70 veces, con el mismo número de instrucciones retiradas.

Las pruebas incluidas comparan **patrones de acceso en una sola configuración** y son de lectura. No representan una comparación medida con memoria sin caché ni una cuantificación aislada de optimizaciones del compilador. Para validación de escrituras, conflictos RAW y desalojos sucios se emplean pruebas dirigidas de `tb/`.

## Integración con CE1108

`pruebas-compilador/matriz.mem` se prueba con `tb_matriz.sv`, que verifica 100 posiciones de matrices de 10×10 sobre el hardware VLIW integrado. El registro documental del repositorio indica 539 896 ciclos, resultado inicial 21, contador de errores 0 e indicador de prueba correcta 1. El testbench revisa los valores visibles en caché o en RAM, considerando el carácter write-back de L2.

## Reproducción

```bash
bash scripts/run_hardware_benchmarks.sh
python3 python/analyze_performance.py \
  --hardware docs/evidencias_rendimiento/hardware.csv \
  --out build/analisis-evidencia
```

El detalle de la arquitectura, protocolo, metodología y conclusiones se presenta en el [informe final](informe-final-proyecto2.md).
