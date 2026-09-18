#!/usr/bin/env python3
"""Independent integer reference model and fixtures for fixed 8x8 INT8 GEMV."""

import argparse
import json
from pathlib import Path
import random

SIZE = 8
DEFAULT_SEED = 20260917
DEFAULT_RANDOM_COUNT = 100


def gemv(matrix, vector):
    """Compute eight exact integer dot products, without modeling RTL cycles."""
    if len(matrix) != SIZE or any(len(row) != SIZE for row in matrix):
        raise ValueError("matrix must have exactly 8 rows and 8 columns")
    if len(vector) != SIZE:
        raise ValueError("vector must have exactly 8 elements")
    for value in [item for row in matrix for item in row] + list(vector):
        if type(value) is not int or not -128 <= value <= 127:
            raise ValueError("every operand must be a Python integer in [-128, 127]")

    results = []
    for row in range(SIZE):
        total = 0
        for column in range(SIZE):
            total += matrix[row][column] * vector[column]
        results.append(total)
    return results


def encode_signed(value, bits):
    """Encode a signed integer as fixed-width two's-complement hexadecimal."""
    if bits not in (8, 32):
        raise ValueError("fixture words must be 8 or 32 bits")
    if type(value) is not int or not -(1 << (bits - 1)) <= value < (1 << (bits - 1)):
        raise ValueError(f"value {value!r} does not fit signed {bits} bits")
    return f"{value & ((1 << bits) - 1):0{bits // 4}x}"


def constant_matrix(value):
    return [[value for _ in range(SIZE)] for _ in range(SIZE)]


def make_case(name, matrix, vector):
    return {"name": name, "a": matrix, "x": vector, "y": gemv(matrix, vector)}


def generate_cases(seed=DEFAULT_SEED, random_count=DEFAULT_RANDOM_COUNT):
    if type(seed) is not int:
        raise ValueError("seed must be an integer")
    if type(random_count) is not int or random_count < 0:
        raise ValueError("random_count must be a nonnegative integer")

    signed_values = [-128, -17, -1, 0, 1, 23, 64, 127]
    asymmetric = [[8 * row + column - 32 for column in range(SIZE)]
                  for row in range(SIZE)]
    diagonal_values = [-128, -7, -1, 0, 1, 3, 19, 127]
    cases = [
        make_case("zero_matrix", constant_matrix(0), signed_values),
        make_case("zero_vector", asymmetric, [0] * SIZE),
        make_case("identity", [[int(row == column) for column in range(SIZE)]
                               for row in range(SIZE)], signed_values),
        make_case("diagonal", [[diagonal_values[row] if row == column else 0
                               for column in range(SIZE)] for row in range(SIZE)],
                  signed_values),
        make_case("asymmetric", asymmetric, [-3, -2, -1, 0, 1, 2, 3, 5]),
        make_case("mixed_sign", [[(-1 if (row + column) % 2 else 1)
                                 * (8 * row + column + 1)
                                 for column in range(SIZE)] for row in range(SIZE)],
                  [1, -2, 3, -4, 5, -6, 7, -8]),
        make_case("max_sum", constant_matrix(-128), [-128] * SIZE),
        make_case("min_sum", constant_matrix(-128), [127] * SIZE),
        make_case("positive_extremes", constant_matrix(127), [127] * SIZE),
        make_case("last_column_only", [[0] * 7 + [row - 4] for row in range(SIZE)],
                  [1, 2, 3, 4, 5, 6, 7, -128]),
    ]

    # A local RNG makes unrelated random calls elsewhere irrelevant to this seed.
    rng = random.Random(seed)
    for index in range(random_count):
        matrix = [[rng.randint(-128, 127) for _ in range(SIZE)] for _ in range(SIZE)]
        vector = [rng.randint(-128, 127) for _ in range(SIZE)]
        cases.append(make_case(f"random_{index:04d}", matrix, vector))
    return cases


def write_vectors(cases, output_dir, seed, random_count):
    """Write decimal JSON for inspection and hex text for SV/C consumers."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    lines = [str(len(cases))]  # Decimal case count; all subsequent tokens are hex.
    for case in cases:
        for row in case["a"]:
            lines.append(" ".join(encode_signed(value, 8) for value in row))
        lines.append(" ".join(encode_signed(value, 8) for value in case["x"]))
        lines.append(" ".join(encode_signed(value, 32) for value in case["y"]))
    (output_dir / "vectors.txt").write_text("\n".join(lines) + "\n", encoding="ascii")

    document = {
        "format": "gemv-vectors-v1",
        "seed": seed,
        "random_count": random_count,
        "case_count": len(cases),
        "cases": cases,
    }
    (output_dir / "vectors.json").write_text(
        json.dumps(document, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--random-count", type=int, default=DEFAULT_RANDOM_COUNT)
    parser.add_argument("--out-dir", type=Path, default=Path("build/vectors"))
    args = parser.parse_args()
    if args.random_count < 0:
        parser.error("--random-count must be nonnegative")
    cases = generate_cases(args.seed, args.random_count)
    write_vectors(cases, args.out_dir, args.seed, args.random_count)
    print(f"Generated {len(cases)} cases: {len(cases) - args.random_count} directed"
          f" + {args.random_count} random; seed={args.seed}")
    print(f"Fixtures: {args.out_dir / 'vectors.txt'} and {args.out_dir / 'vectors.json'}")


if __name__ == "__main__":
    main()
