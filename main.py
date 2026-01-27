import subprocess
import itertools
import json
import re
import time
import statistics
from pathlib import Path
from typing import Final, Literal
from tqdm import tqdm
import matplotlib.pyplot as plt
from pydantic import BaseModel

PROJECT_ROOT: Final[Path] = Path(__file__).parent
BINARY: Final[Path] = PROJECT_ROOT / "zig-out/bin/zig_thread_test"
CONFIG_PATH: Final[Path] = PROJECT_ROOT / "config.json"
PLOTS_DIR: Final[Path] = PROJECT_ROOT / "plots"
PLOTS_DIR.mkdir(exist_ok=True)

NUM_RUNS = 5
THREAD_COUNTS = [2, 4, 8, 16, 32, 64]
MATRIX_SIZES = [256, 512, 1024, 2048]
PRIME_NS = [5, 6, 7, 8]

Schedule = Literal["sequential", "chunked", "cyclic", "dynamic"]
SCHEDULES = ["chunked", "cyclic", "dynamic"]

TIME_RE = re.compile(r"Timing \(ns\):\s*(\d+)")


class MatrixConfig(BaseModel):
    run: bool
    schedule: Schedule
    M: int
    N: int
    P: int


class PrimeConfig(BaseModel):
    run: bool
    schedule: Schedule
    N: int


class Config(BaseModel):
    n_threads: int
    matrix: MatrixConfig
    prime: PrimeConfig


def placeholder_matrix():
    return MatrixConfig(run=False, schedule="sequential", M=1, N=1, P=1)


def placeholder_prime():
    return PrimeConfig(run=False, schedule="sequential", N=1)


def write_config(cfg: Config):
    with open(CONFIG_PATH, "w") as f:
        json.dump(cfg.model_dump(), f, indent=2)


def run_binary() -> int:
    proc = subprocess.run(
        [str(BINARY)],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
    )

    # Zig prints to STDERR
    output = proc.stdout + proc.stderr

    m = TIME_RE.search(output)
    if not m:
        print("FULL OUTPUT:\n", output)
        raise RuntimeError("Timing not found in output")

    return int(m.group(1))


def averaged_time(cfg: Config) -> float:
    times = []
    for _ in range(NUM_RUNS):
        write_config(cfg)
        times.append(run_binary())
        time.sleep(0.05)
    return statistics.mean(times) / 1e6  # Convert ns to ms


def run_matrix_bench():
    results = []
    total = len(MATRIX_SIZES) * len(THREAD_COUNTS) * len(SCHEDULES)
    
    for size, threads, sched in tqdm(
        itertools.product(MATRIX_SIZES, THREAD_COUNTS, SCHEDULES),
        desc="Matrix benchmarks",
        unit="run",
        total=total,
    ):
        cfg = Config(
            n_threads=threads,
            matrix=MatrixConfig(run=True, schedule=sched, M=size, N=size, P=size),
            prime=placeholder_prime(),
        )
        results.append((size, threads, sched, averaged_time(cfg)))
    return results


def run_prime_bench():
    results = []
    total = len(PRIME_NS) * len(THREAD_COUNTS) * len(SCHEDULES)
    
    for n_exp, threads, sched in tqdm(
        itertools.product(PRIME_NS, THREAD_COUNTS, SCHEDULES),
        desc="Prime benchmarks",
        unit="run",
        total=total,
    ):
        cfg = Config(
            n_threads=threads,
            matrix=placeholder_matrix(),
            prime=PrimeConfig(run=True, schedule=sched, N=n_exp),
        )
        results.append((n_exp, threads, sched, averaged_time(cfg)))
    return results


COLORS = {
    "chunked": "#A23B72",
    "cyclic": "#F18F01",
    "dynamic": "#06A77D",
}

MARKERS = {
    "chunked": "s",
    "cyclic": "^",
    "dynamic": "d",
}


