#!/usr/bin/env python3

import argparse
import re
from pathlib import Path


# Convertir un registro como x2 en su número correspondiente.
def registro(texto):
    texto = texto.strip().lower()

    if not re.fullmatch(r"x\d+", texto):
        raise ValueError(f"Registro inválido: {texto}")

    numero = int(texto[1:])

    if numero < 0 or numero > 15:
        raise ValueError(f"El registro {texto} está fuera del rango x0-x15.")

    return numero


# Leer un número decimal o hexadecimal.
def numero(texto):
    texto = texto.strip().lower()

    try:
        return int(texto, 0)
    except ValueError:
        # int(..., 0) no interpreta números como 05 en algunas versiones.
        if re.fullmatch(r"[+-]?\d+", texto):
            return int(texto, 10)

        raise ValueError(f"Número inválido: {texto}")


# Comprobar que un inmediato cabe en la cantidad de bits indicada.
def inmediato(texto, bits):
    valor = numero(texto)
    minimo = -(1 << (bits - 1))
    maximo = (1 << (bits - 1)) - 1

    if valor < minimo or valor > maximo:
        raise ValueError(
            f"El inmediato {valor} no cabe en {bits} bits con signo."
        )

    # Representación en complemento a dos.
    return valor & ((1 << bits) - 1)


# Separar los operandos de una instrucción.
def operandos(texto):
    if not texto.strip():
        return []

    return [parte.strip() for parte in texto.split(",")]


# Comprobar la cantidad de operandos.
def comprobar_cantidad(nombre, args, cantidad):
    if len(args) != cantidad:
        raise ValueError(
            f"{nombre} necesita {cantidad} operandos; se recibieron {len(args)}."
        )


# Codificar una instrucción del slot ALU.
def codificar_alu(texto):
    partes = texto.strip().upper().split(None, 1)

    if not partes:
        raise ValueError("Falta la instrucción ALU.")

    nombre = partes[0]
    args = operandos(partes[1] if len(partes) > 1 else "")

    # Un NOP se representa con todos sus bits en cero.
    if nombre == "NOP":
        comprobar_cantidad(nombre, args, 0)
        return 0

    # Opcode de tres bits que utiliza alu_decoder.
    opcodes_registro = {
        "ADD": 0b001,
        "SUB": 0b010,
        "OR":  0b011,
        "XOR": 0b100,
        "AND": 0b101,
        "SLT": 0b110,
    }

    opcodes_inmediato = {
        "ADDI": 0b001,
        "SRLI": 0b010,
        "SLLI": 0b011,
    }

    if nombre in opcodes_registro:
        comprobar_cantidad(nombre, args, 3)

        rd = registro(args[0])
        rs1 = registro(args[1])
        rs2 = registro(args[2])
        opcode = opcodes_registro[nombre]

        # Formato R:
        # [15:12] rs2, [11:8] rs1, [7:4] rd, [2:0] opcode.
        return (
            (rs2 << 12)
            | (rs1 << 8)
            | (rd << 4)
            | opcode
        )

    if nombre in opcodes_inmediato:
        comprobar_cantidad(nombre, args, 3)

        rd = registro(args[0])
        rs1 = registro(args[1])
        imm = inmediato(args[2], 12)
        opcode = opcodes_inmediato[nombre]

        # Formato I:
        # [23:12] inmediato, [11:8] rs1, [7:4] rd,
        # [3] indica inmediato y [2:0] contiene el opcode.
        return (
            (imm << 12)
            | (rs1 << 8)
            | (rd << 4)
            | (1 << 3)
            | opcode
        )

    raise ValueError(f"Instrucción ALU desconocida: {nombre}")


