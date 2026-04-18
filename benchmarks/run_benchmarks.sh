#!/bin/bash
# Run comprehensive benchmarks for all list implementations

set -e

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$BENCHMARK_DIR/results"
mkdir -p "$RESULTS_DIR"

DURATION=3.0
RUNS=3
MAX_LEVEL=16
IMPLEMENTATIONS="finegrain lockfree"
THREAD_COUNTS="1 2 4 8 12"

echo "=== Starting Comprehensive List Benchmarks ==="
echo "Duration: ${DURATION}s per run"
echo "Runs: $RUNS"
echo "Max_level: $MAX_LEVEL"
echo "Implementations: $IMPLEMENTATIONS"
echo "Thread counts: $THREAD_COUNTS"
echo ""

cd "$BENCHMARK_DIR"

# Experiment 1: High contains ratio (90%)
echo "Experiment 1: High Contains Ratio (90% read, 5% add, 5% remove)"
CSV_FILE="$RESULTS_DIR/high_contains.csv"
rm -f "$CSV_FILE"
echo "impl,threads,max_level,contains_pct,median,avg" > "$CSV_FILE"

for impl in $IMPLEMENTATIONS; do
  for threads in $THREAD_COUNTS; do
    echo "  Running $impl with $threads threads..."
    dune exec benchmarks/benchmark_skiplist.exe -- \
      --impl "$impl" \
      --threads "$threads" \
      --contains 90 \
      --max-level "$MAX_LEVEL" \
      --duration "$DURATION" \
      --runs "$RUNS" \
      --csv "$CSV_FILE" \
      2>&1 | tail -1
  done
done

echo ""
echo "Results saved to $CSV_FILE"
echo ""

# Experiment 2: (33/33/33) ratio
echo "Experiment 2: Equal Ratios (34% read, 33% add, 33% remove)"
CSV_FILE="$RESULTS_DIR/equal_ratios.csv"
rm -f "$CSV_FILE"
echo "impl,threads,max_level,contains_pct,median,avg" > "$CSV_FILE"

for impl in $IMPLEMENTATIONS; do
  for threads in $THREAD_COUNTS; do
    echo "  Running $impl with $threads threads..."
    dune exec benchmarks/benchmark_skiplist.exe -- \
      --impl "$impl" \
      --threads "$threads" \
      --contains 34 \
      --max-level "$MAX_LEVEL" \
      --duration "$DURATION" \
      --runs "$RUNS" \
      --csv "$CSV_FILE" \
      2>&1 | tail -1
  done
done

echo ""
echo "Results saved to $CSV_FILE"
echo ""

# Experiment 3: write heavy
echo "Experiment 3: Write Heavy Ratio (10% Read, 45% add, 45% remove)"
CSV_FILE="$RESULTS_DIR/write_heavy.csv"
rm -f "$CSV_FILE"
echo "impl,threads,max_level,contains_pct,median,avg" > "$CSV_FILE"

for impl in $IMPLEMENTATIONS; do
  for threads in $THREAD_COUNTS; do
    echo "  Running $impl with $threads threads..."
    dune exec benchmarks/benchmark_skiplist.exe -- \
      --impl "$impl" \
      --threads "$threads" \
      --contains 10 \
      --max-level "$MAX_LEVEL" \
      --duration "$DURATION" \
      --runs "$RUNS" \
      --csv "$CSV_FILE" \
      2>&1 | tail -1
  done
done

echo ""
echo "Results saved to $CSV_FILE"
echo ""

echo "=== All benchmarks complete! ==="
echo "Results are in: $RESULTS_DIR"