def plot_matrix_results(results):
    """Create 2x2 subplot for matrix multiplication results"""
    fig, axes = plt.subplots(2, 2, figsize=(15, 10))
    fig.suptitle(
        "Matrix Multiplication Performance Analysis", fontsize=16, fontweight="bold"
    )
    
    # Plot 1: Performance vs Threads (512x512)
    ax1 = axes[0, 0]
    matrix_size = 512
    
    for sched in SCHEDULES:
        data = sorted(
            (th, t) for (sz, th, sc, t) in results if sz == matrix_size and sc == sched
        )
        if data:
            x_vals = [d[0] for d in data]
            y_vals = [d[1] for d in data]
            ax1.plot(
                x_vals,
                y_vals,
                marker=MARKERS[sched],
                linewidth=2,
                markersize=8,
                label=sched.capitalize(),
                color=COLORS[sched],
            )
    
    ax1.set_xlabel("Number of Threads", fontsize=11)
    ax1.set_ylabel("Duration (ms)", fontsize=11)
    ax1.set_title(f"Performance vs Threads (Matrix Size: {matrix_size}x{matrix_size})", fontsize=12)
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    ax1.set_xscale("log", base=2)
    
    # Plot 2: Performance vs Threads (1024x1024)
    ax2 = axes[0, 1]
    matrix_size = 1024
    
    for sched in SCHEDULES:
        data = sorted(
            (th, t) for (sz, th, sc, t) in results if sz == matrix_size and sc == sched
        )
        if data:
            x_vals = [d[0] for d in data]
            y_vals = [d[1] for d in data]
            ax2.plot(
                x_vals,
                y_vals,
                marker=MARKERS[sched],
                linewidth=2,
                markersize=8,
                label=sched.capitalize(),
                color=COLORS[sched],
            )
    
    ax2.set_xlabel("Number of Threads", fontsize=11)
    ax2.set_ylabel("Duration (ms)", fontsize=11)
    ax2.set_title(f"Performance vs Threads (Matrix Size: {matrix_size}x{matrix_size})", fontsize=12)
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    ax2.set_xscale("log", base=2)
    
    # Plot 3: Performance vs Matrix Size (8 threads)
    ax3 = axes[1, 0]
    thread_count = 8
    
    for sched in SCHEDULES:
        data = sorted(
            (sz, t) for (sz, th, sc, t) in results if th == thread_count and sc == sched
        )
        if data:
            x_vals = [d[0] for d in data]
            y_vals = [d[1] for d in data]
            ax3.plot(
                x_vals,
                y_vals,
                marker=MARKERS[sched],
                linewidth=2,
                markersize=8,
                label=sched.capitalize(),
                color=COLORS[sched],
            )
    
    ax3.set_xlabel("Matrix Size (rows)", fontsize=11)
    ax3.set_ylabel("Duration (ms)", fontsize=11)
    ax3.set_title(f"Performance vs Matrix Size (Threads: {thread_count})", fontsize=12)
    ax3.legend()
    ax3.grid(True, alpha=0.3)
    
    # Plot 4: Performance vs Matrix Size (16 threads)
    ax4 = axes[1, 1]
    thread_count = 16
    
    for sched in SCHEDULES:
        data = sorted(
            (sz, t) for (sz, th, sc, t) in results if th == thread_count and sc == sched
        )
        if data:
            x_vals = [d[0] for d in data]
            y_vals = [d[1] for d in data]
            ax4.plot(
                x_vals,
                y_vals,
                marker=MARKERS[sched],
                linewidth=2,
                markersize=8,
                label=sched.capitalize(),
                color=COLORS[sched],
            )
    
    ax4.set_xlabel("Matrix Size (rows)", fontsize=11)
    ax4.set_ylabel("Duration (ms)", fontsize=11)
    ax4.set_title(f"Performance vs Matrix Size (Threads: {thread_count})", fontsize=12)
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(PLOTS_DIR / "matrix_performance_analysis.png", dpi=300, bbox_inches="tight")
    plt.close()
    print(f"Saved plot: {PLOTS_DIR / 'matrix_performance_analysis.png'}")


