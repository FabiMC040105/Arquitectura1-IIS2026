#!/usr/bin/env python3

import argparse
from pathlib import Path


def leer_volcado(archivo, bytes_por_palabra):
    # Leer el volcado que produjo la simulación.
    lineas = Path(archivo).read_text(encoding="ascii").splitlines()

    memoria = {}
    direccion = 0
    maximo = (1 << (bytes_por_palabra * 8)) - 1

    for numero_linea, linea in enumerate(lineas, start=1):
        # Ignorar líneas vacías y comentarios.
        linea = linea.split("//", 1)[0]
        linea = linea.split("#", 1)[0]
        linea = linea.strip()

        if not linea:
            continue

        # Una directiva @ cambia el índice de memoria.
        if linea.startswith("@"):
            try:
                direccion = int(linea[1:], 16)
            except ValueError:
                raise ValueError(
                    f"Dirección inválida en la línea {numero_linea}."
                )

            continue

        # Aceptar palabras hexadecimales con o sin prefijo 0x.
        valor_texto = linea.replace("_", "")

        if valor_texto.lower().startswith("0x"):
            valor_texto = valor_texto[2:]

        try:
            valor = int(valor_texto, 16)
        except ValueError:
            raise ValueError(
                f"Valor hexadecimal inválido en la línea {numero_linea}."
            )

        if not 0 <= valor <= maximo:
            raise ValueError(
                f"La palabra de la línea {numero_linea} "
                "supera el tamaño configurado."
            )

        # Guardar la palabra usando el índice que le corresponde.
        if direccion in memoria:
            raise ValueError(
                f"La dirección de memoria {direccion:#x} está repetida."
            )

        memoria[direccion] = valor
        direccion += 1

    return memoria


def extraer_archivo(
    entrada,
    salida,
    direccion_inicial,
    cantidad_bytes,
    bytes_por_palabra
):
    if direccion_inicial < 0:
        raise ValueError("La dirección inicial no puede ser negativa.")

    if cantidad_bytes < 0:
        raise ValueError("La cantidad de bytes no puede ser negativa.")

    if bytes_por_palabra <= 0:
        raise ValueError("El tamaño de palabra debe ser mayor que cero.")

    if direccion_inicial % bytes_por_palabra != 0:
        raise ValueError(
            "La dirección inicial debe estar alineada con el tamaño de palabra."
        )

    memoria = leer_volcado(entrada, bytes_por_palabra)

    # Convertir la dirección en bytes al índice de la memoria.
    indice_inicial = direccion_inicial // bytes_por_palabra

    # Reconstruir cada palabra respetando el orden little-endian.
    datos = bytearray()

    while len(datos) < cantidad_bytes:
        indice = indice_inicial + len(datos) // bytes_por_palabra

        if indice not in memoria:
            raise ValueError(
                f"No existe información para la posición de memoria {indice:#x}."
            )

        palabra = memoria[indice]
        bytes_palabra = palabra.to_bytes(
            bytes_por_palabra,
            byteorder="little"
        )

        datos.extend(bytes_palabra)

    # Guardar únicamente la cantidad de bytes solicitada.
    datos = datos[:cantidad_bytes]
    Path(salida).write_bytes(datos)

    print(f"Volcado de entrada: {entrada}")
    print(f"Archivo reconstruido: {salida}")
    print(f"Dirección inicial: 0x{direccion_inicial:X}")
    print(f"Bytes reconstruidos: {len(datos)}")


def main():
    parser = argparse.ArgumentParser(
        description="Reconstruye un archivo binario desde un volcado hexadecimal."
    )

    parser.add_argument(
        "entrada",
        help="Archivo hexadecimal generado por la simulación."
    )

    parser.add_argument(
        "salida",
        help="Archivo binario que se va a reconstruir."
    )

    parser.add_argument(
        "--direccion",
        type=lambda valor: int(valor, 0),
        default=0,
        help="Dirección inicial en bytes. Por defecto: 0."
    )

    parser.add_argument(
        "--cantidad",
        type=lambda valor: int(valor, 0),
        required=True,
        help="Cantidad de bytes que se deben recuperar."
    )

    parser.add_argument(
        "--bytes-por-palabra",
        type=int,
        default=1,
        help="Bytes de cada posición de memoria. Por defecto: 1."
    )

    args = parser.parse_args()

    try:
        extraer_archivo(
            args.entrada,
            args.salida,
            args.direccion,
            args.cantidad,
            args.bytes_por_palabra
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
