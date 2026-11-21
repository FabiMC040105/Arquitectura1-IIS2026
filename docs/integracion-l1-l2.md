# Integración L1 + L2 (conjunto de trabajo)

Esta carpeta reúne la rama de **L1 proporcionada por el equipo** y los módulos de **L2** construidos durante la conversación.

## Código de L2

- `src/cache_l2.sv`: caché de datos de 16 KiB, cuatro vías, 128 conjuntos, líneas de 32 bytes; reemplazo pseudoaleatorio con LFSR.
- `src/l2_controller.sv`: control de hits/misses, write-allocate, contadores, víctima congelada durante backpressure y hit de lectura de ocho ciclos.
- `src/l2_eviction_buffer.sv`: FIFO de ocho líneas sucias con detección de conflicto RAW.
- `src/l2_data_system.sv`: conexión de controlador, FIFO y árbitro hacia un único puerto de memoria.

## Tests añadidos

- `tb/tb_cache_l2.sv`: prueba unitaria básica de datos en caché.
- `tb/tb_l2_controller.sv`: prueba unitaria básica de controlador.
- `tb/tb_l2_eviction_buffer.sv`: FIFO, full, orden y RAW.
- `tb/tb_l2_replacement.sv`: selección/congelamiento de víctima dirty.
- `tb/tb_l2_data_system.sv`: write-back y recuperación desde RAM simulada.
- `tb/tb_l2_raw_stall.sv`: lectura de una línea pendiente de write-back.
- `tb/tb_l2_latency.sv`: latencia exacta de ocho ciclos en read hit.
- `tb/tb_l2_buffer_full.sv`: backpressure con FIFO llena.
- `tb/tb_l1_l2_integration.sv`: prueba de integración entre L1 y L2 reales con RAM simulada.

Los tests `tb_cache_l2.sv`, `tb_l2_controller.sv` y `tb_l2_eviction_buffer.sv` se reconstruyeron a partir del código presentado en el chat; los demás tests y módulos se copiaron de los archivos generados anteriormente. El código reconstruido y el test final L1+L2 deben ejecutarse y verificarse localmente.

## Ejecución

Desde la raíz del repositorio:

```bash
bash scripts/run_l2_tests.sh
```

Requiere `iverilog` y `vvp` instalados. La suite compila y ejecuta un test a la vez, deteniéndose al primer error.

## Límites actuales

- La integración de pruebas usa **RAM simulada**, no el controlador definitivo de memoria de la Persona 4.
- La integración con el `top.sv` y el pipeline del procesador no está hecha.
- La interfaz de memoria del wrapper requiere una respuesta para la finalización de escrituras.
- Las decisiones de política de inclusión NINE, write-back, write-allocate y reemplazo Random deben acordarse/documentarse con el grupo.
- Este ZIP no contiene historial ni metadatos Git, y no cambia ninguna rama/commit.
