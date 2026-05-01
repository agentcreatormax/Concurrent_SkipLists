#!/bin/bash
# Run comprehensive benchmarks for all list implementations

set -e

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$BENCHMARK_DIR/results"
CSV_DIR="$RESULTS_DIR/csv"
mkdir -p "$RESULTS_DIR"
mkdir -p "$CSV_DIR"

DURATION=2.0
RUNS=3
MAX_LEVEL=13
IMPLEMENTATIONS="finegrain lockfree hashtbl"
THREAD_COUNTS="1 2 4 6 8 10 12 13 14 15"

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
CSV_FILE="$CSV_DIR/high_contains.csv"
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
CSV_FILE="$CSV_DIR/equal_ratios.csv"
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
CSV_FILE="$CSV_DIR/write_heavy.csv"
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

# Experiment 4: Varying contains ratio (12 threads)
echo "Experiment 4: Varying Contains Ratio (fixed 12 threads)"
CSV_FILE="$CSV_DIR/varying_contains.csv"
rm -f "$CSV_FILE"
echo "impl,threads,max_level,contains_pct,median,avg" > "$CSV_FILE"

for impl in $IMPLEMENTATIONS; do
  for contains in 0 10 20 30 40 50 60 70 80 90 100; do
    echo "  Running $impl with $contains% contains..."
    dune exec benchmarks/benchmark_skiplist.exe -- \
      --impl "$impl" \
      --threads 6 \
      --contains "$contains" \
      --max-level "$MAX_LEVEL" \
      --duration "$DURATION" \
      --runs "$RUNS" \
      --csv "$CSV_FILE" \
      2>&1 | tail -1
  done
done

RUNS=100000
IMPLEMENTATIONS="finegrain lockfree"
# THREAD_COUNTS="1 2 4 6 8 10 11"
INITIAL_SIZE=100
VALUE_RANGE=1000
# Experiment 5: Avg traversal length with equal ratios
echo "Experiment 5: Avg traversal length with equal ratios"
CSV_FILE="$CSV_DIR/avg_lengths_with_equal_ratios.csv"
rm -f "$CSV_FILE"
echo "impl,threads,max_level,contains_pct,avg_contains,avg_add,avg_remove" > "$CSV_FILE"
for impl in $IMPLEMENTATIONS; do
  for threads in $THREAD_COUNTS; do
    echo "  Running $impl with $threads..."
    dune exec benchmarks/benchmark_traversal_length.exe -- \
    --impl "$impl" \
    --threads "$threads" \
    --contains 34 \
    --runs "$RUNS" \
    --initial-size "$INITIAL_SIZE" \
    --value-range "$VALUE_RANGE" \
    --csv "$CSV_FILE" \
    2>&1 | tail -1
  done
done

# Experiment 6: Avg traversal length with heavy writing
echo "Experiment 6: Avg traversal length with Heavy writing(90%)"
CSV_FILE="$CSV_DIR/avg_lengths_with_heavy_writing.csv"
rm -f "$CSV_FILE"
echo "impl,threads,max_level,contains_pct,avg_contains,avg_add,avg_remove" > "$CSV_FILE"
for impl in $IMPLEMENTATIONS; do
  for threads in $THREAD_COUNTS; do
    echo "  Running $impl with $threads..."
    dune exec benchmarks/benchmark_traversal_length.exe -- \
    --impl "$impl" \
    --threads "$threads" \
    --contains 10 \
    --runs "$RUNS" \
    --initial-size "$INITIAL_SIZE" \
    --value-range "$VALUE_RANGE" \
    --csv "$CSV_FILE" \
    2>&1 | tail -1
  done
done

# Experiment 7: Avg traversal length with 90% reads
echo "Experiment 7: Avg traversal length with High Reads(90%)"
CSV_FILE="$CSV_DIR/avg_lengths_with_heavy_reading.csv"
rm -f "$CSV_FILE"
echo "impl,threads,max_level,contains_pct,avg_contains,avg_add,avg_remove" > "$CSV_FILE"
for impl in $IMPLEMENTATIONS; do
  for threads in $THREAD_COUNTS; do
    echo "  Running $impl with $threads..."
    dune exec benchmarks/benchmark_traversal_length.exe -- \
    --impl "$impl" \
    --threads "$threads" \
    --contains 90 \
    --runs "$RUNS" \
    --initial-size "$INITIAL_SIZE" \
    --value-range "$VALUE_RANGE" \
    --csv "$CSV_FILE" \
    2>&1 | tail -1
  done
done

echo ""
echo "Results saved to $CSV_FILE"
echo ""

echo "=== All benchmarks complete! ==="
echo "Results are in: $CSV_DIR"