def plot_prime_results(results):
    """Create 2x2 subplot for prime counting results"""
    fig, axes = plt.subplots(2, 2, figsize=(15, 10))
    fig.suptitle(
        "Prime Counting Performance Analysis", fontsize=16, fontweight="bold"
    )
    
    # Plot 1: Performance vs Threads (10^6)
    ax1 = axes[0, 0]
    n_exp = 6
    
    for sched in SCHEDULES:
        data = sorted(
            (th, t) for (n, th, sc, t) in results if n == n_exp and sc == sched
        )
        if data:
            x_vals = [d[0] for d in data]
            y_vals = [d[1] for d in data]
            ax1.plot(
                x_vals,
                y_vals,
                marker=MARKERS[sched],
                linewidth=2,
                markersize=8,
                label=sched.capitalize(),
                color=COLORS[sched],
            )
    
    ax1.set_xlabel("Number of Threads", fontsize=11)
    ax1.set_ylabel("Duration (ms)", fontsize=11)
    ax1.set_title(f"Performance vs Threads (N: 10^{n_exp})", fontsize=12)
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    ax1.set_xscale("log", base=2)
    
    # Plot 2: Performance vs Threads (10^7)
    ax2 = axes[0, 1]
    n_exp = 7
    
    for sched in SCHEDULES:
        data = sorted(
            (th, t) for (n, th, sc, t) in results if n == n_exp and sc == sched
        )
        if data:
            x_vals = [d[0] for d in data]
            y_vals = [d[1] for d in data]
            ax2.plot(
                x_vals,
                y_vals,
                marker=MARKERS[sched],
                linewidth=2,
                markersize=8,
                label=sched.capitalize(),
                color=COLORS[sched],
            )
    
    ax2.set_xlabel("Number of Threads", fontsize=11)
    ax2.set_ylabel("Duration (ms)", fontsize=11)
    ax2.set_title(f"Performance vs Threads (N: 10^{n_exp})", fontsize=12)
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    ax2.set_xscale("log", base=2)
    
    # Plot 3: Performance vs Problem Size (8 threads)
    ax3 = axes[1, 0]
    thread_count = 8
    
    for sched in SCHEDULES:
        data = sorted(
            (n, t) for (n, th, sc, t) in results if th == thread_count and sc == sched
        )
        if data:
            x_vals = [10**d[0] for d in data]  # Convert exponent to actual value for x-axis
            y_vals = [d[1] for d in data]
            ax3.plot(
                x_vals,
                y_vals,
                marker=MARKERS[sched],
                linewidth=2,
                markersize=8,
                label=sched.capitalize(),
                color=COLORS[sched],
            )
    
    ax3.set_xlabel("Problem Size (N)", fontsize=11)
    ax3.set_ylabel("Duration (ms)", fontsize=11)
    ax3.set_title(f"Performance vs Problem Size (Threads: {thread_count})", fontsize=12)
    ax3.legend()
    ax3.grid(True, alpha=0.3)
    ax3.set_xscale("log")
    
    # Plot 4: Performance vs Problem Size (16 threads)
    ax4 = axes[1, 1]
    thread_count = 16
    
    for sched in SCHEDULES:
        data = sorted(
            (n, t) for (n, th, sc, t) in results if th == thread_count and sc == sched
        )
        if data:
            x_vals = [10**d[0] for d in data]  # Convert exponent to actual value for x-axis
            y_vals = [d[1] for d in data]
            ax4.plot(
                x_vals,
                y_vals,
                marker=MARKERS[sched],
                linewidth=2,
                markersize=8,
                label=sched.capitalize(),
                color=COLORS[sched],
            )
    
    ax4.set_xlabel("Problem Size (N)", fontsize=11)
    ax4.set_ylabel("Duration (ms)", fontsize=11)
    ax4.set_title(f"Performance vs Problem Size (Threads: {thread_count})", fontsize=12)
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    ax4.set_xscale("log")
    
    plt.tight_layout()
    plt.savefig(PLOTS_DIR / "prime_performance_analysis.png", dpi=300, bbox_inches="tight")
    plt.close()
    print(f"Saved plot: {PLOTS_DIR / 'prime_performance_analysis.png'}")


def print_summary(results, result_type="matrix"):
    """Print performance summary statistics"""
    print(f"\n=== {result_type.capitalize()} Performance Summary ===\n")
    
    if result_type == "matrix":
        sizes = sorted(set(sz for sz, _, _, _ in results))
        for size in sizes:
            print(f"Matrix Size: {size}x{size}")
            data_size = [(th, sc, t) for (sz, th, sc, t) in results if sz == size]
            
            for sched in SCHEDULES:
                sched_data = [(th, t) for (th, sc, t) in data_size if sc == sched]
                if sched_data:
                    best_time = min(t for _, t in sched_data)
                    best_threads = [th for th, t in sched_data if t == best_time][0]
                    print(f"  {sched.capitalize():11s}: Best = {best_time:.2f} ms @ {best_threads} threads")
            print()
    else:  # prime
        ns = sorted(set(n for n, _, _, _ in results))
        for n in ns:
            print(f"Problem Size: 10^{n}")
            data_size = [(th, sc, t) for (nx, th, sc, t) in results if nx == n]
            
            for sched in SCHEDULES:
                sched_data = [(th, t) for (th, sc, t) in data_size if sc == sched]
                if sched_data:
                    best_time = min(t for _, t in sched_data)
                    best_threads = [th for th, t in sched_data if t == best_time][0]
                    print(f"  {sched.capitalize():11s}: Best = {best_time:.2f} ms @ {best_threads} threads")
            print()


if __name__ == "__main__":
    print("Starting benchmarks...")
    print(f"Binary: {BINARY}")
    print(f"Config: {CONFIG_PATH}")
    print(f"Output: {PLOTS_DIR}\n")
    
    # Run matrix benchmarks
    print("Running matrix multiplication benchmarks...")
    matrix = run_matrix_bench()
    
    # Run prime benchmarks
    print("\nRunning prime counting benchmarks...")
    primes = run_prime_bench()
    
    # Generate plots
    print("\nGenerating plots...")
    plot_matrix_results(matrix)
    plot_prime_results(primes)
    
    # Print summaries
    print_summary(matrix, "matrix")
    print_summary(primes, "prime")
    
    print("\nBenchmarks complete!")
