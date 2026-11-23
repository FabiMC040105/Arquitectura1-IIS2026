#!/usr/bin/env bash
# Benchmarks de CPU + L1 + L2 + RAM.
# El CSV final solo se publica si los tres programas pasan.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

out=build/benchmarks
mkdir -p "$out"
rm -f "$out/hardware.csv" "$out/hardware.csv.tmp"

echo "=== Generando programas de prueba ==="
python3 python/generate_benchmarks.py \
    > "$out/generacion_hw.log" 2>&1

mapfile -t fuentes < <(
    sed -n '/^SRC =/,/^$/p' Makefile |
    grep -oE 'src/[^[:space:]\\]+\.sv'
)

for patron in sequential random stride; do
    echo "=== $patron ==="

    iverilog -g2012 -Wall \
        -s tb_benchmarks_hw \
        -o "$out/sim_hw_$patron" \
        "-DPROGRAM_FILE=\"$out/$patron.mem\"" \
        "-DDATA_FILE=\"$out/data.mem\"" \
        -DDUMP_PALABRAS=0 \
        -DMAX_CICLOS=100000 \
        tb/tb_benchmarks_hw.sv "${fuentes[@]}" \
        > "$out/compile_hw_$patron.log" 2>&1 || {
            tail -20 "$out/compile_hw_$patron.log"
            exit 1
        }

    vvp "$out/sim_hw_$patron" \
        "+BENCHMARK=$patron" \
        "+PERF_CSV=$out/raw_hw_$patron.csv" \
        > "$out/hw_$patron.log" 2>&1 || {
            tail -20 "$out/hw_$patron.log"
            exit 1
        }

    python3 python/generate_benchmarks.py \
        --check-log "$patron" "$out/hw_$patron.log"

    grep -E 'Programa terminado|Metricas RAW exportadas' \
        "$out/hw_$patron.log"
done

echo "=== Consolidando datos validados ==="

python3 - "$out" <<'PY'
import csv
import sys
from pathlib import Path

out = Path(sys.argv[1])
resultados = []
campos = None

for nombre in ("sequential", "random", "stride"):
    with (out / f"raw_hw_{nombre}.csv").open(newline="") as f:
        reader = csv.DictReader(f)
        filas = list(reader)

        if len(filas) != 1:
            raise SystemExit(f"ERROR: cantidad de filas en {nombre}")

        fila = filas[0]
        if fila["benchmark"] != nombre or fila["status"] != "RAW":
            raise SystemExit(f"ERROR: CSV inesperado para {nombre}")

        if campos is None:
            campos = reader.fieldnames
        elif campos != reader.fieldnames:
            raise SystemExit("ERROR: columnas CSV diferentes")

        # Los registros ya se verificaron con --check-log.
        fila["status"] = "PASS"
        resultados.append(fila)

with (out / "hardware.csv.tmp").open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=campos)
    writer.writeheader()
    writer.writerows(resultados)

print("OK: tres resultados validados")
PY

python3 python/analyze_performance.py \
    --hardware "$out/hardware.csv.tmp" \
    --out "$out/analysis-hardware"

mv "$out/hardware.csv.tmp" "$out/hardware.csv"

echo "=== RESULTADOS FINALES ==="
cat "$out/analysis-hardware/hardware_report.md"
echo "PASS: benchmarks y metricas generados"
