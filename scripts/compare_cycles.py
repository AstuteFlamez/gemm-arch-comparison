#!/usr/bin/env python3
"""Compare scheduled cycles and useful MAC utilization for the supported GEMM sizes."""

import argparse

from plot_gemm_ppa import ARCHITECTURES, SIZES, scheduled_cycles


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sizes", type=int, choices=SIZES, nargs="+", default=list(SIZES),
                        help="matrix dimensions to compare (default: 8 16 32)")
    args = parser.parse_args(argv)

    print("Schedule-based useful MAC utilization: N^3 / (4 MACs x cycles).")
    print("Accepted start to done; external input loading/readback excluded.")
    print(f"{'Size':>7}  {'Architecture':<13}  {'Cycles':>8}  {'Utilization':>11}")
    for size in args.sizes:
        for architecture in ARCHITECTURES:
            cycles = scheduled_cycles(size, architecture)
            utilization = 100 * size ** 3 / (4 * cycles)
            print(f"{size:>3}x{size:<3}  {architecture:<13}  {cycles:>8}  {utilization:>10.2f}%")


if __name__ == "__main__":
    main()
