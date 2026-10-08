"""Independent checks of the FPGA fixture arithmetic, layout, and reproducibility."""

import json
import unittest

from gen_gemm_vectors import gemm, generate_cases, render_vectors


class GemmVectorTests(unittest.TestCase):
    def test_directed_answers(self):
        cases = {case["name"]: case for case in generate_cases(random_count=0)}
        self.assertEqual(len(cases), 10)
        for name, value in (("zero_a", 0), ("zero_b", 0), ("all_ones", 8),
                            ("max_positive_sum", 131072), ("max_negative_sum", -130048),
                            ("positive_extremes", 129032)):
            self.assertEqual(cases[name]["c"], [[value] * 8 for _ in range(8)])
        self.assertEqual(cases["left_identity"]["c"], cases["left_identity"]["b"])
        self.assertEqual(cases["right_identity"]["c"], cases["right_identity"]["a"])
        # Closed form for the original ramp pair, derived from sum(k)=28, sum(k^2)=140.
        self.assertEqual(cases["signed_ramp"]["c"],
                         [[192 * row + 228 * col - 64 * row * col - 1020
                           for col in range(8)] for row in range(8)])
        # Alternating-sign row times the reverse ramp simplifies to this constant.
        self.assertEqual(cases["mixed_sign"]["c"],
                         [[(-1) ** row * (256 * row + 132 + 4 * col)
                           for col in range(8)] for row in range(8)])

    def test_one_hot_operands_select_rows_and_columns(self):
        matrix = generate_cases(seed=42, random_count=1)[-1]["a"]
        for index in range(8):
            selector = [[0] * 8 for _ in range(8)]
            selector[7][index] = 1
            expected = [[0] * 8 for _ in range(8)]
            expected[7] = matrix[index]
            self.assertEqual(gemm(selector, matrix), expected)
            selector = [[0] * 8 for _ in range(8)]
            selector[index][3] = 1
            expected = [[matrix[row][index] if col == 3 else 0 for col in range(8)]
                        for row in range(8)]
            self.assertEqual(gemm(matrix, selector), expected)

    def test_invalid_operands(self):
        zero = [[0] * 8 for _ in range(8)]
        for bad in (zero[:7], [[0] * 7 for _ in range(8)],
                    [[128] * 8 for _ in range(8)], [[-129] * 8 for _ in range(8)],
                    [[True] * 8 for _ in range(8)]):
            with self.assertRaises(ValueError):
                gemm(bad, zero)
            with self.assertRaises(ValueError):
                gemm(zero, bad)
        with self.assertRaises(ValueError):
            generate_cases(random_count=-1)

    def test_default_suite_and_reproducibility(self):
        cases = generate_cases()
        self.assertEqual(len(cases), 110)
        random_cases = cases[10:]
        pairs = {tuple(value for key in ("a", "b") for row in case[key] for value in row)
                 for case in random_cases}
        self.assertEqual(len(pairs), 100)
        self.assertEqual(cases, generate_cases())
        other = generate_cases(seed=42)
        self.assertEqual(cases[:10], other[:10])
        self.assertNotEqual(cases[10:], other[10:])

    def test_hex_layout_and_independent_product(self):
        files = render_vectors(seed=19, random_count=3)
        self.assertEqual(files, render_vectors(seed=19, random_count=3))
        manifest = json.loads(files["vectors_manifest.json"])
        self.assertEqual(manifest["case_count"], 13)
        self.assertIn("CASE_COUNT = 13;", files["gemm_vectors.svh"])
        decoded = {}
        for filename, bits in (("inputs_a.hex", 8), ("inputs_b.hex", 8), ("expected.hex", 32)):
            tokens = files[filename].split()
            self.assertEqual(len(tokens), 13 * 64)
            self.assertTrue(all(len(token) == bits // 4 for token in tokens))
            values = [int(token, 16) for token in tokens]
            decoded[filename] = [value - (1 << bits) if value >= (1 << (bits - 1)) else value
                                 for value in values]
        cases = generate_cases(seed=19, random_count=3)
        for index, case in enumerate(cases):
            start = index * 64
            a = decoded["inputs_a.hex"][start:start + 64]
            b = decoded["inputs_b.hex"][start:start + 64]
            expected = decoded["expected.hex"][start:start + 64]
            self.assertEqual(a, [value for row in case["a"] for value in row])
            self.assertEqual(b, [value for row in case["b"] for value in row])
            # Outer-product accumulation provides a different traversal than the generator.
            actual = [0] * 64
            for k in range(8):
                for row in range(8):
                    for col in range(8):
                        actual[row * 8 + col] += a[row * 8 + k] * b[k * 8 + col]
            self.assertEqual(expected, actual)


if __name__ == "__main__":
    unittest.main()
