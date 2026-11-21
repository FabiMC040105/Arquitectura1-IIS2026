# Arquitectura1-IIS2026 — Proyecto Grupal I

## Descripción del proyecto

Proyecto desarrollado para el curso de **Arquitectura de Computadores I (CE4301)** del **Instituto Tecnológico de Costa Rica (TEC)**, correspondiente al segundo semestre de 2026.

Consiste en el diseño e implementación de un procesador **VLIW (Very Long Instruction Word)** con una arquitectura de conjunto de instrucciones (ISA) propia, orientada a la ejecución de operaciones aritméticas, lógicas, de memoria, control de flujo y cifrado por bloques mediante el algoritmo Feistel4.

El procesador está desarrollado en **SystemVerilog**, cuenta con un pipeline de cinco etapas y cuatro unidades funcionales que permiten ejecutar instrucciones independientes en paralelo.

El proyecto se integra con el compilador desarrollado para el curso de Compiladores e Intérpretes, permitiendo ejecutar programas generados para esta arquitectura.

## Características principales

| Característica | Especificación |
|---|---|
| Arquitectura | VLIW de cuatro slots fijos |
| Tamaño de instrucción VLIW | 128 bits |
| Tamaño por slot | 32 bits |
| Pipeline | Cinco etapas |
| Unidades funcionales | ALU, LSU, BRU y FEIST |
| Registros | 16 registros de 32 bits |
| Memoria de instrucciones | 64 KiB |
| Memoria de datos | 64 KiB |
| Bloque Feistel | 64 bits |
| Llave Feistel | 128 bits |
| Lenguaje de implementación | SystemVerilog |

## Arquitectura VLIW

Cada paquete de instrucciones (*bundle*) tiene un tamaño de 128 bits, dividido en cuatro slots de 32 bits.

| Slot | Unidad | Función |
|---|---|---|
| 0 | ALU | Operaciones aritméticas y lógicas |
| 1 | LSU | Operaciones de carga y almacenamiento |
| 2 | BRU | Saltos y control de flujo |
| 3 | FEIST | Autenticación, bóveda de llaves y operaciones criptográficas |

Los slots no utilizados se rellenan con ceros (NOP). Los bits reservados de las instrucciones también se codifican con cero.

El orden de los slots dentro del bundle es:

`FEIST [127:96] | BRU [95:64] | LSU [63:32] | ALU [31:0]`

El contador de programa avanza 16 bytes por paquete durante la ejecución secuencial.

## Pipeline

El procesador implementa un pipeline de cinco etapas:

1. **IF (Instruction Fetch):** obtiene los paquetes desde la memoria de instrucciones.
2. **ID (Instruction Decode):** decodifica las instrucciones de cada slot.
3. **RR (Register Read):** realiza la lectura de operandos.
4. **EX (Execute):** ejecuta las instrucciones en las unidades funcionales.
5. **WB (Write Back):** escribe los resultados en el banco de registros.

Se implementan mecanismos de control para detenciones (*stalls*) y vaciado (*flush*) del pipeline.

La calendarización de instrucciones es estática. El compilador o ensamblador debe respetar las dependencias entre operaciones, ya que el procesador no realiza reordenamiento dinámico ni resolución automática de dependencias de datos.

## Unidad criptográfica Feistel4

La unidad FEIST permite realizar operaciones de cifrado y descifrado sobre bloques de 64 bits, divididos en dos mitades de 32 bits.

Cada llave de 128 bits está formada por cuatro subllaves de 32 bits.

Las instrucciones implementadas incluyen:

- `AUTH`: autenticación para acceder a la bóveda de llaves.
- `KSTORE`: almacenamiento de subllaves.
- `FROUND`: ejecución de una ronda Feistel.
- `LOGOUT`: finalización de la autorización.

El cifrado utiliza cuatro rondas y el descifrado aplica las subllaves en orden inverso.

La bóveda de llaves se implementa mediante `key_vault.sv`, mientras que las operaciones criptográficas son procesadas por `crypto_unit.sv`.

Las credenciales utilizadas en el entorno de simulación tienen fines académicos y no representan un mecanismo de seguridad de producción.

## Tecnologías utilizadas

- SystemVerilog
- Icarus Verilog
- Python 3
- GNU Make
- GTKWave
- Git y GitHub

## Estructura del repositorio

```text
Arquitectura1-IIS2026/
├── Makefile
├── src/
│   ├── top.sv
│   ├── fetch.sv
│   ├── dispatch.sv
│   ├── instruction_memory.sv
│   ├── register_file.sv
│   ├── alu.sv
│   ├── alu_decoder.sv
│   ├── lsu.sv
│   ├── lsu_decoder.sv
│   ├── data_memory.sv
│   ├── bru.sv
│   ├── bru_decoder.sv
│   ├── bru_conexion.sv
│   ├── crypto_unit.sv
│   ├── feist_decoder.sv
│   ├── key_vault.sv
│   ├── pipeline_reg.sv
│   └── pipeline_control.sv
├── tb/
│   └── Testbenches del procesador
├── python/
│   ├── assembler.py
│   ├── generar_prueba.py
│   ├── procesar_archivo_completo.py
│   ├── load_file.py
│   └── extract_data.py
├── docs/
│   ├── isa.md
│   ├── microarchitecture.md
│   ├── simulation.md
│   └── compiler-integration.md
├── pruebas/
├── program_test.mem
├── input.mem
└── prueba_cifrado.asm
```

