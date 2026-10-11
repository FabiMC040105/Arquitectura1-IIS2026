#!/usr/bin/env python3
import argparse
from pathlib import Path


def convertir_archivo(entrada, salida, direccion_inicial, bytes_por_palabra):
    # Leer el archivo completo como una secuencia de bytes.
    datos = Path(entrada).read_bytes()

    # La dirección inicial debe estar alineada con el tamaño de palabra.
    if direccion_inicial < 0:
        raise ValueError("La dirección inicial no puede ser negativa.")

    if direccion_inicial % bytes_por_palabra != 0:
        raise ValueError(
            "La dirección inicial debe estar alineada con el tamaño de palabra."
        )

    # Cada línea de la imagen representa una posición de memoria.
    # La directiva @ indica la posición inicial del arreglo en $readmemh.
    indice_inicial = direccion_inicial // bytes_por_palabra

    lineas = [f"@{indice_inicial:X}"]

    # Completar la última palabra con ceros si el archivo no tiene
    # una cantidad de bytes múltiplo del tamaño de palabra.
    resto = len(datos) % bytes_por_palabra

    if resto != 0:
        datos += bytes(bytes_por_palabra - resto)

    # Convertir cada grupo de bytes en una palabra hexadecimal.
    for posicion in range(0, len(datos), bytes_por_palabra):
        palabra = datos[posicion:posicion + bytes_por_palabra]

        # La memoria utiliza little-endian: el primer byte ocupa la posición menos significativa de la palabra.
        valor = int.from_bytes(palabra, byteorder="little")

        # Cada palabra se escribe con el ancho hexadecimal necesario.
        ancho_hex = bytes_por_palabra * 2
        lineas.append(f"{valor:0{ancho_hex}X}")

    # Guardar la imagen hexadecimal.
    Path(salida).write_text(
        "\n".join(lineas) + "\n",
        encoding="ascii"
    )

    print(f"Archivo de entrada: {entrada}")
    print(f"Imagen generada: {salida}")
    print(f"Dirección inicial: 0x{direccion_inicial:X}")
    print(f"Bytes originales: {Path(entrada).stat().st_size}")
    print(f"Bytes reservados en memoria: {len(datos)}")
    print(f"Tamaño de palabra: {bytes_por_palabra} byte(s)")


def main():
    parser = argparse.ArgumentParser(
        description="Convierte un archivo binario en una imagen hexadecimal."
    )

    parser.add_argument(
        "entrada",
        help="Archivo binario que se desea cargar."
    )

    parser.add_argument(
        "salida",
        help="Archivo hexadecimal que se va a generar."
    )

    parser.add_argument(
        "--direccion",
        type=lambda valor: int(valor, 0),
        default=0,
        help="Dirección inicial en bytes. Por defecto: 0."
    )

    parser.add_argument(
        "--bytes-por-palabra",
        type=int,
        default=1,
        help="Bytes de cada posición de memoria. Por defecto: 1."
    )

    args = parser.parse_args()

    if args.bytes_por_palabra <= 0:
        parser.error("--bytes-por-palabra debe ser mayor que cero.")

    try:
        convertir_archivo(
            args.entrada,
            args.salida,
            args.direccion,
            args.bytes_por_palabra
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
