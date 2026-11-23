#!/usr/bin/env python3
"""Genera los benchmarks de lectura para el procesador VLIW."""
import argparse
import json
import random
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'benchmarks'
BUILD = ROOT / 'build' / 'benchmarks'
WORDS = 2048                 # 8 KiB de datos para los patrones dispersos
ACCESSES = 256               # Lecturas por pasada
PASSES = 2
SEED = 2026
MARKER = 1234


def patterns():
    # Repetimos la misma secuencia para observar la reutilizacion de las lineas.
    rng = random.Random(SEED)
    return {
        'sequential': [4 * i for i in range(ACCESSES)],
        'random': [4 * i for i in rng.sample(range(WORDS), ACCESSES)],
        'stride': [32 * i for i in range(ACCESSES)],
    }


def make_program(name, addresses):
    lines = [f'# Benchmark {name}: {len(addresses)} lecturas por pasada.',
             '# x2-x5 contienen bases separadas por 2048 bytes.']
    # Los inmediatos del ISA tienen 12 bits con signo. Primero cargamos
    # las bases en palabras, luego las convertimos a direcciones de bytes.
    for i in range(4):
        lines.append(f'ALU: ADDI x{i+2}, x0, {i*512}')
    for i in range(4):
        lines.append(f'ALU: SLLI x{i+2}, x{i+2}, 2')
    # Dejamos que las bases lleguen a WB antes de leerlas en RR.
    lines.extend(['ALU: NOP'] * 4)
    expected = {f'x{i}': 0 for i in range(6, 15)}
    for pass_no in range(PASSES):
        lines.append(f'# Pasada {pass_no + 1}')
        for i, address in enumerate(addresses):
            base, offset = divmod(address, 2048)
            dest = 6 + ((pass_no * len(addresses) + i) % 9)
            # Los LOAD no consumen los resultados de otros LOAD.
            lines.append(f'LSU: LOAD x{dest}, {offset}(x{base+2})')
            expected[f'x{dest}'] = address // 4 + 1
    # El marcador solo indica que se alcanzo el final del programa.
    lines.append(f'ALU: ADDI x15, x0, {MARKER}')
    expected['x15'] = MARKER
    # La ROM se inicializa en NOP; agregamos cola explicita para el tb_run.
    lines.extend(['ALU: NOP'] * 12)
    return '\n'.join(lines) + '\n', expected


def generate(sources_only=False):
    SOURCE.mkdir(parents=True, exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    # La memoria de datos original carga un byte por linea con readmemh.
    # Cada palabra en la direccion 4*i contiene i+1, en little endian.
    data = bytearray(65536)
    for i in range(WORDS):
        data[4*i:4*i+4] = (i+1).to_bytes(4, 'little')
    (BUILD / 'data.mem').write_text(''.join(f'{b:02x}\n' for b in data), encoding='ascii')

    manifest = {}
    for name, addresses in patterns().items():
        program, expected = make_program(name, addresses)
        asm = SOURCE / f'{name}.asm'
        asm.write_text(program, encoding='ascii')
        bundles = sum(bool(line.strip()) and not line.startswith('#') for line in program.splitlines())
        manifest[name] = {
            'reads': len(addresses) * PASSES,
            'passes': PASSES,
            'unique_cache_lines': len({a // 32 for a in addresses}),
            'program_bundles': bundles,
            'addresses_one_pass': addresses,
            'expected_registers': expected,
        }
        if not sources_only:
            subprocess.run([sys.executable, str(ROOT / 'python' / 'assembler.py'),
                            str(asm), '-o', str(BUILD / f'{name}.mem')], check=True)
            binary = (BUILD / f'{name}.mem').read_text().splitlines()
            assert len(binary) == bundles and all(re.fullmatch(r'[0-9a-fA-F]{32}', x) for x in binary)
        print(f'{name}: {len(addresses)*PASSES} lecturas, {bundles} bundles en ROM')
    (BUILD / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='ascii')
    print('Benchmarks preparados en benchmarks/ y build/benchmarks/')


def check_log(name, path):
    expected = json.loads((BUILD / 'manifest.json').read_text())[name]['expected_registers']
    log = Path(path).read_text(encoding='utf-8', errors='replace')
    if 'Programa terminado tras' not in log or 'AVISO: limite' in log:
        raise SystemExit('ERROR: el testbench no informo un fin normal.')
    actual = {reg: int(value, 16) for reg, value in re.findall(r'^\s*(x\d+)\s*=\s*([0-9a-fA-F]{8})\s*$', log, re.M)}
    for reg, value in expected.items():
        if actual.get(reg) != value:
            raise SystemExit(f'ERROR: {reg}, esperado {value}, obtenido {actual.get(reg)}')
    print(f'PASS: {name}, los 10 registros finales coinciden con el resultado esperado')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources-only', action='store_true', help='Genera fuentes y datos sin invocar el ensamblador')
    parser.add_argument('--check-log', nargs=2, metavar=('PATRON', 'LOG'), help='Comprueba los registros finales de tb_run')
    args = parser.parse_args()
    if args.check_log:
        check_log(*args.check_log)
    else:
        generate(args.sources_only)
