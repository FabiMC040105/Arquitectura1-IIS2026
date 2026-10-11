# Especificación del ISA — Procesador VLIW Feistel4

**Curso:** CE-4301 Arquitectura de Computadores I  
**Proyecto:** Proyecto Grupal I — Arquitectura VLIW propia para cifrado por bloques  
Documentación técnica de la ISA implementada.  

## 1. Visión general

Se diseñó una arquitectura *Very Long Instruction Word* (VLIW) con **cuatro slots fijos** que permiten expresar operaciones de distintas unidades funcionales dentro de un mismo bundle de **128 bits**. Cada slot contiene una palabra de **32 bits**. El empaquetado y la calendarización de operaciones independientes corresponden al generador de código; el procesador no incorpora resolución dinámica de dependencias de datos.

| Característica | Especificación |
| --- | --- |
| Ancho de bundle | 128 bits (16 bytes) |
| Número de slots | 4, fijos |
| Ancho de cada slot | 32 bits |
| Slot 0 | ALU: aritmética y lógica |
| Slot 1 | LSU: acceso a memoria |
| Slot 2 | BRU: control de flujo |
| Slot 3 | FEIST: autenticación, bóveda de llaves y ronda Feistel4 |
| Ancho de palabra de datos | 32 bits |
| Registros identificables | 16, codificados mediante índices de 4 bits |
| Direccionamiento | 32 bits |
| Memoria de datos del modelo actual | 64 KiB direccionables por byte |
| Memoria de instrucciones del modelo actual | 64 KiB; hasta 4096 bundles de 16 bytes |
| Orden de bytes | Little-endian |

### 1.1. Distribución del bundle

```text
Bit 127                                      Bit 0
+----------------+----------------+----------------+----------------+
| FEIST [127:96] | BRU [95:64]    | LSU [63:32]    | ALU [31:0]     |
|    Slot 3      |    Slot 2      |    Slot 1      |    Slot 0      |
+----------------+----------------+----------------+----------------+
   32 bits          32 bits          32 bits          32 bits
```

El **slot 0 (ALU)** ocupa los bits menos significativos y el **slot 3 (FEIST)** los más significativos. Al expresar un bundle como un valor hexadecimal de 128 bits, el orden visual es `FEIST | BRU | LSU | ALU`, de izquierda a derecha. La serialización en bytes sigue el orden *little-endian* definido para la arquitectura; un archivo `.mem` leído con `$readmemh` puede representar directamente cada bundle completo como una línea de 32 dígitos hexadecimales y **no** requiere invertir sus dígitos por el orden de bytes.

El contador de programa contiene una **dirección en bytes**. En ejecución secuencial avanza **16 bytes** por bundle; en la implementación actual, la memoria de instrucciones requiere direcciones alineadas a 16 bytes.

### 1.2. Slots fijos

Se adoptaron slots dedicados, en lugar de slots flexibles, para simplificar el decodificador y la conexión entre cada subinstrucción y su unidad funcional. Al conocerse la clase de operación por su posición, cada slot necesita únicamente el opcode local de su unidad, y no un campo extra de selección de unidad funcional.

Cada slot puede codificar un **NOP** si no hay una operación lista para ejecutarse en esa unidad. Esto permite empaquetar menos de cuatro operaciones útiles en un bundle sin ejecutar operaciones espurias.

## 2. Registros y convenciones

| Registro | Función |
| --- | --- |
| `x0` | Valor cero constante. Se descartan las escrituras dirigidas a `x0`. |
| `x1` | Registro arquitectónico asociado al *Program Counter* (PC). |
| `x2`–`x15` | Registros de propósito general de 32 bits. |

Los índices requieren 4 bits y por ello permiten nombrar `x0` a `x15`. El código del procesador trata `x1` como un caso especial: su lectura entrega el PC del bundle que realiza la lectura; una escritura a `x1` procedente de las rutas ALU/LOAD redirige el PC, en lugar de almacenarse en el banco de registros. En la ruta FEIST, `x1` no es un destino permitido para los resultados de `FROUND`.

Como `x0` siempre vale cero, es posible construir operaciones equivalentes a ciertos movimientos sin definir opcodes nuevos, por ejemplo `ADD x4, x0, x5` para copiar el contenido de `x5` a `x4`. **No se debe usar `x1` como registro temporal ordinario**, puesto que su escritura tiene efectos sobre el flujo de control.

## 3. Reglas generales de codificación

