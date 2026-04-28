#!/usr/bin/env python3
"""
Plot benchmark results for the concurrent skip list benchmarks.
Generates plots that match the CSV files produced by run_benchmarks.sh:
1. High Contains Ratio
2. Equal Ratios
3. Write Heavy
"""

import csv
import matplotlib.pyplot as plt
from pathlib import Path

# Style configuration for the benchmarked skip list implementations.
IMPL_STYLES = {
    'lockfree': {'label': 'Lock-free', 'marker': 's', 'color': 'black', 'linestyle': '--'},
    'finegrain': {'label': 'Fine-grained', 'marker': 'o', 'color': 'red', 'linestyle': '-'},
    'hashtbl': {'label': 'Hashtbl(coarsegrain)', 'marker': 'v', 'color': 'blue', 'linestyle': '-.'},
}

def read_csv(filename):
    """Read CSV file and return data grouped by implementation."""
    data = {}
    with open(filename, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            impl = row['impl']
            if impl not in data:
                data[impl] = {'threads': [], 'contains_pct': [], 'median': [], 'avg': []}
            data[impl]['threads'].append(int(row['threads']))
            data[impl]['contains_pct'].append(int(row['contains_pct']))
            data[impl]['median'].append(float(row['median']))
            data[impl]['avg'].append(float(row['avg']))
    return data

def read_csv_traversal(filename):
    """Read CSV file and return data grouped by implementation."""
    data = {}
    with open(filename, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            impl = row['impl']
            if impl not in data:
                data[impl] = {'threads': [], 'contains_pct': [], 'avg_contains': [], 'avg_add': [], 'avg_remove' : []}
            data[impl]['threads'].append(int(row['threads']))
            data[impl]['contains_pct'].append(int(row['contains_pct']))
            data[impl]['avg_contains'].append(float(row['avg_contains']))
            data[impl]['avg_add'].append(float(row['avg_add']))
            data[impl]['avg_remove'].append(float(row['avg_remove']))
    return data

def plot_thread_scaling(csv_file, title, output_file):
    """Plot throughput vs thread count."""
    data = read_csv(csv_file)

    fig, ax = plt.subplots(figsize=(8, 6))

    # Plot each implementation
    for impl in ['finegrain', 'lockfree', 'hashtbl']:
        if impl in data:
            style = IMPL_STYLES[impl]
            threads = data[impl]['threads']
            throughput = data[impl]['median']

            ax.plot(threads, throughput,
                   marker=style['marker'],
                   color=style['color'],
                   linestyle=style['linestyle'],
                   markersize=8,
                   linewidth=2,
                   label=style['label'])

    ax.set_xlabel('threads', fontsize=12)
    ax.set_ylabel('Ops/sec', fontsize=12)
    ax.set_title(title, fontsize=14, fontweight='bold')
    ax.legend(loc='upper left', fontsize=10)
    ax.grid(True, alpha=0.3)

    # Format y-axis with scientific notation
    ax.ticklabel_format(style='scientific', axis='y', scilimits=(0,0))

    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved {output_file}")
    plt.close()

def plot_contains_mix(csv_file, title, output_file):
    """Plot throughput vs contains percentage."""
    data = read_csv(csv_file)

    fig, ax = plt.subplots(figsize=(8, 6))

    # Plot each implementation
    for impl in ['finegrain', 'lockfree', 'hashtbl']:
        if impl in data:
            style = IMPL_STYLES[impl]
            contains_pct = data[impl]['contains_pct']
            throughput = data[impl]['median']

            ax.plot(contains_pct, throughput,
                   marker=style['marker'],
                   color=style['color'],
                   linestyle=style['linestyle'],
                   markersize=8,
                   linewidth=2,
                   label=style['label'])

    ax.set_xlabel('% Contains()', fontsize=12)
    ax.set_ylabel('Ops/sec', fontsize=12)
    ax.set_title(title, fontsize=14, fontweight='bold')
    ax.legend(loc='upper left', fontsize=10)
    ax.grid(True, alpha=0.3)

    # Format y-axis with scientific notation
    ax.ticklabel_format(style='scientific', axis='y', scilimits=(0,0))

    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved {output_file}")
    plt.close()

def plot_thread_scaling_traversal(csv_file, title, output_file, length_type):
    """Plot traversal length vs thread count."""
    data = read_csv_traversal(csv_file)

    fig, ax = plt.subplots(figsize=(8, 6))

    # Plot each implementation
    for impl in ['finegrain', 'lockfree']:
        if impl in data:
            style = IMPL_STYLES[impl]
            threads = data[impl]['threads']
            length = data[impl][length_type]

            ax.plot(threads, length,
                   marker=style['marker'],
                   color=style['color'],
                   linestyle=style['linestyle'],
                   markersize=8,
                   linewidth=2,
                   label=style['label'])

    ax.set_xlabel('threads', fontsize=12)
    ax.set_ylabel('avg-traversal-length', fontsize=12)
    ax.set_title(title, fontsize=14, fontweight='bold')
    ax.legend(loc='upper left', fontsize=10)
    ax.grid(True, alpha=0.3)

    # Format y-axis with scientific notation
    ax.ticklabel_format(style='scientific', axis='y', scilimits=(0,0))

    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Saved {output_file}")
    plt.close()

def main():
    # Get script directory and construct results path relative to it
    script_dir = Path(__file__).parent.absolute()
    results_dir = script_dir.parent / 'results'

    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}")
        return

    print("Generating plots...")

    # Plot 1: High Contains Ratio
    high_csv = results_dir / 'high_contains.csv'
    if high_csv.exists():
        plot_thread_scaling(
            high_csv,
            'High Contains Ratio (90%)',
            results_dir / 'plot_high_contains.png'
        )
    else:
        print(f"Warning: {high_csv} not found")

    # Plot 2: Equal Ratios
    equal_csv = results_dir / 'equal_ratios.csv'
    if equal_csv.exists():
        plot_thread_scaling(
            equal_csv,
            'Equal Ratios (34% contains / 33% add / 33% remove)',
            results_dir / 'plot_equal_ratios.png'
        )
    else:
        print(f"Warning: {equal_csv} not found")

    # Plot 3: Write Heavy
    write_heavy_csv = results_dir / 'write_heavy.csv'
    if write_heavy_csv.exists():
        plot_thread_scaling(
            write_heavy_csv,
            'Write Heavy Ratio (10% contains / 45% add / 45% remove)',
            results_dir / 'plot_write_heavy.png'
        )
    else:
        print(f"Warning: {write_heavy_csv} not found")

    # Plot 4: Varying Contains Ratio
    varying_csv = results_dir / 'varying_contains.csv'
    if varying_csv.exists():
        plot_contains_mix(
            varying_csv,
            'Varing Contains',
            results_dir / 'plot_varying_contains.png'
        )
    else:
        print(f"Warning: {varying_csv} not found")

    # Plot 5: Contains traversal length (equal ratios)
    length_csv = results_dir / 'avg_lengths_with_equal_ratios.csv'
    if length_csv.exists():
        plot_thread_scaling_traversal(
            length_csv,
            'Avg traversal length in Contains op with Equal ratios',
            results_dir / 'plot_avg_contains_length.png',
            'avg_contains'
        )
    else:
        print(f"Warning: {length_csv} not found")

    # Plot 6: Add traversal length (equal ratios)
    length_csv = results_dir / 'avg_lengths_with_equal_ratios.csv'
    if length_csv.exists():
        plot_thread_scaling_traversal(
            length_csv,
            'Avg traversal length in Add op with Equal ratios',
            results_dir / 'plot_avg_add_length.png',
            'avg_add'
        )
    else:
        print(f"Warning: {length_csv} not found")
    
    # Plot 7: Remove traversal length (equal ratios)
    length_csv = results_dir / 'avg_lengths_with_equal_ratios.csv'
    if length_csv.exists():
        plot_thread_scaling_traversal(
            length_csv,
            'Avg traversal length in Remove op with Equal ratios',
            results_dir / 'plot_remove_contains_length.png',
            'avg_remove'
        )
    else:
        print(f"Warning: {length_csv} not found")

    print("\nAll plots generated successfully!")

if __name__ == '__main__':
    main()
