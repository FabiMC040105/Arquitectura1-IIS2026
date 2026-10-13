
from pathlib import Path
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--bloques", type=int, required=True)
parser.add_argument("--modo", choices=["cifrar", "descifrar"], required=True)
args = parser.parse_args()

if args.bloques < 1 or args.bloques > 8192:
    raise ValueError("La cantidad de bloques debe estar entre 1 y 8192")

lineas = []

def instruccion(texto):
    lineas.append(texto)
    for _ in range(4):
        lineas.append("ALU: NOP")

def construir_constante(reg, valor):
    if not 0 <= valor <= 0xFFFFFFFF:
        raise ValueError(f"Constante fuera de rango: {valor}")

    bytes_val = [
        (valor >> 24) & 0xFF,
        (valor >> 16) & 0xFF,
        (valor >> 8) & 0xFF,
        valor & 0xFF
    ]

    instruccion(f"ALU: ADDI {reg}, x0, {bytes_val[0]}")

    for byte in bytes_val[1:]:
        instruccion(f"ALU: SLLI {reg}, {reg}, 8")
        instruccion(f"ALU: ADDI {reg}, {reg}, {byte}")

# Credenciales del key vault del hardware.
construir_constante("x2", 0xC0DE1234)
construir_constante("x3", 0xABCD5678)

# Todas las subclaves se inicializan con 1,
# igual que en la prueba funcional existente.
instruccion("ALU: ADDI x4, x0, 1")
instruccion("FEIST: AUTH x2, x3")

for ronda in range(4):
    instruccion(f"FEIST: KSTORE 0, {ronda}, x4")

# x14: dirección del bloque actual.
# x5: cantidad de bloques de 8 bytes pendientes.
instruccion("ALU: ADDI x14, x0, 0")
construir_constante("x5", args.bloques)

indice_bucle = len(lineas)

# Leer los 64 bits del bloque en dos registros.
instruccion("LSU: LOAD x8, 0(x14)")
instruccion("LSU: LOAD x9, 4(x14)")

if args.modo == "cifrar":
    rondas = [0, 1, 2, 3]
    modo_feistel = 0
else:
    rondas = [3, 2, 1, 0]
    modo_feistel = 1

# Cada FROUND ejecuta una ronda en el hardware.
for ronda in rondas:
    instruccion(
        f"FEIST: FROUND x10, x11, x8, x9, 0, {ronda}, {modo_feistel}"
        if ronda == rondas[0]
        else f"FEIST: FROUND x10, x11, x10, x11, 0, {ronda}, {modo_feistel}"
    )

# Cifrado en el mismo espacio de memoria de entrada.
instruccion("LSU: STORE x10, 0(x14)")
instruccion("LSU: STORE x11, 4(x14)")

# Avanzar al siguiente bloque de 8 bytes.
instruccion("ALU: ADDI x14, x14, 8")
instruccion("ALU: ADDI x5, x5, -1")

# Saltar al inicio del ciclo mientras queden bloques.
indice_bne = len(lineas)
instruccion("BRU: BNE x5, x0, 0")

desplazamiento = (indice_bucle - indice_bne) * 16
lineas[indice_bne] = f"BRU: BNE x5, x0, {desplazamiento}"

# Cuando termina el procesamiento, quedarse en este salto.
instruccion("BRU: JMP 0")

Path("prueba_cifrado.asm").write_text(
    "\n".join(lineas) + "\n",
    encoding="utf-8"
)

print(f"Modo: {args.modo}")
print(f"Bloques de 8 bytes: {args.bloques}")
print(f"Bundles generados: {len(lineas)}")
print("Programa guardado en prueba_cifrado.asm")
