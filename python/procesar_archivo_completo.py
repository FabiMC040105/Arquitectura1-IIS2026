from pathlib import Path
import subprocess
import sys
import math
import argparse

RAIZ = Path(__file__).resolve().parent.parent

parser = argparse.ArgumentParser(
    description="Cifra y descifra cualquier archivo mediante el procesador VLIW."
)
parser.add_argument(
    "archivo",
    help="Ruta del archivo que se va a procesar"
)
args = parser.parse_args()

IMAGEN = Path(args.archivo).resolve()
TAMANO_MEMORIA = 65536
TAMANO_BLOQUE = 8
ARCHIVO_ENTRADA = RAIZ / "input.mem"
ARCHIVO_ASM = RAIZ / "prueba_cifrado.asm"
ARCHIVO_PROGRAMA = RAIZ / "program_test.mem"
ARCHIVO_SIMULADOR = RAIZ / "sim_cipher.vvp"

SALIDA_CIFRADA = IMAGEN.with_name(IMAGEN.name + ".cifrado.bin")
SALIDA_DESCIFRADA = IMAGEN.with_name(IMAGEN.name + ".descifrado")

def ejecutar(comando, descripcion):
    print(f"\n{descripcion}", flush=True)
    resultado = subprocess.run(comando, cwd=RAIZ, text=True, capture_output=True)
    if resultado.returncode != 0:
        print(resultado.stdout)
        print(resultado.stderr)
        raise RuntimeError(f"Fallo durante: {descripcion}")
    if resultado.stdout.strip():
        print(resultado.stdout.strip())
    if resultado.stderr.strip():
        # Las advertencias de Icarus no siempre indican un fallo.
        print(resultado.stderr.strip())

def guardar_memoria(datos):
    if len(datos) > TAMANO_MEMORIA:
        raise ValueError("Los datos exceden la memoria disponible")
    with ARCHIVO_ENTRADA.open("w", encoding="ascii", newline="\n") as f:
        f.write("@0\n")
        for byte in datos:
            f.write(f"{byte:02X}\n")

def generar_programa(modo, bloques):
    ejecutar([
        sys.executable,
        str(RAIZ / "Python" / "generar_prueba.py"),
        "--modo", modo,
        "--bloques", str(bloques)
    ], f"Generando programa para {modo}")
    ejecutar([
        sys.executable,
        str(RAIZ / "Python" / "assembler.py"),
        str(ARCHIVO_ASM),
        "-o",
        str(ARCHIVO_PROGRAMA)
    ], "Ensamblando programa VLIW")

def ejecutar_hardware(modo, datos, numero_bloque):
    datos_padded = datos + bytes((-len(datos)) % TAMANO_BLOQUE)
    if not datos_padded:
        return b""
    bloques = len(datos_padded) // TAMANO_BLOQUE
    guardar_memoria(datos_padded)
    generar_programa(modo, bloques)
    
    # Margen para inicialización, ejecución de los bloques y pipeline.
    max_ciclos = bloques * 80 + 5000
    archivo_salida = RAIZ / f"bloque_{numero_bloque:04d}_{modo}.bin"
    ejecutar([
        "vvp",
        str(ARCHIVO_SIMULADOR),
        f"+OUTPUT_FILE={archivo_salida.name}",
        f"+OUTPUT_BYTES={len(datos_padded)}",
        f"+MAX_CYCLES={max_ciclos}"
    ], f"Bloque {numero_bloque}: {modo}, {bloques} bloques Feistel")
    
    if not archivo_salida.exists():
        raise RuntimeError(f"No se generó {archivo_salida.name}")
    resultado = archivo_salida.read_bytes()
    if len(resultado) != len(datos_padded):
        raise RuntimeError(f"Tamaño inesperado en {archivo_salida.name}: {len(resultado)} bytes; esperados {len(datos_padded)}")
    archivo_salida.unlink()
    return resultado

def main():
    if not IMAGEN.exists():
        raise FileNotFoundError(f"No se encontró la imagen: {IMAGEN}")
    original = IMAGEN.read_bytes()
    tamano_original = len(original)
    if tamano_original == 0:
        raise ValueError("La imagen de entrada está vacía")
    
    print("=" * 60)
    print(" CIFRADO COMPLETO DE IMAGEN MEDIANTE VLIW + FEISTEL")
    print("=" * 60)
    print(f"Imagen: {IMAGEN}")
    print(f"Tamaño original: {tamano_original:,} bytes")
    print(f"Memoria disponible: {TAMANO_MEMORIA:,} bytes")
    print(f"Bloques de procesamiento: {math.ceil(tamano_original / TAMANO_MEMORIA)}")

    fuentes = sorted((RAIZ / "src").glob("*.sv"))
    testbench = RAIZ / "tb" / "tb_cipher.sv"
    if not fuentes:
        raise FileNotFoundError("No se encontraron archivos .sv en src")
    if not testbench.exists():
        raise FileNotFoundError(f"No se encontró {testbench}")

    comando_compilar = [
        "iverilog", "-g2012", "-s", "tb_cipher", "-o", str(ARCHIVO_SIMULADOR),
        *[str(f) for f in fuentes], str(testbench)
    ]
    ejecutar(comando_compilar, "Compilando el procesador y el testbench")

    cifrado_completo = bytearray()
    descifrado_completo = bytearray()

    # Se procesa en bloques de 64 KiB.
    # Cada bloque se cifra y después se descifra en el hardware.
    total_bloques = math.ceil(tamano_original / TAMANO_MEMORIA)
    for numero in range(total_bloques):
        inicio = numero * TAMANO_MEMORIA
        fin = min(inicio + TAMANO_MEMORIA, tamano_original)
        bloque_original = original[inicio:fin]
        
        print("\n" + "=" * 60)
        print(f"PROGRESO: bloque {numero + 1}/{total_bloques}; bytes {inicio:,} a {fin - 1:,}", flush=True)

        bloque_cifrado = ejecutar_hardware("cifrar", bloque_original, numero)
        cifrado_completo.extend(bloque_cifrado)

        bloque_descifrado = ejecutar_hardware("descifrar", bloque_cifrado, numero)
        descifrado_completo.extend(bloque_descifrado)

        # Comprobar cada bloque antes de continuar.
        if bloque_descifrado[:len(bloque_original)] != bloque_original:
            raise RuntimeError(f"El bloque {numero} no se recuperó correctamente. Se detiene el procesamiento.")
        print(f"Bloque {numero + 1}: verificación correcta.")

    # El último bloque puede contener bytes de relleno.
    cifrado_final = bytes(cifrado_completo[:tamano_original])
    descifrado_final = bytes(descifrado_completo[:tamano_original])

    SALIDA_CIFRADA.write_bytes(cifrado_final)
    SALIDA_DESCIFRADA.write_bytes(descifrado_final)

    print("\n" + "=" * 60)
    print("RESULTADO FINAL")
    print("=" * 60)
    print(f"Original:     {tamano_original:,} bytes")
    print(f"Cifrado:      {len(cifrado_final):,} bytes")
    print(f"Descifrado:   {len(descifrado_final):,} bytes")
    print(f"Archivo cifrado:    {SALIDA_CIFRADA}")
    print(f"Archivo descifrado: {SALIDA_DESCIFRADA}")

    if descifrado_final == original:
        print("\nPASS: el archivo descifrado es idéntico al original.")
        print("PASS: la comparación byte por byte fue exitosa.")
    else:
        raise RuntimeError("ERROR: el archivo descifrado difiere del original.")

if __name__ == "__main__":
    main()