1. **Cada instrucción ocupa un slot completo de 32 bits**, incluso si solamente utiliza algunos de esos bits para campos significativos.
2. **Todos los bits no asignados a campos de la instrucción son reservados y deben codificarse en cero**; el ensamblador y el compilador deben emitirlos como `0`.
3. Los campos de registros (`rd`, `rs1`, `rs2`, `rb`, `rdL`, `rdR`, `rsL`, `rsR`) se codifican como índices sin signo de 4 bits.
4. Dentro de cada slot, el opcode se encuentra en los bits menos significativos. Su ancho depende del slot: ALU 4 bits, LSU 2 bits, BRU 3 bits y FEIST 3 bits.
5. **NOP canónico:** los 32 bits del slot son `0x00000000`. El opcode cero se reserva a NOP en todas las unidades.
6. Los inmediatos y desplazamientos con signo se codifican en complemento a dos. La interpretación de cada campo se detalla en su formato.



## 4. Hoja de referencia de instrucciones (*instruction reference sheet*)

### 4.1. ALU — Slot 0

El opcode de ALU tiene 4 bits. Su bit 3 diferencia las operaciones con registros (`0`) de las operaciones con inmediato (`1`); los otros tres bits identifican la operación dentro de cada familia.

| Instrucción | Formato | Sintaxis | Opcode (4 bits) | Efecto |
| --- | --- | --- | --- | --- |
| `ADD` | R | `ADD rd, rs1, rs2` | `0001` | `rd ← rs1 + rs2` |
| `SUB` | R | `SUB rd, rs1, rs2` | `0010` | `rd ← rs1 - rs2` |
| `OR` | R | `OR rd, rs1, rs2` | `0011` | `rd ← rs1 OR rs2` |
| `XOR` | R | `XOR rd, rs1, rs2` | `0100` | `rd ← rs1 XOR rs2` |
| `AND` | R | `AND rd, rs1, rs2` | `0101` | `rd ← rs1 AND rs2` |
| `SLT` | R | `SLT rd, rs1, rs2` | `0110` | `rd ← 1` si `rs1 < rs2` con signo; si no, `0` |
| `ADDI` | I | `ADDI rd, rs1, imm` | `1001` | `rd ← rs1 + signo_extendido(imm)` |
| `SRLI` | I | `SRLI rd, rs1, imm` | `1010` | Desplazamiento lógico a la derecha |
| `SLLI` | I | `SLLI rd, rs1, imm` | `1011` | Desplazamiento lógico a la izquierda |
| `NOP` | — | `NOP` | `0000` | Sin operación |

**Formato R (ALU):**

| Bits | Campo | Ancho |
| --- | --- | ---: |
| `[31:16]` | Reservado = 0 | 16 |
| `[15:12]` | `rs2` | 4 |
| `[11:8]` | `rs1` | 4 |
| `[7:4]` | `rd` | 4 |
| `[3:0]` | `opcode` | 4 |

**Formato I (ALU):**

| Bits | Campo | Ancho |
| --- | --- | ---: |
| `[31:24]` | Reservado = 0 | 8 |
| `[23:12]` | `imm` | 12 |
| `[11:8]` | `rs1` | 4 |
| `[7:4]` | `rd` | 4 |
| `[3:0]` | `opcode` | 4 |

`ADDI` emplea un inmediato de 12 bits en complemento a dos, con rango de **−2048 a 2047**, extendido con signo a 32 bits para la operación. Las operaciones aritméticas operan sobre resultados de 32 bits. `SLT` compara sus operandos como enteros con signo.

**Comportamiento de desplazamientos implementado:** `SRLI` y `SLLI` utilizan el valor completo del campo `imm[11:0]` como cantidad de desplazamiento, sin enmascararlo a 4 o 5 bits. Como el operando tiene 32 bits, las cantidades de 0 a 31 producen desplazamientos útiles; para cantidades de 32 o más, el resultado del desplazamiento lógico es cero. 

### 4.2. LSU — Slot 1

| Instrucción | Formato | Sintaxis | Opcode (2 bits) | Efecto |
| --- | --- | --- | --- | --- |
| `LOAD` | L | `LOAD rd, offset(rb)` | `01` | `rd ← MEM32[rb + signo_extendido(offset)]` |
| `STORE` | S | `STORE rs1, offset(rb)` | `10` | `MEM32[rb + signo_extendido(offset)] ← rs1` |
| `NOP` | — | `NOP` | `00` | Sin operación |

**Formato L:**

| Bits | Campo | Ancho |
| --- | --- | ---: |
| `[31:22]` | Reservado = 0 | 10 |
| `[21:10]` | `offset` | 12 |
| `[9:6]` | `rb` | 4 |
| `[5:2]` | `rd` | 4 |
| `[1:0]` | `opcode` | 2 |

