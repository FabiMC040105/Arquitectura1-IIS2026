# Integración con Compiladores (CE1108) — Contrato ISA–Compilador

**Curso:** CE-4301 Arquitectura de Computadores I  
**Proyecto:** Proyecto Grupal I — Arquitectura VLIW propia para cifrado por bloques Feistel4  
**Documento:** `docs/compiler-integration.md`  
**Estado:** Integración validada con programas generados por el compilador de CE1108.

## 1. Propósito

El procesador VLIW desarrollado en CE4301 se integra con el compilador del curso CE1108 para ejecutar programas escritos en el lenguaje de alto nivel definido por el grupo de Compiladores e Intérpretes.

El contrato de integración establece el formato binario de los bundles, la distribución de slots, las codificaciones de instrucciones, las convenciones de registros, la organización de memoria y las reglas de calendarización necesarias para que el código generado por CE1108 pueda ejecutarse directamente sobre la implementación SystemVerilog del procesador.

La integración fue validada con tres programas completos generados por el compilador de CE1108: cálculo de factorial, búsqueda en una matriz bidimensional y cálculo del máximo común divisor. Los tres programas alcanzaron correctamente su punto final y produjeron los resultados esperados en registros y memoria.

Documentación relacionada:

- [`isa.md`](isa.md): especificación completa de la ISA y codificación binaria.
- [`microarchitecture.md`](microarchitecture.md): organización interna y pipeline.
- [`simulation.md`](simulation.md): simulación, testbenches y herramientas de carga de archivos.

Repositorio del compilador CE1108:

- https://github.com/FabiMC040105/CompiladoresIIS2026.git

## 2. Responsabilidades de integración

| Equipo | Responsabilidad |
| --- | --- |
| **CE4301 — Arquitectura** | Mantener la ISA, la codificación binaria, el procesador SystemVerilog, el ensamblador propio y la interfaz de simulación. |
| **CE1108 — Compiladores** | Traducir el lenguaje de alto nivel, generar ensamblador y código de máquina, resolver etiquetas, calendarizar dependencias e insertar NOP cuando corresponda. |
| **Integración conjunta** | Verificar que el binario generado respete el contrato de la ISA y produzca resultados correctos al ejecutarse sobre el procesador VLIW. |

La arquitectura utiliza calendarización estática. El procesador no realiza reordenamiento dinámico, *scoreboarding* ni *forwarding* automático para resolver dependencias de datos; estas dependencias se resuelven en el código generado.

## 3. Formato de bundle

Cada instrucción VLIW ocupa **128 bits (16 bytes)** y contiene cuatro slots fijos de 32 bits:

```text
  127             96 95              64 63              32 31               0
  +-----------------+-------------------+-------------------+-------------------+
  | FEIST (slot 3)  | BRU (slot 2)      | LSU (slot 1)      | ALU (slot 0)      |
  +-----------------+-------------------+-------------------+-------------------+
```

| Slot | Bits | Unidad |
| --- | --- | --- |
| 0 | `[31:0]` | ALU |
| 1 | `[63:32]` | LSU |
| 2 | `[95:64]` | BRU |
| 3 | `[127:96]` | FEIST |

Los slots sin operación se rellenan con `0x00000000`. Los bits reservados de cada instrucción también se codifican con cero.

La memoria de instrucciones utiliza `$readmemh`, por lo que cada línea del archivo de programa contiene un bundle completo representado por **32 dígitos hexadecimales**:

```text
FEIST | BRU | LSU | ALU
```

Ejemplo de un bundle con una operación ALU y los otros tres slots en NOP:

```text
00000000000000000000000000003241
```

El PC es una dirección en bytes y avanza **16 bytes por bundle** durante la ejecución secuencial. Las direcciones de instrucciones deben estar alineadas a 16 bytes.

## 4. Ensamblador propio

El proyecto de CE4301 incluye un ensamblador autónomo en `python/assembler.py`. Cada línea del archivo fuente representa un bundle y utiliza la sintaxis:

```text
ALU: <instrucción> | LSU: <instrucción> | BRU: <instrucción> | FEIST: <instrucción>
```

Los slots pueden omitirse; el ensamblador los completa automáticamente con NOP. También impide colocar dos instrucciones en el mismo slot.

Ejemplo:

```text
ALU: ADDI x4, x0, 5 | LSU: LOAD x5, 0(x6) | BRU: NOP | FEIST: NOP
```

Para ensamblar un programa:

```bash
python3 python/assembler.py programa.asm -o program_test.mem
```

El archivo de salida puede cargarse directamente en la memoria de instrucciones del procesador.

## 5. Registros y convenciones utilizadas por CE1108

El procesador dispone de 16 registros identificados como `x0` a `x15`.

