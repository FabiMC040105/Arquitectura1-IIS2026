"""Cifrado/descifrado independiente de archivos con VLIW + Feistel simulado.

El cifrado se ejecuta en SystemVerilog, no en Python.
Python solo prepara datos, programas, simulaciones y el encabezado del archivo.
"""

from pathlib import Path
import argparse
import hashlib
import math
import subprocess
import sys
import tempfile

RAIZ = Path(__file__).resolve().parent.parent
TAMANO_MEMORIA = 65536
TAMANO_BLOQUE = 8
MAGIA = b"VLIWFEI1"  # Identificador del formato del archivo cifrado

TIPOS = {
    ".jpg": "imagen JPEG", ".jpeg": "imagen JPEG",
    ".png": "imagen PNG", ".gif": "imagen GIF",
    ".bmp": "imagen BMP", ".pdf": "documento PDF",
    ".txt": "archivo de texto", ".csv": "archivo CSV",
    ".mp4": "video MP4", ".mov": "video MOV",
    ".mp3": "audio MP3", ".wav": "audio WAV",
    ".zip": "archivo ZIP", ".bin": "archivo binario",
}


def tipo_archivo(nombre):
    """Describe el tipo usando la extensión original guardada en el encabezado."""
    extension = Path(nombre).suffix.lower()
    return TIPOS.get(extension, f"archivo de extensión {extension or '(sin extensión)'}")


# Identificacion por firmas binarias: inspecciona el contenido real,
# independientemente de la extension del nombre del archivo.
FIRMAS = [
    # Imagenes
    (bytes.fromhex("89504E470D0A1A0A"), "PNG"),
    (bytes.fromhex("FFD8FF"), "JPEG"),
    (bytes.fromhex("474946383761"), "GIF87a"),
    (bytes.fromhex("474946383961"), "GIF89a"),
    (bytes.fromhex("424D"), "BMP"),
    (bytes.fromhex("49492A00"), "TIFF"),
    (bytes.fromhex("4D4D002A"), "TIFF"),
    (bytes.fromhex("00000100"), "ICO"),

    # Documentos
    (bytes.fromhex("25504446"), "PDF"),
    (bytes.fromhex("D0CF11E0A1B11AE1"), "OLE / Office antiguo"),
    (bytes.fromhex("504B0304"), "ZIP (posible DOCX/XLSX/PPTX u otro ZIP)"),

    # Audio
    (bytes.fromhex("494433"), "MP3 (ID3)"),
    (bytes.fromhex("4F676753"), "OGG"),
    (bytes.fromhex("664C6143"), "FLAC"),
    (bytes.fromhex("52494646"), "RIFF (posible WAV/AVI/WebP)"),

    # Video
    (bytes.fromhex("00000018667479706D703432"), "MP4"),
    (bytes.fromhex("00000020667479704D534E56"), "ISO BMFF / posible MP4"),
    (bytes.fromhex("1A45DFA3"), "MKV / WebM (EBML)"),
    (bytes.fromhex("464C5601"), "FLV"),
    (bytes.fromhex("3026B2758E66CF11"), "ASF (posible WMV/WMA)"),

    # Archivos comprimidos
    (bytes.fromhex("1F8B"), "GZIP"),
    (bytes.fromhex("425A68"), "BZIP2"),
    (bytes.fromhex("FD377A585A00"), "XZ"),
    (bytes.fromhex("377ABCAF271C"), "7-Zip"),
    (bytes.fromhex("526172211A070100"), "RAR 5"),
    (bytes.fromhex("526172211A0700"), "RAR"),

    # Ejecutables
    (bytes.fromhex("4D5A"), "EXE/DLL de Windows (MZ)"),
    (bytes.fromhex("7F454C46"), "ELF (Linux/Unix)"),
]


def identificar_formato(ruta):
    """Identifica algunas firmas comunes leyendo el principio del archivo."""
    with Path(ruta).open("rb") as archivo:
        inicio = archivo.read(32)

    if inicio.startswith(b"RIFF") and len(inicio) >= 12:
        tipo_riff = {
            b"WAVE": "WAV", b"AVI ": "AVI", b"WEBP": "WebP"
        }.get(inicio[8:12])
        if tipo_riff:
            return tipo_riff

    for firma, formato in FIRMAS:
        if inicio.startswith(firma):
            return formato

    # Varios contenedores multimedia tienen el cuadro 'ftyp'
    # a partir del desplazamiento 4, con tamanos distintos.
    if len(inicio) >= 12 and inicio[4:8] == b"ftyp":
        return "Contenedor ISO BMFF (posible MP4/MOV/HEIC)"

    return "BINARIO DESCONOCIDO (sin firma reconocida)"


def ejecutar(comando, descripcion, carpeta_trabajo):
    print(f"\n{descripcion}", flush=True)
    resultado = subprocess.run(
        comando, cwd=carpeta_trabajo, text=True, capture_output=True
    )
    if resultado.stdout.strip():
        print(resultado.stdout.strip())
    if resultado.stderr.strip():
        print(resultado.stderr.strip())
    if resultado.returncode != 0:
        raise RuntimeError(f"Falló: {descripcion} (código {resultado.returncode})")