## Instalación

Se recomienda utilizar Ubuntu o WSL con Ubuntu.

Instalar las dependencias:

```bash
sudo apt update
sudo apt install -y iverilog make python3
```

Para visualizar las señales de simulación:

```bash
sudo apt install -y gtkwave
```

Clonar el repositorio:

```bash
git clone https://github.com/FabiMC040105/Arquitectura1-IIS2026.git
cd Arquitectura1-IIS2026
```

Mientras el proyecto no esté integrado en `main`, se puede acceder a la versión de desarrollo mediante:

```bash
git switch development
```

## Compilación y pruebas

El proyecto dispone de un Makefile para automatizar la elaboración y ejecución de pruebas.

Desde la raíz del repositorio:

```bash
make check
```

Comprueba que los módulos del procesador puedan elaborarse.

```bash
make top
```

Comprueba la elaboración del procesador integrado.

```bash
make test
```

Ejecuta las pruebas principales de Fetch, Dispatch, Top y Feistel.

### Comandos del Makefile

| Comando | Descripción |
|---|---|
| `make` | Ejecuta las pruebas principales |
| `make check` | Comprueba los módulos |
| `make top` | Elabora el procesador |
| `make fetch` | Prueba Fetch |
| `make dispatch` | Prueba Dispatch |
| `make tb_top` | Prueba la integración del procesador |
| `make feistel` | Prueba la unidad Feistel |
| `make test` | Ejecuta las pruebas principales |
| `make clean` | Elimina ejecutables de simulación |

La carpeta `tb/` también incluye pruebas adicionales para las unidades funcionales, las memorias, el pipeline, los saltos y la ejecución paralela de instrucciones VLIW.

## Ensamblador propio

El proyecto incorpora un ensamblador independiente implementado en Python, capaz de traducir instrucciones de la ISA a código hexadecimal compatible con la memoria de instrucciones.

Ejemplo de uso:

```bash
python3 python/assembler.py prueba_cifrado.asm -o ejemplo.mem
```

El archivo generado contiene un paquete de 128 bits por línea, representado mediante 32 dígitos hexadecimales.

El contenido puede cargarse directamente en la memoria de instrucciones mediante `$readmemh`.

## Cifrado y descifrado de archivos

El proyecto incluye una herramienta que permite cifrar y descifrar archivos de diferentes formatos mediante la simulación del procesador VLIW.

La herramienta prepara los datos y las instrucciones en Python, pero el procesamiento Feistel se ejecuta en el hardware simulado con SystemVerilog.

Para probar el proceso completo:

```bash
printf 'Hola TEC\n' > ejemplo.txt
python3 python/procesar_archivo_completo.py ejemplo.txt
```

Para realizar solamente el cifrado:

```bash
python3 python/procesar_archivo_completo.py cifrar ejemplo.txt
```

Para descifrar:

```bash
python3 python/procesar_archivo_completo.py descifrar ejemplo.txt.cifrado.bin
```

El proceso permite:

- Dividir los archivos en bloques de 8 bytes.
- Preparar los datos para la memoria simulada.
- Generar las instrucciones de cifrado o descifrado.
- Ejecutar el procesamiento en el simulador.
- Reconstruir los archivos recuperados.
- Verificar la integridad mediante SHA-256.
- Comparar el archivo original y el recuperado.

El formato de salida cifrado utiliza un contenedor propio con extensión `.cifrado.bin`. Esta herramienta tiene fines demostrativos y no debe utilizarse para proteger información sensible.

## Visualización de señales

Algunos testbenches generan archivos `.vcd`, que pueden abrirse mediante GTKWave.

Ejemplo:

```bash
gtkwave nombre_de_la_traza.vcd
```

Esto permite observar señales internas como el PC, instrucciones, registros, etapas del pipeline y resultados de las unidades funcionales, dependiendo del testbench utilizado.

## Integración con Compiladores e Intérpretes

El proyecto está relacionado con el compilador desarrollado para el curso de Compiladores e Intérpretes (CE1108).

El compilador genera código compatible con la ISA del procesador, respetando:

- Los cuatro slots fijos de 32 bits.
- El formato VLIW de 128 bits.
- La codificación de las instrucciones.
- Las convenciones del banco de registros.
- Las dependencias de datos y control.
- La calendarización de instrucciones.
- La inserción de NOP cuando corresponde.
- La resolución de saltos y direcciones.

Esta integración permite que programas escritos en el lenguaje del compilador se traduzcan a instrucciones ejecutables en la arquitectura simulada.

Repositorio del compilador:

[CompiladoresIIS2026](https://github.com/FabiMC040105/CompiladoresIIS2026)

## Documentación técnica

Para información detallada sobre los componentes y su funcionamiento, consultar:

- [Especificación de la ISA](docs/isa.md)
- [Microarquitectura y pipeline](docs/microarchitecture.md)
- [Simulación y testbenches](docs/simulation.md)
- [Integración con el compilador](docs/compiler-integration.md)

## Licencia

Consultar el archivo [LICENSE](LICENSE) del repositorio.

---

**Instituto Tecnológico de Costa Rica (TEC)**

**CE4301 — Arquitectura de Computadores I**

**Proyecto Grupal I — II Semestre 2026**
