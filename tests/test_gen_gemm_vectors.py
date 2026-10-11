"""Independent checks of GEMM fixture arithmetic, layout, and reproducibility."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from gen_gemm_vectors import SUPPORTED_SIZES, gemm, generate_cases, render_vectors


class GemmVectorTests(unittest.TestCase):
    def test_directed_answers(self):
        for size in SUPPORTED_SIZES:
            with self.subTest(size=size):
                cases = {case["name"]: case for case in generate_cases(random_count=0, size=size)}
                self.assertEqual(len(cases), 10)
                for name, value in (("zero_a", 0), ("zero_b", 0), ("all_ones", size),
                                    ("max_positive_sum", size * 16384),
                                    ("max_negative_sum", size * -16256),
                                    ("positive_extremes", size * 16129)):
                    self.assertEqual(cases[name]["c"], [[value] * size for _ in range(size)])
                self.assertEqual(cases["left_identity"]["c"], cases["left_identity"]["b"])
                self.assertEqual(cases["right_identity"]["c"], cases["right_identity"]["a"])

    def test_original_eight_by_eight_patterns(self):
        cases = {case["name"]: case for case in generate_cases(random_count=0)}
        # Closed forms preserve an independently derived check of the original fixtures.
        self.assertEqual(cases["signed_ramp"]["c"],
                         [[192 * row + 228 * col - 64 * row * col - 1020
                           for col in range(8)] for row in range(8)])
        self.assertEqual(cases["mixed_sign"]["c"],
                         [[(-1) ** row * (256 * row + 132 + 4 * col)
                           for col in range(8)] for row in range(8)])

    def test_one_hot_operands_select_rows_and_columns(self):
        for size in SUPPORTED_SIZES:
            matrix = generate_cases(seed=42, random_count=1, size=size)[-1]["a"]
            for index in range(size):
                with self.subTest(size=size, index=index):
                    selector = [[0] * size for _ in range(size)]
                    selector[size - 1][index] = 1
                    expected = [[0] * size for _ in range(size)]
                    expected[size - 1] = matrix[index]
                    self.assertEqual(gemm(selector, matrix), expected)
                    selector = [[0] * size for _ in range(size)]
                    selector[index][size - 1] = 1
                    expected = [[matrix[row][index] if col == size - 1 else 0
                                 for col in range(size)] for row in range(size)]
                    self.assertEqual(gemm(matrix, selector), expected)

    def test_invalid_operands(self):
        for size in SUPPORTED_SIZES:
            zero = [[0] * size for _ in range(size)]
            for bad in (zero[:-1], [[0] * (size - 1) for _ in range(size)],
                        [[128] * size for _ in range(size)], [[-129] * size for _ in range(size)],
                        [[True] * size for _ in range(size)]):
                with self.subTest(size=size), self.assertRaises(ValueError):
                    gemm(bad, zero)
                with self.subTest(size=size), self.assertRaises(ValueError):
                    gemm(zero, bad)
        with self.assertRaises(ValueError):
            gemm([[0] * 8 for _ in range(8)], [[0] * 16 for _ in range(16)])
        for size in (0, 7, 24, 64, True, 8.0):
            with self.subTest(size=size), self.assertRaises(ValueError):
                generate_cases(size=size)
        for count in (-1, True, 1.5):
            with self.assertRaises(ValueError):
                generate_cases(random_count=count)
        with self.assertRaises(ValueError):
            generate_cases(seed=True)

    def test_default_suite_and_reproducibility(self):
        for size in SUPPORTED_SIZES:
            with self.subTest(size=size):
                cases = generate_cases(size=size)
                self.assertEqual(len(cases), 110)
                pairs = {tuple(value for key in ("a", "b") for row in case[key] for value in row)
                         for case in cases[10:]}
                self.assertEqual(len(pairs), 100)
                self.assertEqual(cases, generate_cases(size=size))
                other = generate_cases(seed=42, size=size)
                self.assertEqual(cases[:10], other[:10])
                self.assertNotEqual(cases[10:], other[10:])

    def test_hex_layout_and_independent_product(self):
        for size in SUPPORTED_SIZES:
            with self.subTest(size=size):
                words = size * size
                files = render_vectors(seed=19, random_count=3, size=size)
                self.assertEqual(files, render_vectors(seed=19, random_count=3, size=size))
                manifest = json.loads(files["vectors_manifest.json"])
                self.assertEqual(manifest["format"], "gemm-vectors-v2")
                self.assertEqual(manifest["matrix_dim"], size)
                self.assertEqual(manifest["words_per_case"], words)
                self.assertEqual(manifest["case_count"], 13)
                self.assertEqual(manifest["seed"], 19)
                self.assertEqual(manifest["input_bits"], 8)
                self.assertEqual(manifest["result_bits"], 32)
                self.assertIn("CASE_COUNT = 13;", files["gemm_vectors.svh"])
                self.assertIn(f"VECTOR_MATRIX_DIM = {size};", files["gemm_vectors.svh"])
                self.assertIn(f"VECTOR_WORDS_PER_CASE = {words};", files["gemm_vectors.svh"])
                decoded = {}
                for filename, bits in (("inputs_a.hex", 8), ("inputs_b.hex", 8),
                                       ("expected.hex", 32)):
                    tokens = files[filename].split()
                    self.assertEqual(len(tokens), 13 * words)
                    self.assertTrue(all(len(token) == bits // 4 for token in tokens))
                    values = [int(token, 16) for token in tokens]
                    decoded[filename] = [value - (1 << bits) if value >= (1 << (bits - 1))
                                         else value for value in values]
                cases = generate_cases(seed=19, random_count=3, size=size)
                self.assertEqual(manifest["cases"], [case["name"] for case in cases])
                for index, case in enumerate(cases):
                    start = index * words
                    a = decoded["inputs_a.hex"][start:start + words]
                    b = decoded["inputs_b.hex"][start:start + words]
                    expected = decoded["expected.hex"][start:start + words]
                    self.assertEqual(a, [value for row in case["a"] for value in row])
                    self.assertEqual(b, [value for row in case["b"] for value in row])
                    # Outer products traverse the multiplication differently from the generator.
                    actual = [0] * words
                    for k in range(size):
                        for row in range(size):
                            for col in range(size):
                                actual[row * size + col] += a[row * size + k] * b[k * size + col]
                    self.assertEqual(expected, actual)

    def test_cli_check_detects_stale_files(self):
        script = Path(__file__).with_name("gen_gemm_vectors.py")
        with tempfile.TemporaryDirectory() as directory:
            command = [sys.executable, str(script), "--size", "32", "--seed", "123",
                       "--random-count", "0", "--out-dir", directory]
            subprocess.run(command, check=True, capture_output=True, text=True)
            subprocess.run(command + ["--check"], check=True, capture_output=True, text=True)
            changed = Path(directory) / "expected.hex"
            changed.write_text("00000001\n", encoding="ascii")
            result = subprocess.run(command + ["--check"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("expected.hex", result.stderr)
            self.assertEqual(changed.read_text(encoding="ascii"), "00000001\n")
            wrong_size = command.copy()
            wrong_size[wrong_size.index("--size") + 1] = "24"
            result = subprocess.run(wrong_size, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