def preparar_simulador(carpeta_trabajo):
    fuentes = sorted((RAIZ / "src").glob("*.sv"))
    banco = RAIZ / "tb" / "tb_cipher.sv"
    if not fuentes or not banco.exists():
        raise FileNotFoundError("Faltan los módulos src/*.sv o tb/tb_cipher.sv")
    comando = [
        "iverilog", "-g2012", "-s", "tb_cipher", "-o", "sim_cipher.vvp",
        *[str(f) for f in fuentes], str(banco),
    ]
    ejecutar(comando, "Compilando el procesador VLIW", carpeta_trabajo)


def ejecutar_hardware(modo, datos, numero_parte, carpeta_trabajo):
    """Entrega bloques de 8 bytes al procesador simulado y recoge su salida."""
    datos = datos + bytes((-len(datos)) % TAMANO_BLOQUE)
    if not datos:
        return b""
    if len(datos) > TAMANO_MEMORIA:
        raise ValueError("La parte excede la memoria del procesador")

    cantidad_bloques = len(datos) // TAMANO_BLOQUE
    entrada = carpeta_trabajo / "input.mem"
    with entrada.open("w", encoding="ascii", newline="\n") as archivo:
        archivo.write("@0\n")
        for byte in datos:
            archivo.write(f"{byte:02X}\n")

    # generar_prueba.py escribe prueba_cifrado.asm en el directorio actual.
    ejecutar([
        sys.executable, str(RAIZ / "python" / "generar_prueba.py"),
        "--modo", modo, "--bloques", str(cantidad_bloques),
    ], f"Generando programa para {modo}", carpeta_trabajo)

    ejecutar([
        sys.executable, str(RAIZ / "python" / "assembler.py"),
        "prueba_cifrado.asm", "-o", "program_test.mem",
    ], "Ensamblando programa VLIW", carpeta_trabajo)

    salida = f"parte_{numero_parte:04d}_{modo}.bin"
    ciclos = cantidad_bloques * 80 + 5000
    ejecutar([
        "vvp", "sim_cipher.vvp",
        f"+OUTPUT_FILE={salida}",
        f"+OUTPUT_BYTES={len(datos)}",
        f"+MAX_CYCLES={ciclos}",
    ], f"Ejecutando hardware: {modo} ({cantidad_bloques} bloques)",
        carpeta_trabajo)

    ruta_salida = carpeta_trabajo / salida
    if not ruta_salida.exists():
        raise RuntimeError(f"El simulador no generó {salida}")
    resultado = ruta_salida.read_bytes()
    if len(resultado) != len(datos):
        raise RuntimeError("La cantidad de bytes entregados por el hardware es incorrecta")
    ruta_salida.unlink()
    return resultado


def procesar_bytes(modo, datos, carpeta_trabajo):
    """Divide el archivo en partes que caben en los 64 KiB de RAM simulada."""
    resultado = bytearray()
    total = math.ceil(len(datos) / TAMANO_MEMORIA)
    for n in range(total):
        parte = datos[n * TAMANO_MEMORIA:(n + 1) * TAMANO_MEMORIA]
        print(f"\nParte {n + 1}/{total}: {len(parte)} bytes")
        resultado.extend(ejecutar_hardware(modo, parte, n, carpeta_trabajo))
    return bytes(resultado)


def crear_contenedor(nombre_original, datos_originales, bytes_cifrados):
    """Encabezado: magia(8) + tamaño(8) + nombre_len(2) + nombre + SHA256(32)."""
    nombre = Path(nombre_original).name.encode("utf-8")
    if not nombre or len(nombre) > 65535:
        raise ValueError("Nombre original demasiado largo")
    return (
        MAGIA
        + len(datos_originales).to_bytes(8, "little")
        + len(nombre).to_bytes(2, "little")
        + nombre
        + hashlib.sha256(datos_originales).digest()
        + bytes_cifrados
    )


