# Programming Assignment 3: Batch Bounded Blocking Queue
# Student Makefile

.PHONY: all build test clean help test-manual test-lin test-stm-seq test-stm-conc

all: build

build:
	dune build

test-all: test test-finegrain

test: test-manual test-lin test-stm-seq test-stm-conc

test-finegrain: test-manual-finegrain test-lin-finegrain test-stm-seq-finegrain test-stm-conc-finegrain

test-manual:
	@echo "=== Running Lockfree Manual Tests ==="
	dune exec ./test_lockfree_skiplist.exe

test-manual-finegrain:
	@echo "=== Running Fine-Grain Manual Tests ==="
	dune exec ./test_finegrain_skiplist.exe

test-lin:
	@echo ""
	@echo "=== Running QCheck-Lin Linearizability Test ==="
	dune exec ./qcheck_lin_lockfree_skiplist.exe

test-lin-finegrain:
	@echo ""
	@echo "=== Running QCheck-Lin Fine-Grain Linearizability Test ==="
	dune exec ./qcheck_lin_finegrain_skiplist.exe

test-stm-seq:
	@echo ""
	@echo "=== Running QCheck-STM Sequential Test ==="
	dune exec ./qcheck_stm_lockfree_skiplist.exe -- sequential

test-stm-seq-finegrain:
	@echo ""
	@echo "=== Running QCheck-STM Sequential Fine-Grain Test ==="
	dune exec ./qcheck_stm_finegrain_skiplist.exe -- sequential

test-stm-conc:
	@echo ""
	@echo "=== Running QCheck-STM Concurrent Test ==="
	dune exec ./qcheck_stm_lockfree_skiplist.exe -- concurrent

test-stm-conc-finegrain:
	@echo ""
	@echo "=== Running QCheck-STM Concurrent Fine-Grain Test ==="
	dune exec ./qcheck_stm_finegrain_skiplist.exe -- concurrent

clean:
	dune clean

help:
	@echo "Available targets:"
	@echo "  make build                   - Build the project"
	@echo "  make test                    - Run all tests"
	@echo "  make test-manual             - Run manual concurrent tests"
	@echo "  make test-lin                - Run QCheck-Lin linearizability test"
	@echo "  make test-stm-seq            - Run QCheck-STM sequential test"
	@echo "  make test-stm-conc           - Run QCheck-STM concurrent test"
	@echo "  make clean                   - Remove build artifacts"
	@echo ""
	@echo "  make test-manual-finegrain   - Run fine-grain manual tests"
	@echo "  make test-lin-finegrain      - Run fine-grain QCheck-Lin test"
	@echo "  make test-stm-seq-finegrain  - Run fine-grain QCheck-STM sequential test"
	@echo "  make test-stm-conc-finegrain - Run fine-grain QCheck-STM concurrent test"
	@echo ""
	@echo " make test-all"                - Run both fine-grain and lockfree tests