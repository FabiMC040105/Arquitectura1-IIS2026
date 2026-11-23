#!/usr/bin/env bash
# Ejecuta pruebas de lectura sobre CPU + L1 + L2 + RAM.
# Los resultados se guardan en build/benchmarks para no mezclar datos con el RTL.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

for tool in python3 make iverilog vvp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: falta instalar $tool" >&2
        exit 1
    fi
done

out=build/benchmarks
mkdir -p "$out"
# No dejamos un CSV anterior que parezca corresponder a una corrida fallida.
rm -f "$out/resultados_lecturas.csv" "$out/resultados_lecturas.csv.tmp"
trap 'rm -f "$out/resultados_lecturas.csv.tmp"' EXIT

# Primero comprobamos que los contadores sigan funcionando de forma aislada.
echo '=== Prueba de contadores ==='
iverilog -g2012 -Wall -s tb_performance -o "$out/sim_performance" \
    src/performance_counters.sv tb/tb_performance.sv
vvp "$out/sim_performance" | tee "$out/counters.log"
grep -Fq 'OK: todas las pruebas de contadores pasaron' "$out/counters.log"

# El generador usa una semilla fija y el ensamblador original del grupo.
echo '=== Preparando benchmarks ==='
python3 python/generate_benchmarks.py

for pattern in sequential random stride; do
    echo "=== Ejecutando $pattern con L1/L2/RAM ==="
    log="$out/${pattern}.log"
    if ! make run PROGRAM="$out/${pattern}.mem" DATA="$out/data.mem" FLAGS="-g2012 -Wall -DDUMP_PALABRAS=16 -DMAX_CICLOS=100000" > "$log" 2>&1; then
        tail -n 30 "$log" >&2
        echo "ERROR: fallo la simulacion de $pattern. Revisar $log" >&2
        exit 1
    fi
    # El tb_run puede terminar con un aviso sin devolver un codigo de error.
    # Por eso tambien comprobamos el fin normal y los registros esperados.
    python3 python/generate_benchmarks.py --check-log "$pattern" "$log"
done

# Solo se genera el resumen si las tres simulaciones pasaron.
# Los ciclos de tb_run incluyen su criterio de terminacion con NOPs.
python3 - "$out" <<'PY'
import csv
import json
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
manifest = json.loads((out / 'manifest.json').read_text())
fields = ['benchmark', 'configuration', 'expected_reads', 'unique_cache_lines',
          'rom_bundles', 'rom_bytes', 'tb_run_cycles', 'status']
with (out / 'resultados_lecturas.csv.tmp').open('w', newline='', encoding='ascii') as handle:
    writer = csv.DictWriter(handle, fieldnames=fields)
    writer.writeheader()
    for name in ('sequential', 'random', 'stride'):
        log = (out / f'{name}.log').read_text(encoding='utf-8', errors='replace')
        match = re.search(r'Programa terminado tras\s+(\d+)\s+ciclos', log)
        if match is None or int(match.group(1)) <= 0:
            raise SystemExit(f'ERROR: no se encontraron ciclos validos para {name}')
        item = manifest[name]
        writer.writerow({
            'benchmark': name,
            'configuration': 'l1_l2_ram',
            'expected_reads': item['reads'],
            'unique_cache_lines': item['unique_cache_lines'],
            'rom_bundles': item['program_bundles'],
            'rom_bytes': item['program_bundles'] * 16,
            'tb_run_cycles': int(match.group(1)),
            'status': 'PASS',
        })
(out / 'resultados_lecturas.csv.tmp').replace(out / 'resultados_lecturas.csv')
PY

echo '=== Resumen de las tres pruebas ==='
cat "$out/resultados_lecturas.csv"
echo "OK: resultados guardados en $out/resultados_lecturas.csv"