**Formato S:** idéntico a L, excepto que `[5:2]` codifica `rs1` (registro cuyo contenido se almacenará), no `rd`.

El desplazamiento tiene 12 bits con signo (**−2048 a 2047**) y se extiende a 32 bits. La dirección efectiva se calcula como `rb + offset`. La memoria de datos implementada es direccionable por bytes y las instrucciones actuales realizan accesos de **32 bits** usando orden *little-endian*: el byte menos significativo se ubica en la dirección más baja. El modelo comprueba que haya espacio para los cuatro bytes completos de cada acceso; no debe documentarse soporte de LOAD/STORE de 8 o 16 bits porque no aparece en los módulos suministrados.

### 4.3. BRU — Slot 2

| Instrucción | Formato | Sintaxis | Opcode (3 bits) | Condición |
| --- | --- | --- | --- | --- |
| `JMP` | J | `JMP offset` | `001` | Salto incondicional |
| `BGE` | B | `BGE rs1, rs2, offset` | `010` | `rs1 ≥ rs2` con signo |
| `BLE` | B | `BLE rs1, rs2, offset` | `011` | `rs1 ≤ rs2` con signo |
| `BEQ` | B | `BEQ rs1, rs2, offset` | `100` | `rs1 = rs2` |
| `BNE` | B | `BNE rs1, rs2, offset` | `101` | `rs1 ≠ rs2` |
| `NOP` | — | `NOP` | `000` | Sin operación |

**Formato B (saltos condicionales):**

| Bits | Campo | Ancho |
| --- | --- | ---: |
| `[31:23]` | Reservado = 0 | 9 |
| `[22:11]` | `offset` | 12 |
| `[10:7]` | `rs2` | 4 |
| `[6:3]` | `rs1` | 4 |
| `[2:0]` | `opcode` | 3 |

**Formato J (salto incondicional):**

| Bits | Campo | Ancho |
| --- | --- | ---: |
| `[31:23]` | Reservado = 0 | 9 |
| `[22:3]` | `offset` | 20 |
| `[2:0]` | `opcode` | 3 |

El desplazamiento B tiene rango **−2048 a 2047 bytes**; el desplazamiento J tiene rango **−524288 a 524287 bytes**. Los dos se extienden con signo a 32 bits y se suman al **PC del bundle que contiene el salto**, no al PC incrementado. El destino debe ser una dirección válida y alineada a 16 bytes para que la memoria de instrucciones implementada pueda leer el siguiente bundle.

En la microarquitectura disponible, la decisión de BRU ocurre en **EX**. Cuando se toma un salto, `pipeline_control` redirige el PC y descarta bundles más jóvenes mediante `flush`. 

### 4.4. FEIST — Slot 3

Este slot incorpora control de acceso a la bóveda, almacenamiento de subllaves y aceleración de una ronda de Feistel4. Tiene opcode local de 3 bits.

| Instrucción | Formato | Sintaxis | Opcode (3 bits) | Efecto |
| --- | --- | --- | --- | --- |
| `AUTH` | FA | `AUTH rs1, rs2` | `001` | Comprueba las credenciales e intenta autorizar operaciones privilegiadas |
| `LOGOUT` | FL | `LOGOUT` | `010` | Desactiva autorización |
| `KSTORE` | FK | `KSTORE key, round, rs1` | `011` | Guarda el contenido de `rs1` como subllave seleccionada |
| `FROUND` | FR | `FROUND rdL, rdR, rsL, rsR, key, round, mode` | `100` | Calcula una ronda Feistel4, con subllave de la bóveda |
| `NOP` | — | `NOP` | `000` | Sin operación |

**Formato FA — AUTH:**

| Bits | Campo | Ancho |
| --- | --- | ---: |
| `[31:11]` | Reservado = 0 | 21 |
| `[10:7]` | `rs2` | 4 |
| `[6:3]` | `rs1` | 4 |
| `[2:0]` | `opcode` | 3 |

**Formato FL — LOGOUT:** `[31:3]` reservado = 0 y `[2:0]` = `010`.

**Formato FK — KSTORE:**

| Bits | Campo | Ancho |
| --- | --- | ---: |
| `[31:11]` | Reservado = 0 | 21 |
| `[10:9]` | `key` | 2 |
| `[8:7]` | `round` | 2 |
| `[6:3]` | `rs1` | 4 |
| `[2:0]` | `opcode` | 3 |

**Formato FR — FROUND (codificación que extrae actualmente `feist_decoder.sv`):**