# Codificar una instrucción del slot LSU.
def codificar_lsu(texto):
    partes = texto.strip().upper().split(None, 1)

    if not partes:
        raise ValueError("Falta la instrucción LSU.")

    nombre = partes[0]
    args = operandos(partes[1] if len(partes) > 1 else "")

    if nombre == "NOP":
        comprobar_cantidad(nombre, args, 0)
        return 0

    if nombre not in ("LOAD", "STORE"):
        raise ValueError(f"Instrucción LSU desconocida: {nombre}")

    comprobar_cantidad(nombre, args, 2)

    # La dirección se escribe como offset(xRegistro).
    coincidencia = re.fullmatch(
        r"\s*([+-]?(?:0[xX][0-9a-fA-F]+|\d+))\s*"
        r"\(\s*(x\d+)\s*\)\s*",
        args[1],
        re.IGNORECASE
    )

    if coincidencia is None:
        raise ValueError(
            f"Dirección inválida: {args[1]}. "
            "Utiliza el formato offset(xRegistro)."
        )

    offset = inmediato(coincidencia.group(1), 12)
    rb = registro(coincidencia.group(2))
    rd_o_rs1 = registro(args[0])

    # Formato LSU:
    # [21:10] offset, [9:6] rb, [5:2] registro, [1:0] opcode.
    if nombre == "LOAD":
        opcode = 0b01
    else:
        opcode = 0b10

    return (
        (offset << 10)
        | (rb << 6)
        | (rd_o_rs1 << 2)
        | opcode
    )


# Codificar una instrucción del slot BRU.
def codificar_bru(texto):
    partes = texto.strip().upper().split(None, 1)

    if not partes:
        raise ValueError("Falta la instrucción BRU.")

    nombre = partes[0]
    args = operandos(partes[1] if len(partes) > 1 else "")

    if nombre == "NOP":
        comprobar_cantidad(nombre, args, 0)
        return 0

    # JMP utiliza un offset con signo de 20 bits.
    if nombre == "JMP":
        comprobar_cantidad(nombre, args, 1)
        offset = inmediato(args[0], 20)

        # Formato J:
        # [22:3] offset y [2:0] opcode.
        return (offset << 3) | 0b001

    opcodes = {
        "BGE": 0b010,
        "BLE": 0b011,
        "BEQ": 0b100,
        "BNE": 0b101,
    }

    if nombre in opcodes:
        comprobar_cantidad(nombre, args, 3)

        rs1 = registro(args[0])
        rs2 = registro(args[1])
        offset = inmediato(args[2], 12)

        # Formato condicional:
        # [22:11] offset, [10:7] rs2, [6:3] rs1,
        # [2:0] opcode.
        return (
            (offset << 11)
            | (rs2 << 7)
            | (rs1 << 3)
            | opcodes[nombre]
        )

    raise ValueError(f"Instrucción BRU desconocida: {nombre}")


# Codificar una instrucción del slot FEIST.
def codificar_feist(texto):
    partes = texto.strip().upper().split(None, 1)

    if not partes:
        raise ValueError("Falta la instrucción FEIST.")

    nombre = partes[0]
    args = operandos(partes[1] if len(partes) > 1 else "")

    if nombre == "NOP":
        comprobar_cantidad(nombre, args, 0)
        return 0

    if nombre == "AUTH":
        comprobar_cantidad(nombre, args, 2)

        rs1 = registro(args[0])
        rs2 = registro(args[1])

        # AUTH: [10:7] rs2, [6:3] rs1, [2:0] opcode.
        return (rs2 << 7) | (rs1 << 3) | 0b001

    if nombre == "LOGOUT":
        comprobar_cantidad(nombre, args, 0)
        return 0b010

    if nombre == "KSTORE":
        comprobar_cantidad(nombre, args, 3)

        key = numero(args[0])
        ronda = numero(args[1])
        rs1 = registro(args[2])

        if not 0 <= key <= 3:
            raise ValueError("KEY debe estar entre 0 y 3.")

        if not 0 <= ronda <= 3:
            raise ValueError("ROUND debe estar entre 0 y 3.")

        # KSTORE: [10:9] key, [8:7] ronda, [6:3] rs1.
        return (
            (key << 9)
            | (ronda << 7)
            | (rs1 << 3)
            | 0b011
        )

    if nombre == "FROUND":
        comprobar_cantidad(nombre, args, 7)

        rdL = registro(args[0])
        rdR = registro(args[1])
        rsL = registro(args[2])
        rsR = registro(args[3])
        key = numero(args[4])
        ronda = numero(args[5])
        modo = numero(args[6])

        if not 0 <= key <= 3:
            raise ValueError("KEY debe estar entre 0 y 3.")

        if not 0 <= ronda <= 3:
            raise ValueError("ROUND debe estar entre 0 y 3.")

        if modo not in (0, 1):
            raise ValueError("MODE debe ser 0 o 1.")

        # FROUND utiliza los campos definidos en feist_decoder.sv.
        return (
            (rdL << 20)
            | (rdR << 16)
            | (rsL << 12)
            | (rsR << 8)
            | (key << 6)
            | (ronda << 4)
            | (modo << 3)
            | 0b100
        )

    raise ValueError(f"Instrucción FEIST desconocida: {nombre}")


