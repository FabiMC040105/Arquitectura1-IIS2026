# Medicion del rendimiento

## Metodologia

Se contemplan tres benchmarks de lectura con 512 accesos previstos cada uno, en dos pasadas sobre la misma secuencia. El patron secuencial usa direcciones contiguas, el aleatorio selecciona palabras con semilla fija y el stride usa un salto de 32 bytes. Todos utilizan los mismos datos iniciales y se verifica el estado final de los diez registros esperados. Esta verificacion no sustituye pruebas de escritura, reemplazo y coherencia de los modulos de cache.

## Ejecucion preliminar

Desde la raiz del repositorio, con Icarus Verilog, Make y Python 3 instalados:

```bash
bash scripts/run_benchmarks.sh
python3 python/analyze_performance.py --baseline build/benchmarks/resultados_lecturas.csv
```

Los resultados se guardan en `build/benchmarks/analysis/`. El script ejecuta la jerarquia actual L1, L2 y RAM. Su CSV resume pruebas funcionales y no sustituye la exportacion de contadores de hardware. Los ciclos de `tb_run` incluyen su criterio de fin; los bundles en ROM son un conteo estatico y no deben utilizarse como instrucciones retiradas. Esta corrida es una referencia funcional preliminar, no una comparacion entre configuraciones.

## Contadores integrados

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


## Resultados de las pruebas de integracion

Se verificaron los contadores utilizando programas pequenos
ejecutados en el procesador completo con L1, L2 y RAM.

### Comparacion de lecturas

| Prueba | Ciclos | Instrucciones | IPC | Hit rate L1 | AMAT teorico |
| --- | ---: | ---: | ---: | ---: | ---: |
| Una lectura | 77 | 2 | 0.0260 | 0% | 62.0 |
| Dos lecturas | 80 | 3 | 0.0375 | 50% | 31.5 |

En ambas pruebas se realizo una sola lectura fisica de RAM.
En la segunda, el LOAD adicional encontro su linea en L1.

Estos programas tienen diferente cantidad de instrucciones.
Por lo tanto, sus resultados sirven para demostrar la
reutilizacion de cache, pero no constituyen una comparacion
definitiva de velocidad entre configuraciones.

### Prueba de escritura

Se ejecuto un STORE seguido de un LOAD a la misma direccion.
El valor escrito fue recuperado correctamente.

Los contadores registraron:

- L1 write hits: 0
- L1 write misses: 1
- L2 write hits: 0
- L2 write misses: 1
- Lecturas fisicas de RAM: 1
- Escrituras fisicas de RAM: 0

El resultado es compatible con la politica write-back de L2.
Aun faltan pruebas adicionales de hits de escritura y desalojo
de lineas modificadas.

### Penalizaciones por saltos

Se realizaron tres pruebas:

| Caso | Penalizacion registrada | Resultado |
| --- | ---: | --- |
| JMP tomado desde EX | 3 ciclos | PASS |
| BNE no tomado | 0 ciclos | PASS |
| Redireccion del PC desde WB | 4 ciclos | PASS |

Los 3 y 4 ciclos proceden del modelo de recuperacion
implementado con las etapas invalidadas del pipeline.
Todavia falta contrastar esa estimacion con las burbujas
observadas independientemente en cada ejecucion.

### Regresiones

Pasaron correctamente:

- Compilacion completa de top.sv
- Pruebas de L1 y L2
- Pruebas aisladas de contadores y reset
- Integracion CPU, L1, L2 y RAM
- Pruebas basicas de saltos

Los resultados se exportaron a CSV y se analizaron
con python/analyze_performance.py, generando tablas
y graficas SVG.

### Validacion del programa matriz

Se ejecuto pruebas-compilador/matriz.mem sobre el procesador
completo con CPU, L1, L2 y RAM.

El programa contiene 4015 bundles y finaliza mediante un
salto JMP 0. Por eso se utilizo un testbench que detecta
ese salto en lugar de esperar 40 bundles NOP consecutivos.

Resultados obtenidos:

- Ciclos: 539896
- PC del salto final: 0x0000FAD0
- Matriz: 10x10
- resultado[0][0]: 21
- Indicador errores: 0
- Indicador prueba_correcta: 1
- Validacion de los elementos de las matrices: PASS

La verificacion consulta los valores visibles en la
jerarquia L1/L2/RAM, considerando las escrituras que
todavia pueden permanecer en cache.

El resultado demuestra la ejecucion funcional del programa
matriz en la arquitectura integrada.

## Benchmarks con contadores de hardware

Se ejecutaron los patrones sequential, random y stride sobre el procesador completo con L1, L2 y RAM.

Cada programa realiza 512 LOAD, distribuidos en dos pasadas. Se verificaron los registros finales antes de aceptar los resultados.

| Benchmark | Ciclos | IPC | Hit L1 | Hit L2 | AMAT teorico |
| --- | ---: | ---: | ---: | ---: | ---: |
| sequential | 2867 | 0.1817 | 93.75% | 0.00% | 4.8125 |
| random | 13848 | 0.0376 | 44.53% | 41.55% | 22.6211 |
| stride | 22068 | 0.0236 | 0.00% | 50.00% | 35.5000 |

### Contadores de memoria

| Benchmark | Hits L1 | Misses L1 | Hits L2 | Misses L2 | Lecturas RAM | Palabras RAM |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| sequential | 480 | 32 | 0 | 32 | 32 | 256 |
| random | 228 | 284 | 118 | 166 | 166 | 1328 |
| stride | 0 | 512 | 256 | 256 | 256 | 2048 |

### Interpretacion

El patron secuencial obtuvo el mayor IPC y la mayor tasa de hits en L1. El patron aleatorio genero mas fallos de cache, mientras que stride obtuvo un miss en L1 por cada lectura. Esto incremento los ciclos necesarios para completar la misma cantidad de instrucciones.

El AMAT reportado corresponde al modelo teorico de lectura. No representa una medicion directa de latencia por acceso.

Estas pruebas comparan patrones de acceso sobre la misma arquitectura. No constituyen una comparacion contra una configuracion sin cache.

### Reproduccion

```bash
bash scripts/run_hardware_benchmarks.sh
```

El script genera los programas, valida los registros, exporta los contadores y produce reportes y graficas SVG en build/benchmarks/analysis-hardware/.


## Comparaciones pendientes

Se debe repetir cada benchmark con memoria realista sin cache y con L1/L2, manteniendo los mismos datos, programa y criterio de medicion. Se compararan configuraciones de cache acordadas por el equipo y programas del compilador con diferentes optimizaciones, verificando que las salidas sean equivalentes. Ya se capturaron resultados de las pruebas pequenas. Faltan las comparaciones definitivas entre configuraciones y los benchmarks completos.