| Bits | Campo | Ancho |
| --- | --- | ---: |
| `[31:24]` | Reservado = 0 | 8 |
| `[23:20]` | `rdL` | 4 |
| `[19:16]` | `rdR` | 4 |
| `[15:12]` | `rsL` | 4 |
| `[11:8]` | `rsR` | 4 |
| `[7:6]` | `key` | 2 |
| `[5:4]` | `round` | 2 |
| `[3]` | `mode` | 1 |
| `[2:0]` | `opcode` | 3 |

En los campos `key` y `round`, los valores válidos son `0..3`. `mode = 0` solicita cifrado y `mode = 1` solicita descifrado. `rsL` y `rsR` contienen las dos mitades de 32 bits del bloque; `rdL` y `rdR` reciben las mitades resultantes. Una invocación de `FROUND` ejecuta **una ronda**; para completar el algoritmo se requieren cuatro invocaciones, en orden de subllaves ascendente al cifrar y descendente al descifrar.



#### 4.4.1. Operación Feistel4

El algoritmo procesa bloques de 64 bits divididos en `L` y `R` de 32 bits, con una llave de 128 bits separada en cuatro subllaves de 32 bits. La función de ronda es:

```text
F(x, k) = (ROL32(x, 5) + k) XOR ROL32(x, 13)
```

La suma se realiza módulo `2^32`. Las transformaciones por instrucción son:

```text
Cifrado (mode = 0):
    L' = R
    R' = L XOR F(R, subkey)

Descifrado (mode = 1):
    L' = R XOR F(L, subkey)
    R' = L
```


#### 4.4.2. Bóveda de llaves y autorización

La bóveda contiene **4 llaves de 128 bits**, organizadas internamente como `4 × 4` subllaves de 32 bits. `KSTORE` selecciona la llave (`key`) y la subllave (`round`) que recibirá el valor de `rs1`. La bóveda no se mapea como memoria de datos ni expone una ruta para copiar subllaves directamente hacia registros generales. La lectura de una subllave se permite exclusivamente como operando interno de `FROUND`, cuando la autorización está activa.

`AUTH` compara las credenciales suministradas a través de dos registros y controla el estado de autorización; `LOGOUT` lo cancela. Un intento de `KSTORE` o `FROUND` sin autorización provoca una señal de error de acceso en el modelo. 
## 5. Modelo de ejecución y calendarización

El compilador o ensamblador debe construir bundles respetando las dependencias de datos y control y colocando las operaciones en sus slots respectivos. En la implementación estudiada el pipeline contiene las etapas **IF → ID → RR → EX → WB**; aunque varios bundles pueden coexistir en sus distintas etapas, el hardware no incorpora *forwarding* automático, *scoreboarding* ni inserción dinámica de burbujas para solucionar dependencias de datos.

Por ello, el generador de código debe:

- Asignar cada operación al slot adecuado y completar los slots no utilizados con NOP.
- Separar operaciones dependientes mediante bundles/NOP suficientes para que el productor escriba el resultado antes de que el consumidor lo lea en RR.
- Evitar múltiples escrituras arquitectónicas conflictivas al mismo destino dentro de un bundle y respetar el tratamiento especial de `x1`.
- Garantizar que los destinos de salto sean válidos y estén alineados a 16 bytes.
- Gestionar el orden de autorización y almacenamiento de llaves antes de solicitar rondas criptográficas.


## 6. Ejemplos de codificación

**Ejemplo de instrucción R:**

```text
ADD x4, x2, x3
rs2=0011 | rs1=0010 | rd=0100 | opcode=0001
Slot ALU = 0x00003241
```

**Ejemplo de bundle con una única operación ALU:**

```text
FEIST       BRU         LSU         ALU
00000000    00000000    00000000    00003241
```

Línea correspondiente a un archivo hexadecimal de memoria de instrucciones (`$readmemh`):

```text
00000000000000000000000000003241
```

Los otros tres slots no tienen operación útil y por ello son NOP completos. La línea tiene **32 dígitos hexadecimales** que representan 128 bits.

## 7. Correspondencia con módulos SystemVerilog

| Componente del ISA | Módulos descritos en la implementación |
| --- | --- |
| Lectura del bundle | `fetch.sv`, `instruction_memory.sv` |
| División en slots | `dispatch.sv` |
| Operaciones ALU | `alu_decoder.sv`, `alu.sv` |
| Operaciones de memoria | `lsu_decoder.sv`, `lsu.sv`, `data_memory.sv` |
| Saltos | `bru_decoder.sv`, `bru.sv` |
| Operaciones FEIST | `feist_decoder.sv`, `crypto_unit.sv`, `key_vault.sv` |
| Registros y PC | `register_file.sv`, `pipeline_control.sv` |
| Integración | `top.sv`, `pipeline_reg.sv` |





