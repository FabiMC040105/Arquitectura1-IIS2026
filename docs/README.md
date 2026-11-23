# Documentación técnica — Proyecto Grupal II (CE4301)

**Instituto Tecnológico de Costa Rica · Escuela de Ingeniería en Computadores · II semestre de 2026**

**Proyecto:** Análisis de impacto de memoria caché y optimizaciones de compilador en el procesador propio VLIW.

## Informe de entrega

[**Informe final del Proyecto II**](informe-final-proyecto2.md): documento unificado que describe el diseño, la integración de componentes, las políticas de memoria, la metodología experimental, los resultados de rendimiento, la validación funcional y las conclusiones.

## Documentos técnicos

| Documento | Contenido |
|:---|:---|
| [Microarquitectura](microarchitecture.md) | Pipeline, ISA VLIW, unidades, control de stalls y contadores. |
| [Jerarquía de memoria](integracion-l1-l2.md) | L1-D, L2, políticas, buffers, RAM y coherencia de datos. |
| [Rendimiento y validación](performance.md) | Metodología, métricas, tablas, gráficas e interpretación. |
| [Simulación y pruebas](simulation.md) | Dependencias, comandos de ejecución, scripts y testbenches. |
| [Especificación de ISA](isa.md) | Codificación y semántica de instrucciones heredadas del Proyecto I. |
| [Contrato con Compiladores](compiler-integration.md) | Interfaz binaria, convenciones de registros y calendarización. |
| [Trazabilidad de verificación](pendientes-proyecto2.md) | Relación de requisitos, módulos y evidencias del sistema. |

## Figuras y resultados

- [Arquitectura del procesador VLIW](diagramas/procesador_vliw.svg).
- [Jerarquía L1-D/L2/RAM](diagramas/jerarquia_cache.svg).
- [CSV de resultados de hardware](evidencias_rendimiento/hardware.csv).
- [Gráficos de ciclos, IPC, hits, stalls y AMAT](performance.md#resultados-registrados).

El conjunto de métricas corresponde a la configuración `l1_l2_ram` a 100 MHz de CPU y 25 MHz de memoria, para los patrones `sequential`, `random` y `stride`.
