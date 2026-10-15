# Simulación y validación del procesador VLIW Feistel4

**Curso:** CE-4301 Arquitectura de Computadores I  
**Proyecto:** Proyecto Grupal I — Arquitectura VLIW propia para aplicaciones de cifrado por bloques  
**Documento:** `docs/simulation.md`  
**Fuentes:** especificación oficial del proyecto y módulos, Makefile y testbenches del material de implementación compartido.  
**Alcance:** este documento describe el modelo y las pruebas presentes en el material revisado. La existencia de un testbench **no equivale a una ejecución verificada**; los resultados y archivos de evidencia deben obtenerse ejecutando la versión final del repositorio.

## 1. Objetivo y enfoque de validación

El procesador se modela mediante módulos **SystemVerilog** y se evalúa a nivel de simulación, sin necesidad de implementarlo en una FPGA. La herramienta principal contemplada en el Makefile es **Icarus Verilog**, con `iverilog` para compilación y elaboración y `vvp` para ejecutar la simulación. La especificación oficial también permite utilizar Verilator.

La validación se organiza en tres niveles:

1. **Pruebas unitarias:** comprueban módulos individuales, como decodificadores, unidades funcionales, memorias y control de pipeline.
2. **Pruebas de integración entre módulos:** comprueban conexiones como LSU + memoria de datos, BRU + decodificador y bóveda + unidad criptográfica.
3. **Pruebas del procesador integrado:** comprueban el recorrido de bundles por el pipeline, la escritura de resultados y la ejecución de instrucciones FEIST en el procesador completo.

El comportamiento del modelo y las instrucciones soportadas se detallan en [`isa.md`](isa.md); la estructura de etapas y señales se describe en [`microarchitecture.md`](microarchitecture.md).

## 2. Entorno de simulación

### 2.1. Herramientas

| Herramienta | Función | Estado en el material |
| --- | --- | --- |
| Icarus Verilog (`iverilog`) | Compilar y elaborar SystemVerilog | Utilizado en el Makefile con `-g2012 -Wall` |
| VVP (`vvp`) | Ejecutar los testbenches compilados | Utilizado en el Makefile |
| GNU Make (`make`) | Automatizar compilación y ejecución | Se incluye un Makefile con objetivos de prueba |
| GTKWave | Inspeccionar formas de onda `.vcd` | Compatible con los volcados que generan varios testbenches |
| Verilator | Alternativa aceptada por el enunciado | No se identifica una configuración de Verilator en el Makefile proporcionado |

La opción `-g2012` habilita las construcciones de SystemVerilog 2012 utilizadas en el proyecto; `-Wall` solicita advertencias durante la compilación. El Makefile requiere un entorno que entienda las recetas de shell que contiene. **En Windows CMD, GNU Make por sí solo puede no bastar**, porque el objetivo `check-modules` utiliza comandos de shell tipo Unix y `clean` utiliza `rm`. Para esos objetivos se recomienda ejecutar `make` dentro de WSL o de un entorno con shell compatible, siempre que estén instaladas las dependencias.

Desde **CMD de Windows**, situado en la raíz del repositorio, y con las herramientas instaladas dentro de WSL, puede invocarse:

```cmd
wsl make check
wsl make test
```

Si `make` e `iverilog` ya funcionan en el shell que se está utilizando, se pueden ejecutar directamente `make check` y `make test` sin el prefijo `wsl`.

### 2.2. Organización utilizada por el Makefile

El Makefile declara una lista `SRC` que comprende, entre otros, los siguientes archivos:

```text
src/
├── top.sv
├── fetch.sv
├── instruction_memory.sv
├── dispatch.sv
├── register_file.sv
├── alu.sv
├── alu_decoder.sv
├── lsu.sv
├── lsu_decoder.sv
├── data_memory.sv
├── bru.sv
├── bru_decoder.sv
├── bru_conexion.sv
├── crypto_unit.sv
├── feist_decoder.sv
├── key_vault.sv
├── pipeline_reg.sv
└── pipeline_control.sv
```