| Registro | Uso en la integración |
| --- | --- |
| `x0` | Constante cero; las escrituras se descartan. |
| `x1` | PC especial y mecanismo de redirección al escribirse desde ALU o LOAD. |
| `x2` | Valor de retorno de funciones. |
| `x3` | Registro auxiliar del backend. |
| `x4`–`x12` | Temporales utilizados por el código generado. |
| `x13` | Registro auxiliar para direcciones y operaciones internas del backend. |
| `x14` | Stack Pointer (SP). |
| `x15` | Frame Pointer (FP). |

La pila se ubica en la región alta de la memoria de datos y crece hacia direcciones menores. El backend de CE1108 mantiene marcos de activación para funciones, parámetros y variables locales, y restaura `SP` y `FP` al finalizar las llamadas.

## 6. Memoria de datos

La memoria de datos es direccionable por bytes y utiliza palabras de 32 bits en orden *little-endian*.

Las instrucciones LSU son:

```text
LOAD  rd, offset(rb)
STORE rs, offset(rb)
```

El offset se representa con 12 bits con signo. Los accesos de palabra deben estar alineados a **4 bytes** y permanecer dentro del rango válido de la memoria.

La configuración utilizada por el compilador divide lógicamente la memoria en:

```text
0x0000 - 0x7FFF   datos/globales
0x8000 - 0xFFFF   pila
```

## 7. Saltos y control de flujo

Las instrucciones BRU utilizan offsets relativos al **PC del bundle que contiene el salto**.

```text
target = PC_bundle + offset
```

Los offsets se expresan en bytes. Como cada bundle ocupa 16 bytes, todos los destinos generados deben respetar la alineación de 16 bytes.

Los saltos se resuelven en EX. Cuando un salto se toma, el control del pipeline redirige el PC y descarta los bundles más jóvenes mediante *flush*. No existe un *branch delay slot* arquitectónico.

El compilador CE1108 resuelve las etiquetas antes de producir el código de máquina y calcula los offsets definitivos a partir de la posición de cada bundle.

## 8. Calendarización de dependencias

El pipeline implementado es:

```text
IF → ID → RR → EX → WB
```

Una instrucción productora escribe su resultado en WB y las instrucciones consumidoras leen sus operandos en RR. Para una dependencia RAW, el backend utiliza la regla conservadora de que un valor producido en el bundle `B0` puede consumirse de forma segura a partir de `B3`.

```text
B0: productor
B1: operación independiente o NOP
B2: operación independiente o NOP
B3: consumidor
```

Cuando existen operaciones independientes, el compilador puede utilizarlas en los bundles intermedios. De lo contrario, inserta NOP.

La calendarización considera dependencias de:

- registros;
- memoria;
- control de flujo;
- estado de la unidad FEIST y bóveda de llaves;
- escrituras al PC mediante `x1`.

Las operaciones independientes de unidades distintas pueden compartir un mismo bundle. El empaquetador VLIW de CE1108 conserva una sola operación por slot y evita dependencias RAW, WAW y conflictos de control dentro de un paquete.

## 9. Flujo de integración

El flujo completo utilizado es:

```text
Programa de alto nivel CE1108
        ↓
Lexer + Parser + AST
        ↓
Análisis semántico y tabla de símbolos
        ↓
Generación de ensamblador de la ISA
        ↓
Calendarización de dependencias
        ↓
Resolución de etiquetas y offsets
        ↓
Empaquetado VLIW de cuatro slots
        ↓
Codificación hexadecimal de 128 bits
        ↓
$readmemh en instruction_memory.sv
        ↓
Ejecución en top.sv
```

La salida final del compilador contiene una línea hexadecimal de 128 bits por bundle y puede utilizarse directamente como imagen de la memoria de instrucciones.

## 10. Validación conjunta CE1108–CE4301

La integración se validó ejecutando código generado por el compilador CE1108 sobre el procesador VLIW de CE4301. Se utilizaron tres programas con características distintas para comprobar llamadas a funciones, ciclos, saltos, memoria, matrices y operaciones aritméticas.

### 10.1. Factorial

Programa de alto nivel: cálculo de `5!` mediante una función, un ciclo y multiplicación implementada por el backend.

Resultado esperado:

```text
5! = 120
```

Resultado de la simulación:

```text
SELF_LOOP detectado en PC=0x00000F70
PASS: fin_programa alcanzado en 0x00000F70
x2 = 0x00000078 (120)
MEM[0000FFF8] = 00000078 (120)
x14 = 0x00010000
x15 = 0x00010000
```

El valor de retorno fue `120`, el resultado quedó almacenado correctamente en memoria y `SP`/`FP` fueron restaurados al final de la ejecución.

### 10.2. Búsqueda en matriz bidimensional

El programa utiliza una matriz de `2 × 3`:

```text
[[4, 8, 15],
 [16, 23, 42]]
```

y busca el valor `23`.

Resultado esperado:

```text
posición = 4
fila = 1
columna = 1
```

Resultado de la simulación:

```text
SELF_LOOP detectado en PC=0x00001950
PASS: fin_programa alcanzado en 0x00001950
x2 = 0x00000004 (4)
MEM[0000FFE4] = 00000017 (23)
MEM[0000FFE0] = 00000004 (4)
MEM[0000FFDC] = 00000001 (1)
MEM[0000FFD8] = 00000001 (1)
x14 = 0x00010000
x15 = 0x00010000
```

La ejecución confirmó el direccionamiento *row-major* de la matriz, el paso de la matriz por referencia y el cálculo correcto de posición, fila y columna.

### 10.3. Máximo común divisor

El tercer programa calcula el máximo común divisor de `48` y `18` mediante múltiples funciones y el algoritmo de Euclides.

Resultado esperado:

```text
MCD(48, 18) = 6
```

Resultado de la simulación:

```text
SELF_LOOP detectado en PC=0x00002000
PASS: fin_programa alcanzado en 0x00002000
x2 = 0x00000006 (6)
MEM[0000FFEC] = 00000006 (6)
x14 = 0x00010000
x15 = 0x00010000
```

Durante la ejecución se observaron los valores intermedios del algoritmo de Euclides hasta alcanzar el resultado `6`. Al finalizar, la pila y el frame pointer regresaron a su estado inicial.

### 10.4. Resumen de resultados

| Programa | Bundles generados | PC final | Resultado esperado | Resultado observado | Estado |
| --- | ---: | ---: | --- | --- | --- |
| Factorial | 249 | `0x0F70` | `120` | `120` | PASS |
| Búsqueda en matriz | 407 | `0x1950` | posición `4`, fila `1`, columna `1` | posición `4`, fila `1`, columna `1` | PASS |
| MCD | 514 | `0x2000` | `6` | `6` | PASS |

Los tres casos ejecutaron correctamente código generado por CE1108 sobre el procesador VLIW de CE4301. Las pruebas también comprobaron el retorno de funciones, la gestión de pila, las operaciones de memoria y los cambios de flujo generados por el compilador.

## 11. Paralelismo VLIW generado

El empaquetador de CE1108 combina instrucciones independientes de unidades distintas en un mismo bundle. Durante la generación de los programas de prueba se obtuvieron paquetes con combinaciones ALU+LSU, ALU+BRU y LSU+BRU.

Ejemplo de bundle generado para el programa factorial:

```text
ALU: ADDI x5, x0, 0 | LSU: LOAD x4, 8(x15)
HEX: 0000000000000000000023D100000059
```

Otro paquete combina ALU y BRU:

```text
ALU: ADDI x8, x0, 1 | BRU: BGE x4, x0, 64
HEX: 00000000000200220000000000001089
```

Estos casos verifican que la salida del compilador respeta la distribución física de slots y permite expresar paralelismo entre unidades funcionales dentro de un mismo bundle.

## 12. Compatibilidad con la unidad criptográfica

El contrato entregado a CE1108 incluye las instrucciones FEIST:

```text
AUTH
LOGOUT
KSTORE
FROUND
```

`FROUND` procesa una ronda Feistel4 sobre dos mitades de 32 bits. Las cuatro subllaves se almacenan en la bóveda mediante `KSTORE` después de una autenticación válida.

La función de ronda implementada es:

```text
F(x, k) = ((ROL32(x, 5) + k) mod 2^32) XOR ROL32(x, 13)
```

Para cifrado se utilizan las rondas `0 → 1 → 2 → 3`; para descifrado se aplican en orden `3 → 2 → 1 → 0`.

La implementación de CE4301 incluye pruebas de autenticación, almacenamiento de subllaves, acceso autorizado a la bóveda, rondas Feistel, cifrado/descifrado y coexistencia de instrucciones tradicionales y criptográficas.

## 13. Compatibilidad del contrato

La codificación binaria utilizada por CE1108 corresponde a los mismos campos que decodifican los módulos SystemVerilog del procesador. La fuente principal para el contrato ejecutable es la implementación actual de los decodificadores y unidades funcionales, complementada por [`isa.md`](isa.md).

Cualquier cambio futuro en opcodes, campos, distribución de slots o semántica de instrucciones requiere actualizar conjuntamente la especificación de la ISA y el backend del compilador.

## 14. Conclusión

La integración entre CE1108 y CE4301 fue validada de extremo a extremo. El compilador genera bundles de 128 bits compatibles con la memoria de instrucciones del procesador, respeta la calendarización estática y las convenciones acordadas, resuelve correctamente etiquetas y saltos y produce programas que se ejecutan sobre la implementación SystemVerilog con los resultados esperados.

Las pruebas de factorial, búsqueda en matriz y máximo común divisor confirman que la arquitectura puede ejecutar programas generados automáticamente con funciones, pila, memoria, estructuras de control y operaciones aritméticas, completando el contrato de integración ISA–compilador definido para el proyecto.