def leer_contenedor(contenido):
    """Lee los metadatos y comprueba que el cifrado conserva todos los bloques."""
    if len(contenido) < 18 or contenido[:8] != MAGIA:
        raise ValueError("Formato no reconocido: se esperaba un .cifrado.bin VLIWFEI1")
    tamano = int.from_bytes(contenido[8:16], "little")
    longitud_nombre = int.from_bytes(contenido[16:18], "little")
    fin_nombre = 18 + longitud_nombre
    if not longitud_nombre or len(contenido) < fin_nombre + 32:
        raise ValueError("Encabezado del archivo cifrado incompleto")
    try:
        nombre = contenido[18:fin_nombre].decode("utf-8")
    except UnicodeDecodeError as e:
        raise ValueError("Nombre original inválido en el encabezado") from e
    if nombre in (".", "..") or "/" in nombre or "\\" in nombre:
        raise ValueError("Nombre original inválido en el encabezado")
    huella = contenido[fin_nombre:fin_nombre + 32]
    cifrado = contenido[fin_nombre + 32:]
    tamano_esperado = ((tamano + TAMANO_BLOQUE - 1) // TAMANO_BLOQUE) * TAMANO_BLOQUE
    if len(cifrado) != tamano_esperado:
        raise ValueError("Cifrado incompleto o con relleno de tamaño incorrecto")
    return nombre, tamano, huella, cifrado


def ruta_recuperada(carpeta, nombre):
    """Nunca sobrescribe por defecto el original: añade '_recuperado'."""
    original = Path(nombre)
    extensiones = "".join(original.suffixes)
    base = original.name[:-len(extensiones)] if extensiones else original.name
    return carpeta / f"{base}_recuperado{extensiones}"


def cifrar(entrada, salida, trabajo):
    datos = entrada.read_bytes()
    print(f"\nArchivo original: {entrada.name}")
    print(f"Tipo registrado: {tipo_archivo(entrada.name)}")
    print(f"Formato detectado por firma: {identificar_formato(entrada)}")
    print(f"Tamaño original: {len(datos)} bytes")
    cifrado = procesar_bytes("cifrar", datos, trabajo)
    contenedor = crear_contenedor(entrada.name, datos, cifrado)
    salida.write_bytes(contenedor)
    print(f"\nCIFRADO GENERADO: {salida}")
    print(f"Bytes cifrados Feistel: {len(cifrado)}")
    print(f"Tamaño total (incluye encabezado): {len(contenedor)}")
    print(f"Formato detectado por firma: {identificar_formato(entrada)}")
    return salida


def descifrar(entrada, salida_opcional, trabajo):
    nombre, tamano, huella, cifrado = leer_contenedor(entrada.read_bytes())
    salida = salida_opcional or ruta_recuperada(entrada.parent, nombre)
    print(f"\nArchivo cifrado: {entrada.name}")
    print(f"Nombre original: {nombre}")
    print(f"Tipo recuperado: {tipo_archivo(nombre)}")
    print(f"Tamaño original registrado: {tamano} bytes")
    recuperado_con_relleno = procesar_bytes("descifrar", cifrado, trabajo)
    recuperado = recuperado_con_relleno[:tamano]
    if hashlib.sha256(recuperado).digest() != huella:
        raise RuntimeError("ERROR: verificación SHA-256 incorrecta; no se guardó el archivo")
    salida.write_bytes(recuperado)
    print(f"Formato recuperado por firma: {identificar_formato(salida)}")
    print(f"\nPASS: verificación SHA-256 correcta")
    print(f"PASS: recuperados {len(recuperado)} bytes")
    print(f"ARCHIVO RECUPERADO: {salida}")
    return salida


def main():
    parser = argparse.ArgumentParser(description="Archivos VLIW + Feistel")
    parser.add_argument("primero", help="cifrar, descifrar o ruta (prueba completa)")
    parser.add_argument("archivo", nargs="?", help="Ruta del archivo")
    parser.add_argument("--salida", help="Nombre de salida opcional")
    args = parser.parse_args()

    if args.primero in ("cifrar", "descifrar"):
        if not args.archivo:
            parser.error("Falta la ruta del archivo")
        modo, entrada = args.primero, Path(args.archivo).resolve()
    elif args.archivo is None:
        modo, entrada = "completo", Path(args.primero).resolve()
    else:
        parser.error("Utiliza: cifrar ARCHIVO, descifrar ARCHIVO o ARCHIVO")

    if not entrada.is_file():
        parser.error(f"No existe el archivo: {entrada}")
    salida = Path(args.salida).resolve() if args.salida else None
    if salida is not None and salida == entrada:
        parser.error("La salida no puede sobrescribir el archivo de entrada")

    # Trabajamos lejos del repositorio: nada de input.mem/program_test.mem
    # ni prueba_cifrado.asm se sobrescribe en Git.
    with tempfile.TemporaryDirectory(prefix="vliw_feistel_") as temporal:
        trabajo = Path(temporal)
        preparar_simulador(trabajo)
        if modo == "cifrar":
            cifrar(entrada, salida or entrada.with_name(entrada.name + ".cifrado.bin"), trabajo)
        elif modo == "descifrar":
            descifrar(entrada, salida, trabajo)
        else:
            archivo_cifrado = cifrar(
                entrada, entrada.with_name(entrada.name + ".cifrado.bin"), trabajo
            )
            archivo_recuperado = descifrar(archivo_cifrado, salida, trabajo)
            if archivo_recuperado.read_bytes() != entrada.read_bytes():
                raise RuntimeError("ERROR: el archivo recuperado no coincide con el original")
            print("\nPASS: comparación byte por byte con el original")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(f"\nERROR: {error}", file=sys.stderr)
        sys.exit(1)