Los testbenches se referencian dentro del directorio `tb/`. Además, las memorias de prueba y los archivos `.mem` se leen en función de las rutas utilizadas al ejecutar cada simulación. En particular, las rutas relativas de `$readmemh` deben resolverse desde el directorio de trabajo de la ejecución.

## 3. Modelo funcional del procesador

### 3.1. Ejecución de bundles

La memoria de instrucciones almacena bundles de **128 bits**, cada uno dividido en cuatro slots fijos de 32 bits. `fetch` recupera un bundle de acuerdo con el PC y `dispatch` separa sus slots ALU, LSU, BRU y FEIST.

El pipeline está organizado como **IF → ID → RR → EX → WB**. Las etapas están conectadas mediante registros `pipeline_reg`, que transportan tanto datos y señales de control como indicadores de validez. La lectura de operandos ocurre en RR y las cuatro unidades se pueden ejecutar en paralelo durante EX.

En avance secuencial, el PC se incrementa **16 bytes** por bundle. `pipeline_control` puede detener las etapas mediante `stall_i`, o invalidar bundles con señales `flush` cuando existe una redirección del flujo de control. La arquitectura utiliza **calendarización estática**: no se implementa detección dinámica de dependencias RAW ni forwarding automático para corregir programas mal calendarizados. Quien produce el código debe organizar los bundles e insertar NOP cuando corresponda.

### 3.2. Banco de registros

`register_file.sv` modela 16 registros de 32 bits con lectura combinacional y escritura en flanco positivo. La configuración que utiliza `top.sv` dispone de **ocho puertos de lectura y cuatro de escritura**, lo que permite atender las unidades funcionales en la etapa RR y los resultados en WB.

- `x0` siempre se lee como cero y descarta escrituras.
- `x1` representa arquitectónicamente el PC. En `top.sv`, su lectura se sustituye por el PC del bundle; las escrituras a `x1` provenientes de ALU o LOAD redirigen el PC.
- Los demás registros se utilizan para operandos y resultados ordinarios.

La prueba integrada debe tener en cuenta que un resultado producido en EX **no aparece inmediatamente** en el banco de registros: se transfiere mediante `EX/WB` y se escribe en WB.

### 3.3. Memoria de instrucciones

`instruction_memory.sv` implementa, por defecto, una capacidad de **65536 bytes (64 KiB)** con posiciones de 128 bits. Inicializa los bundles en cero y carga un programa en formato hexadecimal por medio de:

```systemverilog
$readmemh(PROGRAM_FILE, memory);
```

En este formato, **cada línea representa un bundle completo de 128 bits**, es decir, 32 dígitos hexadecimales, y se organiza como:

```text
| FEIST (32 bits) | BRU (32 bits) | LSU (32 bits) | ALU (32 bits) |
|    [127:96]    |   [95:64]     |   [63:32]     |    [31:0]    |
```

La dirección del PC está expresada en bytes. `instruction_memory` requiere **alineación a 16 bytes** y verifica que el bundle completo se encuentre dentro del rango de memoria. Una dirección inválida activa `access_error`, y `fetch` marca inválida la salida. Un bundle de cuatro NOP permanece válido si su dirección es correcta.

El parámetro `PROGRAM_FILE` aparece con valor predeterminado `"program.mem"` en `fetch.sv` y `top.sv`; `instruction_memory.sv` declara `"program_test.mem"` como predeterminado cuando se instancia directamente. `fetch` pasa explícitamente su propio parámetro al módulo de memoria. Por tanto, **el archivo a utilizar depende del módulo principal y de los parámetros de la prueba**.

El material incluye un ejemplo `program_test.mem` con cuatro bundles hexadecimales de 128 bits destinados a ejercitar la separación de slots; no debe confundirse ese archivo de prueba con un programa ensamblado de aplicación.

### 3.4. Memoria de datos y LSU

`data_memory.sv` utiliza **65536 bytes**, direccionables individualmente, inicializados en cero en la simulación. Los accesos implementados son de **palabra de 32 bits**:

- **STORE:** escritura síncrona en el flanco positivo de los cuatro bytes.
- **LOAD:** lectura combinacional de los cuatro bytes.
- **Little-endian:** el byte menos significativo se almacena en la dirección menor.
- **Rango:** una operación de memoria señala `access_error` cuando no caben los cuatro bytes a partir de la dirección indicada.

Por ejemplo, almacenar `0x12345678` en la dirección `A` produce la siguiente distribución:

| Dirección | Byte |
| --- | --- |
| `A` | `0x78` |
| `A + 1` | `0x56` |
| `A + 2` | `0x34` |
| `A + 3` | `0x12` |

`lsu.sv` recibe una dirección base, un desplazamiento inmediato de 12 bits y el dato que se desea almacenar. Extiende el desplazamiento con signo a 32 bits y calcula la **dirección efectiva = base + offset**. `lsu_decoder.sv` identifica LOAD, STORE, NOP y codificaciones ilegales, además de generar las señales de control. La memoria de datos proporcionada **no incorpora una verificación de alineación a cuatro bytes**: el control mostrado verifica el rango de acceso.

### 3.5. Unidad criptográfica y bóveda

`key_vault.sv` modela cuatro llaves de 128 bits como 16 subllaves de 32 bits, organizadas por índice de llave y ronda. Mantiene el estado `authorized` y controla las instrucciones AUTH, LOGOUT, KSTORE y el suministro de subllave para FROUND. En la implementación compartida, las credenciales de prueba están definidas como constantes dentro del módulo; se trata de un **modelo educativo**, no de un sistema de credenciales seguro para producción.

`crypto_unit.sv` recibe las mitades izquierda y derecha de 32 bits, la subllave enviada por la bóveda y el modo de operación. Calcula una ronda usando:

```text
F(x, k) = ((ROL32(x, 5) + k) mod 2^32) XOR ROL32(x, 13)
```

En cifrado produce `L' = R` y `R' = L XOR F(R, k)`. En descifrado emplea el cálculo inverso de la ronda con las subllaves en orden inverso. La unidad solo considera válido el resultado cuando la bóveda autoriza el suministro de la subllave. El camino de lectura de llaves se conecta **directamente** entre bóveda y unidad criptográfica, sin una salida destinada al banco de registros generales.

## 4. Compilación y ejecución mediante Makefile

El Makefile entregado en el material define los siguientes objetivos:

| Objetivo | Acción descrita por el Makefile |
| --- | --- |
| `make check` | Ejecuta `check-modules`, que intenta elaborar por separado los módulos listados. |
| `make top` | Elabora `top` con sus dependencias, sin ejecutar un testbench. |
| `make fetch` | Compila y ejecuta `tb_fetch` junto a `fetch` e `instruction_memory`. |
| `make dispatch` | Compila y ejecuta `tb_dispatch` con `dispatch`. |
| `make tb_top` | Compila y ejecuta `tb_top` utilizando la lista `SRC`. |
| `make feistel` | Compila y ejecuta `tb_feistel` utilizando la lista `SRC`. |
| `make test` | Ejecuta los objetivos `fetch`, `dispatch`, `tb_top` y `feistel`. |
| `make` | Invoca el objetivo predeterminado `all`, definido como `test`. |
| `make clean` | Elimina los ejecutables de simulación nombrados en el Makefile. |

La compilación está configurada con las banderas:

```makefile
FLAGS = -g2012 -Wall
```

Ejemplo de flujo desde la raíz del repositorio, **en WSL o un shell compatible**, con las dependencias instaladas:

```bash
make check
make top
make test
```

El primer comando comprueba elaboración de módulos; el segundo comprueba la instancia principal, y el tercero ejecuta las cuatro pruebas conectadas al objetivo general. **`make check` no está incluido automáticamente en `make test`.**

El material consolidado compartido incluye el cuerpo de numerosos testbenches, pero **no permite confirmar la presencia del archivo `tb/tb_fetch.sv`**, aunque el Makefile sí lo referencia. Asimismo, contiene **dos versiones de `tb_top`**; para reproducir la ejecución se debe utilizar el único `tb/tb_top.sv` que esté efectivamente versionado en el repositorio final. Esto es una observación sobre el material recibido, no una afirmación de que el repositorio de trabajo carezca necesariamente de esos archivos.

