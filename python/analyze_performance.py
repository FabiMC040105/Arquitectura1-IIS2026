#!/usr/bin/env python3
"""Resume resultados de simulacion y calcula las metricas de rendimiento."""
import argparse
import csv
import math
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'build' / 'benchmarks'
# Los nombres coinciden con los eventos del modulo performance_counters.
RAW = ['cycles', 'bundles', 'instructions', 'cache_stall_cycles',
       'branch_stall_cycles', 'l2_lookup_stall_cycles', 'memory_stall_cycles',
       'buffer_stall_cycles', 'l1_read_hits', 'l1_read_misses', 'l1_write_hits',
       'l1_write_misses', 'l2_read_hits', 'l2_read_misses', 'l2_write_hits',
       'l2_write_misses', 'mem_reads', 'mem_writes', 'mem_busy_cycles', 'mem_words']


def ratio(n, d):
    # Sin accesos no existe una tasa; no la confundimos con un cero real.
    return n / d if d else None


def read_csv(path, fields):
    with path.open(newline='', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        missing = set(fields) - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f'{path}: faltan columnas {sorted(missing)}')
        rows = list(reader)
    if not rows:
        raise ValueError(f'{path}: no contiene resultados')
    keys = set()
    for row in rows:
        key = (row['benchmark'], row['configuration'])
        if not all(key) or key in keys or row['status'] != 'PASS':
            raise ValueError(f'Fila duplicada, incompleta o no validada: {key}')
        keys.add(key)
    return rows


def integer(row, key):
    value = int(row[key])
    if value < 0:
        raise ValueError(f'{key} no puede ser negativo')
    return value


def analyze_baseline(path):
    names = ['expected_reads', 'unique_cache_lines', 'rom_bundles',
             'rom_bytes', 'tb_run_cycles']
    rows = read_csv(path, ['benchmark', 'configuration', 'status'] + names)
    return [dict(benchmark=r['benchmark'], configuration=r['configuration'],
                 **{k: integer(r, k) for k in names}, status=r['status']) for r in rows]


def analyze_hardware(path):
    rows = read_csv(path, ['benchmark', 'configuration', 'status', 'memory_mhz'] + RAW)
    results = []
    for r in rows:
        c = {k: integer(r, k) for k in RAW}
        cycles, bundles, instructions = (c[k] for k in ('cycles', 'bundles', 'instructions'))
        freq = float(r['memory_mhz'])
        if not 20 <= freq <= 50 or not cycles or bundles > cycles or instructions > 4 * bundles:
            raise ValueError(f"Contadores o frecuencia invalidos en {r['benchmark']}")
        stalls = c['cache_stall_cycles']
        phases = sum(c[k] for k in ('l2_lookup_stall_cycles', 'memory_stall_cycles', 'buffer_stall_cycles'))
        if phases > stalls or stalls + c['branch_stall_cycles'] > cycles or c['mem_busy_cycles'] > cycles:
            raise ValueError('Los ciclos de stall/ocupacion no son consistentes')
        result = dict(benchmark=r['benchmark'], configuration=r['configuration'], memory_mhz=freq, **c)
        result['ipc'] = ratio(instructions, cycles)
        result['bundle_rate'] = ratio(bundles, cycles)
        result['cache_stall_pct'] = 100 * stalls / cycles
        for level in ('l1', 'l2'):
            for kind in ('read', 'write', 'total'):
                hits = sum(c[f'{level}_{k}_hits'] for k in ('read', 'write')) if kind == 'total' else c[f'{level}_{kind}_hits']
                misses = sum(c[f'{level}_{k}_misses'] for k in ('read', 'write')) if kind == 'total' else c[f'{level}_{kind}_misses']
                access = hits + misses
                result[f'{level}_{kind}_accesses'] = access
                result[f'{level}_{kind}_hit_rate'] = ratio(hits, access)
                result[f'{level}_{kind}_miss_rate'] = ratio(misses, access)
        result['memory_accesses'] = c['mem_reads'] + c['mem_writes']
        tmem = 25 + 7 * math.ceil(100 / freq)
        result['tmem_cycles'] = tmem
        result['mem_nominal_transfer_cycles'] = result['memory_accesses'] * tmem
        # AMAT teorico de lecturas: tasas locales de demanda, sin espera de buffers.
        # En NINE/write-through las escrituras de L2 no se mezclan con read misses.
        m1 = result['l1_read_miss_rate']
        m2 = result['l2_read_miss_rate']
        result['amat_read_model_cycles'] = (None if m1 is None else 1.0 if m1 == 0
                                             else None if m2 is None else 1 + m1 * (8 + m2 * tmem))
        # Una palabra de 4 bytes por ciclo de memoria es el pico teorico.
        result['bandwidth_utilization_pct'] = 100 * c['mem_words'] / (cycles * freq / 100)
        result['memory_bandwidth_bytes_s'] = c['mem_words'] * 4 * 100_000_000 / cycles
        result['status'] = r['status']
        results.append(result)
    return results