# Cada línea del ensamblador representa un bundle.
def codificar_bundle(linea):
    # Los cuatro slots comienzan como NOP.
    slots = {
        "ALU": 0,
        "LSU": 0,
        "BRU": 0,
        "FEIST": 0,
    }

    usados = set()

    # Separar los slots mediante el símbolo |.
    instrucciones = linea.split("|")

    for instruccion in instrucciones:
        instruccion = instruccion.strip()

        if not instruccion:
            continue

        coincidencia = re.fullmatch(
            r"(ALU|LSU|BRU|FEIST)\s*:\s*(.+)",
            instruccion,
            re.IGNORECASE
        )

        if coincidencia is None:
            raise ValueError(
                f"Slot inválido: {instruccion}. "
                "Utiliza ALU:, LSU:, BRU: o FEIST:."
            )

        slot = coincidencia.group(1).upper()
        texto = coincidencia.group(2).strip()

        # No permitir dos instrucciones en el mismo slot.
        if slot in usados:
            raise ValueError(
                f"El slot {slot} aparece más de una vez en el bundle."
            )

        usados.add(slot)

        if slot == "ALU":
            valor = codificar_alu(texto)
        elif slot == "LSU":
            valor = codificar_lsu(texto)
        elif slot == "BRU":
            valor = codificar_bru(texto)
        else:
            valor = codificar_feist(texto)

        slots[slot] = valor

    # El bundle tiene este orden:
    # [127:96] FEIST, [95:64] BRU, [63:32] LSU, [31:0] ALU.
    bundle = (
        (slots["FEIST"] << 96)
        | (slots["BRU"] << 64)
        | (slots["LSU"] << 32)
        | slots["ALU"]
    )

    return bundle


def ensamblar(entrada, salida):
    lineas = Path(entrada).read_text(encoding="utf-8").splitlines()
    bundles = []

    for numero_linea, linea in enumerate(lineas, start=1):
        # Permitir comentarios con # o //.
        linea = linea.split("#", 1)[0]
        linea = linea.split("//", 1)[0]
        linea = linea.strip()

        if not linea:
            continue

        try:
            bundle = codificar_bundle(linea)
        except ValueError as error:
            raise ValueError(
                f"Error en la línea {numero_linea}: {error}"
            ) from error

        # Cada bundle se escribe como 32 dígitos hexadecimales.
        bundles.append(f"{bundle:032X}")

    # El archivo resultante contiene un bundle por línea.
    Path(salida).write_text(
        "\n".join(bundles) + ("\n" if bundles else ""),
        encoding="ascii"
    )

    print(f"Archivo ensamblado: {salida}")
    print(f"Bundles generados: {len(bundles)}")
    print(f"Bytes de instrucciones: {len(bundles) * 16}")


def main():
    parser = argparse.ArgumentParser(
        description="Ensamblador para el procesador VLIW-Feistel4."
    )

    parser.add_argument(
        "entrada",
        help="Archivo fuente con extensión .asm."
    )

    parser.add_argument(
        "-o",
        "--salida",
        default="program_test.mem",
        help="Archivo hexadecimal de salida. Por defecto: program_test.mem."
    )

    args = parser.parse_args()

    try:
        ensamblar(args.entrada, args.salida)
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
