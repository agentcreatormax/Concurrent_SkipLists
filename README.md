# Concurrent Skiplists 

A comparative study of concurrent set implementations in OCaml 5, built around three data structures: a **lock-free skip list**, a **fine-grained locking skip list**, and a **coarse-grained hash table**. The project includes correctness testing with QCheck-STM / QCheck-Lin, throughput benchmarks, and traversal-length analysis across varied workloads and thread counts.

---

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Implementations](#implementations)
  - [Lock-Free Skip List](#lock-free-skip-list)
  - [Fine-Grained Locking Skip List](#fine-grained-locking-skip-list)
  - [Coarse-Grained Hash Table (Baseline)](#coarse-grained-hash-table-baseline)
- [Building](#building)
- [Running Tests](#running-tests)
- [Benchmarks](#benchmarks)
  - [Throughput Benchmark](#throughput-benchmark)
  - [Traversal-Length Benchmark](#traversal-length-benchmark)
  - [Running All Experiments](#running-all-experiments)
- [Benchmark Experiments](#benchmark-experiments)
- [Results](#results)

---

## Overview

OCaml 5 introduced native support for **shared-memory parallelism** via `Domain` and `Atomic`. This project exploits those primitives to implement and compare concurrent ordered-set data structures:

| Implementation | Synchronisation | Ordered? | Notes |
|---|---|---|---|
| `lockfree_skiplist` | Lock-free CAS (atomic markable refs) | Yes | Harris-Herlihy-Shavit style |
| `finegrain_skiplist` | Per-node `Mutex` | Yes | Herlihy & Shavit textbook algorithm |
| `coarsegrain_hashtbl` | Single global `Mutex` | No | Baseline reference |

All three expose the same interface (`add`, `remove`, `contains`) so they are drop-in replacements in the benchmarks.

---

## Project Structure

```
concurrent_skiplists/
├── lib/                          # Core library
│   ├── atomic_markable_ref.ml    # AtomicMarkableReference primitive
│   ├── atomic_markable_ref.mli
│   ├── coarsegrain_hashtbl.ml    # Coarse-grained hash table (baseline)
│   ├── coarsegrain_hashtbl.mli
│   ├── finegrain_skiplist.ml     # Fine-grained locking skip list
│   ├── finegrain_skiplist.mli
│   ├── lockfree_skiplist.ml      # Lock-free skip list
│   ├── lockfree_skiplist.mli
│   └── dune
│
├── benchmarks/
│   ├── lib_with_stats/           # Instrumented variants (track traversal lengths)
│   │   ├── finegrain_skiplist_with_stats.ml
│   │   ├── finegrain_skiplist_with_stats.mli
│   │   ├── lockfree_skiplist_with_stats.ml
│   │   ├── lockfree_skiplist_with_stats.mli
│   │   └── dune
│   ├── benchmark_skiplist.ml          # Throughput benchmark
│   ├── benchmark_traversal_length.ml  # Traversal-length benchmark
│   ├── plot.py                        # Python plotting script
│   ├── run_benchmarks.sh              # Full experiment runner
│   └── dune
│
├── bin/
│   ├── main.ml
│   └── dune
│
├── test/
│   ├── qcheck_lin_lockfree_skiplist.ml    # Lin linearizability test for lockfree implementation
│   ├── qcheck_stm_lockfree_skiplist.ml    # STM state-machine test for lockfree implementation
│   ├── test_lockfree_skiplist.ml          # Unit tests
│   ├── qcheck_lin_finegrain_skiplist.ml   # Lin linearizability test for finegrain implementation
│   ├── qcheck_stm_finegrain_skiplist.ml   # STM state-machine test for finegrain implementation
│   ├── test_finegrain_skiplist.ml         # Unit tests
│   ├── Makefile
│   └── dune
│
├── dune-project
└── README.md
```

---

## Implementations

### Lock-Free Skip List

**File:** `lib/lockfree_skiplist.ml`  
**Primitive:** `lib/atomic_markable_ref.ml`

A non-blocking skip list based on the algorithm by Herlihy, Lev, Luchangco, and Shavit. Threads never hold locks; all synchronisation is done through compare-and-swap (CAS) operations on `Atomic_markable_ref` cells — an OCaml encoding of Java's `AtomicMarkableReference`.

Key design points:

- **Logical deletion** — a node is first *marked* (via CAS on its `next` pointer's mark bit) and then physically unlinked lazily during subsequent `find` traversals.
- **`find` with helping** — every call to `find` scans top-to-bottom and unlinks any marked nodes it encounters, assisting other threads.
- **Linearisation points** — `add` linearises at the bottom-level CAS that inserts the new node; `remove` linearises at the bottom-level CAS that marks it.
- **`contains` is wait-free** — it reads without any CAS and simply skips over marked nodes.

```
Interface:
  val create   : int -> t              (* max_level *)
  val add      : t -> int -> bool
  val remove   : t -> int -> bool
  val contains : t -> int -> bool
```

### Fine-Grained Locking Skip List

**File:** `lib/finegrain_skiplist.ml`

A skip list where each node carries its own `Mutex`. Writers lock a consistent (key-sorted) subset of predecessor nodes before splicing; readers (`contains`) are fully lock-free and rely on `fully_linked` and `marked` atomic flags.

Key design points:

- **Lock ordering** — all distinct predecessors are sorted by key before locking, preventing deadlock.
- **`fully_linked` flag** — an inserting thread sets this atomically after all levels are spliced, making the publish step visible to concurrent readers.
- **Two-phase remove** — the victim's `marked` flag is set first (under the node's own lock); physical unlinking follows after re-validating predecessors.

### Coarse-Grained Hash Table (Baseline)

**File:** `lib/coarsegrain_hashtbl.ml`

A thin wrapper around OCaml's stdlib `Hashtbl` protected by a single global `Mutex`. Serves as a simple, correct baseline to contextualise the scalability of the skip-list implementations. Does not maintain sorted order.

### Atomic Markable Reference

**File:** `lib/atomic_markable_ref.ml`

A generic `'a marked_ref Atomic.t` that packs a reference and a boolean mark into one atomic word, offering:

```ocaml
val create           : 'a -> bool -> 'a t
val get              : 'a t -> bool ref -> 'a      (* sets mark out-param *)
val get_reference    : 'a t -> 'a
val get_mark         : 'a t -> bool
val compare_and_set  : 'a t
                       -> expected_ref:'a -> new_ref:'a
                       -> expected_mark:bool -> new_mark:bool
                       -> bool
```

---

## Building

Requirements:

- OCaml ≥ 5.0 (for `Domain` and `Atomic`)
- [opam](https://opam.ocaml.org/)
- [Dune](https://dune.build/) build system
- `qcheck-lin` and `qcheck-stm` (for tests)

```bash
# Install dependencies
opam install qcheck qcheck-lin qcheck-stm

# Build the entire project
dune build
```

---

## Running Tests

### Unit Tests

```bash
dune test
```

### Linearizability Test (QCheck-Lin)

Checks that the lock-free skip list is **linearizable** — i.e., every concurrent execution is equivalent to some valid sequential execution.

```bash
dune exec test/qcheck_lin_lockfree_skiplist.exe
```

### State-Machine Test (QCheck-STM)

Verifies both sequential consistency and parallel correctness of the lock-free skip list against an `int list` reference model.

```bash
dune exec test/qcheck_stm_lockfree_skiplist.exe
```

Both tests run 1 000 random scenarios by default; all tests are expected to **pass**.

---

## Benchmarks

### Throughput Benchmark

**File:** `benchmarks/benchmark_skiplist.ml`

Spawns *N* OCaml `Domain`s; each domain repeatedly picks a random operation (`contains` / `add` / `remove`) according to the configured ratio and a random key from `[0, value_range)`. The benchmark runs for a fixed wall-clock duration, then reports median and average throughput (operations / second).

```bash
dune exec benchmarks/benchmark_skiplist.exe -- \
  --impl      lockfree   \   # lockfree | finegrain | hashtbl
  --threads   8          \
  --contains  90         \   # % of contains ops
  --duration  2.0        \   # seconds per run
  --max-level 13         \
  --initial-size 1000    \
  --value-range  10000   \
  --runs      3          \
  --csv       results/csv/out.csv
```

### Traversal-Length Benchmark

**File:** `benchmarks/benchmark_traversal_length.ml`  
**Instrumented libs:** `benchmarks/lib_with_stats/`

Measures the **average number of nodes visited** per operation. Each `add`, `remove`, and `contains` call returns a `(bool * int)` pair where the second component is the traversal length. This gives structural insight into how contention and list height affect path length.

```bash
dune exec benchmarks/benchmark_traversal_length.exe -- \
  --impl         lockfree \
  --threads      8        \
  --contains     34       \
  --runs         100000   \
  --initial-size 100      \
  --value-range  1000     \
  --csv          results/csv/lengths.csv
```

### Running All Experiments

The shell script automates all seven experiments and writes CSV files to `results/csv/`:

```bash
cd <project-root>
bash benchmarks/run_benchmarks.sh
```

---

## Benchmark Experiments

| # | Experiment | `--contains` | Threads | Output CSV |
|---|---|---|---|---|
| 1 | High read ratio | 90 % | 1–16 | `high_contains.csv` |
| 2 | Equal ratios | 34 % | 1–16 | `equal_ratios.csv` |
| 3 | Write-heavy | 10 % | 1–16 | `write_heavy.csv` |
| 4 | Varying contains ratio | 0–100 % | 12 (fixed) | `varying_contains.csv` |
| 5 | Traversal length — equal ratios | 34 % | 1–16 | `avg_lengths_with_equal_ratios.csv` |
| 6 | Traversal length — write-heavy | 10 % | 1–16 | `avg_lengths_with_heavy_writing.csv` |
| 7 | Traversal length — read-heavy | 90 % | 1–16 | `avg_lengths_with_heavy_reading.csv` |

Each throughput experiment: 2 s per run × 3 runs, 1 warm-up run, `max_level = 13`.  
Each traversal experiment: 100 000 ops per thread, `initial_size = 100`, `value_range = 1000`.

After running, generate plots with:

```bash
python3 benchmarks/plot.py
```

Plots are saved under `results/throughput_plots/` and `results/traversal_length-*/`.

---

## Results

Benchmark output CSVs and PNG plots are stored in `results/` after running the experiments:

```
results/
├── csv/
│   ├── high_contains.csv
│   ├── equal_ratios.csv
│   ├── write_heavy.csv
│   ├── varying_contains.csv
│   ├── avg_lengths_with_equal_ratios.csv
│   ├── avg_lengths_with_heavy_reading.csv
│   └── avg_lengths_with_heavy_writing.csv
├── throughput_plots/
│   ├── plot_high_contains.png
│   ├── plot_equal_ratios.png
│   ├── plot_write_heavy.png
│   └── plot_varying_contains.png
├── traversal_length-equal_ratios/
├── traversal_length-heavy_reading/
└── traversal_length-heavy_writing/
```