### 4.1. Ejemplo de ejecución de una prueba independiente desde CMD

Si Icarus Verilog está disponible directamente en Windows, desde CMD y situado en la raíz del proyecto se puede ejecutar el test de memoria de datos sin Make:

```cmd
iverilog -g2012 -Wall -s data_memory_tb -o sim_data_memory.vvp src\data_memory.sv tb\data_memory_tb.sv
vvp sim_data_memory.vvp
```

Para las pruebas que involucran varios módulos es necesario pasar al compilador **todos los archivos SystemVerilog dependientes**. Los nombres y rutas deben corresponder a la estructura real del repositorio.

## 5. Inventario de testbenches incluidos en el material

La siguiente tabla distingue las pruebas **encontradas en el documento de módulos** de aquellas realmente conectadas al Makefile. Las pruebas de la tabla son casos programados; no se atribuye aquí un resultado `PASS` de ejecución real.

| Testbench (módulo principal) | Aspectos comprobados por el código de prueba | `make test` |
| --- | --- | --- |
| `tb_dispatch` | Separación de los cuatro slots, propagación del PC, validez por slot y bundles NOP o inválidos. | Sí |
| `tb_top` | Pipeline integrado, avance y pausa del PC, escritura en WB, inmutabilidad de `x0` y separación de slots; considerar la versión final del archivo. | Sí |
| `tb_feistel` | Instrucciones AUTH, KSTORE, FROUND y LOGOUT dentro de `top`; prueba de una ronda frente a una función de referencia y restricciones de acceso. | Sí |
| `tb_bru` | NOP, JMP, comparaciones BGE/BLE/BEQ/BNE, offsets positivos/negativos y casos de opcode reservado. | No |
| `tb_bru_decoder` | Extracción de campos BRU, extensión de signo y detección de codificaciones inválidas. | No |
| `tb_bru_conexion` | Integración de decodificador BRU con ejecución de saltos. | No |
| `lsu_tb` | Dirección efectiva, offsets con signo, señales LOAD/STORE y operación inactiva. | No |
| `lsu_decoder_tb` | Campos de LOAD/STORE, NOP, opcodes ilegales y bits reservados. | No |
| `data_memory_tb` | LOAD/STORE de 32 bits, orden little-endian, sobrescrituras y accesos fuera de rango. | No |
| `lsu_integration_tb` | Integración LSU + decodificador + memoria, lectura, escritura, offset negativo y NOP. | No |
| `instruction_memory_tb` | Lectura de bundles, separación de slots, alineación y límites de memoria. | No |
| `tb_crypto_unit` | Ronda Feistel con subllave válida o inválida, cifrado/descifrado y manejo de errores. | No |
| `tb_key_vault` | Reset, autorización correcta/incorrecta, KSTORE autorizado/no autorizado, suministro FROUND y LOGOUT. | No |
| `tb_crypto_integracion` | Cuatro subllaves; cifrado de cuatro rondas, descifrado inverso, recuperación del bloque original y rechazo de acceso no autorizado. | No |
| `tb_feist_decoder` | NOP, AUTH, LOGOUT, KSTORE, FROUND, selección de llave/ronda/modo y opcode ilegal. | No |
| `tb_pipeline_control` | `PC + 16`, stall, saltos, prioridad de redirecciones, flush y reset. | No |
| `tb_pipeline_reg` | Reset, flush, enable, conservación de datos y propagación de validez. | No |

**Nota sobre `tb_fetch`:** aparece en el Makefile y es requerido por el objetivo `make fetch`, pero su cuerpo no se identifica en el material de módulos proporcionado. Debe comprobarse directamente en `tb/` antes de registrar qué casos cubre y cuál fue su resultado.

### 5.1. Validación del cifrado de cuatro rondas

Es importante **no confundir dos niveles de prueba**:

