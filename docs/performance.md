# Medicion del rendimiento

## Metodologia

Se ejecutan tres benchmarks de lectura con 512 accesos previstos cada uno, en dos pasadas sobre la misma secuencia. El patron secuencial usa direcciones contiguas, el aleatorio selecciona palabras con semilla fija y el stride usa un salto de 32 bytes. Todos utilizan los mismos datos iniciales y se verifica el estado final de los diez registros esperados. Esta verificacion no sustituye pruebas de escritura, reemplazo y coherencia de los modulos de cache.

## Ejecucion preliminar

Desde la raiz del repositorio, con Icarus Verilog, Make y Python 3 instalados:

```bash
bash scripts/run_benchmarks.sh
python3 python/analyze_performance.py --baseline build/benchmarks/baseline.csv
```

Los resultados se guardan en `build/benchmarks/analysis/`. El procesador original no representa todavia la memoria externa de latencia realista exigida en la iteracion 2. Los ciclos de `tb_run` incluyen su criterio de fin; los bundles en ROM son un conteo estatico y no deben utilizarse como instrucciones retiradas. Esta corrida es una referencia funcional preliminar, no la comparacion definitiva sin cache.

## Contadores integrados (pendiente de conectar)

El modulo `performance_counters` cuenta en el reloj del procesador durante la ventana de medicion. El retiro debe producirse una sola vez por bundle valido en WB, contando los cuatro bits de actividad no-NOP, incluidos STORE, BRU y operaciones de seguridad sin escritura de registros. No se cuentan bundles invalidados por flush ni se repiten durante stall. La medicion debe incluir los ciclos de llenado y drenado del pipeline hasta completar la ultima instruccion real del programa, con un criterio identico en todas las configuraciones.

L1 se cuenta al clasificar la solicitud original antes del refill. Una lectura que causa miss no vuelve a contarse como hit cuando se entrega la linea. L2 reutiliza los cuatro contadores del controlador. Los accesos de L2 incluyen escrituras del write buffer, por lo que se separan lectura y escritura. La memoria cuenta solicitudes aceptadas y palabras realmente transferidas, sincronizadas al reloj de CPU. Las fases de stall deben excluirse entre si; el total de cache incluye espera por buffers y no se suma nuevamente a sus subcategorias. El contador de salto requiere un evento por ciclo perdido, no solo un pulso por salto tomado; se debe validar al integrar.

## Metricas

- IPC = instrucciones no-NOP completadas / ciclos totales.
- Hit rate = hits / (hits + misses), separado por nivel y por tipo de acceso. Miss rate = 1 - hit rate cuando existen accesos.
- Tmem = 25 + 7 * ceil(100 / frecuencia_memoria_MHz), en ciclos de CPU.
- AMAT teorico de lectura = 1 + miss_rate_L1_read * (8 + miss_rate_L2_read * Tmem). La tasa de L2 es local a las lecturas que llegan desde L1. Este modelo supone jerarquia completa, no incluye contencion ni espera por buffers y no equivale a una latencia medida por solicitud.
- Accesos a memoria = lecturas de lineas + escrituras de lineas. Ciclos nominales de transferencia = accesos * Tmem; se reportan tambien los ciclos de ocupacion observados, sin asumir que sean iguales.
- Ancho de banda observado = palabras transferidas * 4 bytes * 100 MHz / ciclos de CPU. Utilizacion = ancho de banda observado / (4 bytes * frecuencia de memoria), en porcentaje. La ventana de medicion debe ser comun a ambas cantidades.

## Contrato CSV para la integracion

El testbench definitivo debe exportar una fila por benchmark y configuracion, con `status=PASS` solo despues de validar la salida. Las columnas son:

```text
benchmark,configuration,status,memory_mhz,cycles,bundles,instructions,cache_stall_cycles,branch_stall_cycles,l2_lookup_stall_cycles,memory_stall_cycles,buffer_stall_cycles,l1_read_hits,l1_read_misses,l1_write_hits,l1_write_misses,l2_read_hits,l2_read_misses,l2_write_hits,l2_write_misses,mem_reads,mem_writes,mem_busy_cycles,mem_words
```

Los contadores deben provenir del hardware, no de las direcciones previstas por el generador. Para una configuracion sin cache se debe usar un reporte separado y medir el IPC real con los contadores del pipeline, sin aplicar el modelo AMAT de dos niveles. Para la jerarquia completa:

```bash
python3 python/analyze_performance.py --hardware build/benchmarks/hardware.csv --out build/benchmarks/analysis-hardware
```

## Comparaciones pendientes

Se debe repetir cada benchmark con memoria realista sin cache y con L1/L2, manteniendo los mismos datos, programa y criterio de medicion. Se compararan configuraciones de cache acordadas por el equipo y programas del compilador con diferentes optimizaciones, verificando que las salidas sean equivalentes. No se publican cifras de IPC, AMAT ni tasas de cache hasta capturar los contadores integrados. Se agregaran las tablas y graficos reales al completar estas pruebas.