def fmt(v):
    if v is None:
        return 'N/D'
    return f'{v:.4f}' if isinstance(v, float) else str(v)


def save_csv(path, rows):
    with path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows({k: '' if v is None else v for k, v in r.items()} for r in rows)


def chart(path, rows, key, title, unit):
    # SVG sin dependencias externas: se puede abrir directamente en un navegador.
    values = [(f"{r['benchmark']} / {r['configuration']}", r[key]) for r in rows if r[key] is not None]
    if not values:
        return
    width, left, bar_width = 1000, 330, 530
    height = 105 + 44 * len(values)
    maximum = max(v for _, v in values) or 1
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
             '<rect width="100%" height="100%" fill="#ffffff"/>',
             f'<text x="24" y="32" font-size="20" font-family="sans-serif" fill="#172b4d">{escape(title)}</text>',
             f'<text x="24" y="54" font-size="13" font-family="sans-serif" fill="#526174">Unidad: {escape(unit)}</text>']
    for i, (label, value) in enumerate(values):
        y = 75 + i * 44
        color = ['#2563a6', '#7554a3', '#23816f'][i % 3]
        parts.extend([f'<text x="24" y="{y+18}" font-family="sans-serif" font-size="13">{escape(label)}</text>',
                      f'<rect x="{left}" y="{y}" width="{bar_width*value/maximum:.2f}" height="25" rx="3" fill="{color}"/>',
                      f'<text x="{left+bar_width*value/maximum+8:.2f}" y="{y+18}" font-family="sans-serif" font-size="13">{escape(fmt(value))}</text>'])
    path.write_text('\n'.join(parts + ['</svg>']), encoding='utf-8')


def table(path, rows, columns, intro):
    lines = ['# Resultados de rendimiento', '', intro, '',
             '| ' + ' | '.join(columns) + ' |', '| ' + ' | '.join(['---'] * len(columns)) + ' |']
    lines.extend('| ' + ' | '.join(fmt(r[k]) for k in columns) + ' |' for r in rows)
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--baseline', type=Path, help='CSV preliminar de tb_run')
    group.add_argument('--hardware', type=Path, help='CSV de contadores integrados')
    parser.add_argument('--out', type=Path, default=BASE / 'analysis')
    args = parser.parse_args()
    try:
        rows = analyze_baseline(args.baseline) if args.baseline else analyze_hardware(args.hardware)
        args.out.mkdir(parents=True, exist_ok=True)
        if args.baseline:
            save_csv(args.out / 'baseline_summary.csv', rows)
            table(args.out / 'baseline_report.md', rows, list(rows[0]),
                  'Procesador original sin cache ni latencia externa realista. Los ciclos provienen de tb_run y su criterio de fin; no son ciclos de retiro medidos. No se calculan IPC ni AMAT a partir de estos datos.')
            chart(args.out / 'baseline_cycles.svg', rows, 'tb_run_cycles', 'Ciclos reportados por tb_run (sin cache)', 'ciclos')
            chart(args.out / 'baseline_lines.svg', rows, 'unique_cache_lines', 'Lineas distintas previstas por benchmark', 'lineas de 32 bytes')
        else:
            save_csv(args.out / 'hardware_metrics.csv', rows)
            table(args.out / 'hardware_report.md', rows,
                  ['benchmark', 'configuration', 'cycles', 'instructions', 'ipc', 'l1_total_hit_rate', 'l2_total_hit_rate', 'amat_read_model_cycles', 'bandwidth_utilization_pct'],
                  'Tasas expresadas como fraccion de 0 a 1. AMAT teorico de lecturas; no incluye esperas de buffers. Los datos N/D corresponden a denominadores nulos.')
            for key, title, unit in [('cycles', 'Ciclos totales', 'ciclos'), ('ipc', 'IPC', 'instrucciones/ciclo'), ('l1_total_hit_rate', 'Hit rate L1', 'fraccion'), ('l2_total_hit_rate', 'Hit rate L2', 'fraccion'), ('amat_read_model_cycles', 'AMAT teorico de lectura', 'ciclos'), ('cache_stall_cycles', 'Stalls de cache', 'ciclos')]:
                chart(args.out / f'{key}.svg', rows, key, title, unit)
        print(f'OK: {len(rows)} resultados analizados en {args.out}')
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f'ERROR: {error}\n')


if __name__ == '__main__':
    main()