- `tb_feistel` ejerce la ruta **integrada en el procesador `top`** para una instrucción FROUND, además de autenticación, almacenamiento de llave, cierre de sesión y rechazo de accesos ilegales.
- `tb_crypto_integracion` comprueba un **bloque completo de 64 bits a través de cuatro rondas de cifrado y cuatro rondas inversas de descifrado**, conectando directamente `key_vault` y `crypto_unit`. La prueba utiliza el bloque formado por `HOLA` + `1234` y verifica la recuperación de los valores originales.

El segundo testbench valida el cálculo criptográfico completo a nivel de subsistema, pero **no equivale por sí mismo** a demostrar que un programa de cifrado de archivos se ejecuta íntegramente en `top`, lee datos desde la memoria del procesador y guarda el resultado nuevamente en memoria.

### 5.2. Detección de fallos y códigos de salida

Algunos testbenches usan `$fatal(1, ...)` cuando falla una comprobación. Esta forma permite señalar un error a la herramienta de simulación y automatizar un fallo del objetivo correspondiente.

Otros testbenches del material —por ejemplo, `data_memory_tb`, `lsu_tb`, `lsu_decoder_tb` y `lsu_integration_tb`— muestran resultados con mensajes `TEST PASS` / `TEST FAIL` y finalizan con `$finish`, sin convertir necesariamente los fallos en un código de salida distinto de cero. En esas pruebas, **un proceso que termina normalmente no demuestra por sí mismo que todas las comprobaciones pasaron**. Debe revisarse su salida o mejorar el testbench para llamar a `$fatal` al detectar una diferencia.

## 6. Archivos VCD e inspección con GTKWave

Diversos testbenches incorporan llamadas a:

```systemverilog
$dumpfile("nombre_de_prueba.vcd");
$dumpvars(0, nombre_del_testbench);
```

Estos comandos generan una traza VCD durante la simulación. El archivo se puede inspeccionar con GTKWave, por ejemplo:

```bash
gtkwave tb_key_vault.vcd
```

Los nombres de trazas identificados en el material incluyen `data_memory.vcd`, `lsu.vcd`, `lsu_decoder.vcd`, `lsu_integration.vcd`, `instruction_memory.vcd`, `tb_bru.vcd`, `tb_bru_decoder.vcd`, `bru_conexion.vcd`, `tb_key_vault.vcd`, `tb_crypto_unit.vcd`, `tb_crypto_integracion.vcd`, `tb_feist_decoder.vcd`, `pipeline_reg.vcd` y `pipeline_control.vcd`.

**No se identifica una llamada a `$dumpfile` en las versiones proporcionadas de `tb_dispatch`, `tb_top` y `tb_feistel`**. Por ello, no debe afirmarse que esas tres pruebas producen una traza VCD hasta verificar el código final o añadir explícitamente el volcado. Para cumplir plenamente el requisito del enunciado sobre visualización de las simulaciones, conviene habilitar trazas también en las pruebas de integración finales.

Se recomienda observar, según corresponda:

- `pc_o`, `bundle_o`, validez de cada slot y controles `enable`/`flush` de pipeline.
- Señales de lectura/escritura y dirección efectiva de LSU y memoria.
- `branch_taken` y `branch_target` de BRU.
- `authorized`, `access_error`, `subkey_valid`, `result_valid` y entradas/salidas de FROUND.
- Registros de destino y sus valores al llegar a WB.

## 7. Registro reproducible de resultados

Para la entrega final, la evidencia debe corresponder **al mismo commit** que se presentará en la defensa. La siguiente tabla es una plantilla para completar después de ejecutar la versión final en el equipo del grupo; se deja deliberadamente sin resultados supuestos.

| Comando o prueba | Resultado real | Evidencia |
| --- | --- | --- |
| `make check` | Pendiente de registrar | Log de compilación |
| `make top` | Pendiente de registrar | Log de elaboración |
| `make test` | Pendiente de registrar | Log de ejecución |
| `data_memory_tb` | Pendiente de registrar | Consola y `data_memory.vcd` |
| `lsu_integration_tb` | Pendiente de registrar | Consola y `lsu_integration.vcd` |
| `tb_crypto_integracion` | Pendiente de registrar | Consola y `tb_crypto_integracion.vcd` |
| Cifrado/descifrado desde un archivo real | Pendiente de demostrar | Archivo original, cifrado, recuperado y comparación |
| Programa producido por el compilador CE1108 | Pendiente de demostrar | Binario/bundles, ejecución y resultado |

Para archivar evidencia, se recomienda conservar el comando ejecutado, la versión del código, la salida completa del testbench y —cuando se generen— las trazas VCD. Al interpretar los resultados, también se debe comprobar que el testbench no haya emitido mensajes `FAIL` ignorados.

## 8. Carga y extracción de archivos de datos reales

La especificación oficial exige una herramienta capaz de:

1. Leer archivos genéricos como texto, imágenes o binarios.
2. Convertir sus bytes a un archivo de inicialización de memoria (por ejemplo, `.mem`).
3. Seleccionar la dirección inicial de carga y reportar el tamaño/rango ocupado.
4. Extraer los bytes cifrados o descifrados de un volcado de memoria y reconstruir un archivo de salida.
5. Comparar el archivo original con el recuperado tras cifrar y descifrar.

**En el material de implementación revisado no se identifica aún el código de una herramienta de carga/extracción ni del ensamblador propio.** Por tanto, no se presenta ninguna interfaz de comandos como si ya estuviera disponible. La memoria de datos mostrada en `data_memory.sv` se inicializa en cero; su implementación proporcionada no incluye por sí misma una carga de archivos mediante `$readmemh`. La integración de la utilidad de archivos con el modelo de memoria deberá documentarse con los programas y comandos **reales** cuando esos componentes estén disponibles en el repositorio.

Una validación completa sobre un archivo real debería demostrar, al menos:

```text
Archivo original
   ↓ herramienta de carga
Bytes disponibles en memoria de datos
   ↓ ejecución de cuatro rondas Feistel4 por bloque
Datos cifrados
   ↓ ejecución de descifrado con subllaves inversas
Datos recuperados
   ↓ herramienta de extracción
Archivo reconstruido y comparación con el original
```

El tratamiento de archivos cuyo tamaño no sea múltiplo de **8 bytes** debe definirse y registrarse para poder recuperar exactamente la longitud original. Esta es una **consideración pendiente de la herramienta de archivos**, no una función de padding que se haya identificado en los módulos actuales. Asimismo, el padding de archivos no debe confundirse con la regla del ISA que exige codificar los **bits reservados de las instrucciones en cero**.

## 9. Alcance de las pruebas y verificaciones pendientes

De acuerdo con el enunciado oficial, la validación final debe demostrar operaciones tradicionales y criptográficas coexistiendo en los mismos bundles, ejecución de las cuatro rondas Feistel4, protección de las llaves, funcionamiento sobre archivos reales y ejecución de al menos un programa producido por el compilador de CE1108.

El material revisado **sí describe** módulos de ALU, LSU, BRU, FEIST, bóveda, pipeline e integración; también incluye testbenches para una parte considerable de esos comportamientos. Sin embargo, para dar por cumplidos todos los requisitos aún se necesita confirmar con el repositorio y las ejecuciones finales:

- La disponibilidad y ejecución efectiva de todos los testbenches referenciados por el Makefile, especialmente `tb_fetch.sv`, y cuál es la versión vigente de `tb_top.sv`.
- La ausencia de errores de compilación y simulación después de integrar todos los módulos.
- Evidencia de bundles mixtos que combinen **en paralelo** operaciones ALU, memoria, control de flujo y criptografía según la calendarización elegida.
- Evidencia de cifrado y descifrado completo mediante un **programa VLIW ejecutado en `top`**, además de la prueba aislada de cuatro rondas del subsistema criptográfico.
- La herramienta de carga y extracción de archivos, el ensamblador propio y sus ejemplos reproducibles.
- La ejecución conjunta con el compilador de CE1108, cuya interfaz debe explicarse en [`compiler-integration.md`](compiler-integration.md).
- La producción de trazas de las pruebas finales y un registro concreto de resultados comprobables.

**Criterio de cierre:** actualizar las secciones de resultados únicamente con salidas obtenidas del código final y conservar evidencia suficiente para reproducirlas durante la defensa.
