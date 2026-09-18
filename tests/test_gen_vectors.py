"""Check the oracle with hand-derived answers and independently decode fixtures."""

import json
from pathlib import Path
import tempfile
import unittest

from gen_vectors import encode_signed, gemv, generate_cases, write_vectors


class ReferenceTests(unittest.TestCase):
    def test_directed_answers(self):
        # Fixed expectations are independent of the gemv implementation.
        expected = {
            "zero_matrix": [0] * 8,
            "zero_vector": [0] * 8,
            "identity": [-128, -17, -1, 0, 1, 23, 64, 127],
            "diagonal": [16384, 119, 1, 0, 1, 69, 1216, 16129],
            "asymmetric": [-97, -57, -17, 23, 63, 103, 143, 183],
            "mixed_sign": [204, -492, 780, -1068, 1356, -1644, 1932, -2220],
            "max_sum": [131072] * 8,
            "min_sum": [-130048] * 8,
            "positive_extremes": [129032] * 8,
            "last_column_only": [512, 384, 256, 128, 0, -128, -256, -384],
        }
        cases = generate_cases(random_count=0)
        self.assertEqual(set(expected), {case["name"] for case in cases})
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(case["y"], expected[case["name"]])

    def test_one_hot_vector_selects_column(self):
        matrix = generate_cases(seed=42, random_count=1)[-1]["a"]
        for column in range(8):
            vector = [0] * 8
            vector[column] = 1
            with self.subTest(column=column):
                self.assertEqual(gemv(matrix, vector), [row[column] for row in matrix])

    def test_invalid_inputs_are_rejected(self):
        matrix = [[0] * 8 for _ in range(8)]
        with self.assertRaises(ValueError):
            gemv(matrix[:7], [0] * 8)
        with self.assertRaises(ValueError):
            gemv([row[:7] for row in matrix], [0] * 8)
        with self.assertRaises(ValueError):
            gemv(matrix, [0] * 9)
        for value in [-129, 128, 1.0, True]:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    gemv(matrix, [value] + [0] * 7)
                bad_matrix = [[0] * 8 for _ in range(8)]
                bad_matrix[3][6] = value
                with self.assertRaises(ValueError):
                    gemv(bad_matrix, [0] * 8)
        with self.assertRaises(ValueError):
            generate_cases(random_count=-1)

    def test_known_hex_patterns_and_overflow(self):
        for value, bits, expected in [
            (-128, 8, "80"), (-1, 8, "ff"), (0, 8, "00"), (127, 8, "7f"),
            (-1, 32, "ffffffff"), (-130048, 32, "fffe0400"),
            (131072, 32, "00020000"), (-(1 << 31), 32, "80000000"),
            ((1 << 31) - 1, 32, "7fffffff"),
        ]:
            with self.subTest(value=value, bits=bits):
                self.assertEqual(encode_signed(value, bits), expected)
        for bits in [8, 32]:
            for value in [-(1 << (bits - 1)) - 1, 1 << (bits - 1)]:
                with self.assertRaises(ValueError):
                    encode_signed(value, bits)

    def test_every_int8_encoding(self):
        for value in range(-128, 128):
            raw = int(encode_signed(value, 8), 16)
            decoded = raw - 256 if raw >= 128 else raw
            self.assertEqual(decoded, value)

    def test_seed_reproducibility(self):
        first = generate_cases(seed=17, random_count=3)
        self.assertEqual(first, generate_cases(seed=17, random_count=3))
        self.assertNotEqual(first[-1]["a"], generate_cases(seed=18, random_count=3)[-1]["a"])
        self.assertEqual(first[:10], generate_cases(seed=18, random_count=0))

    def test_fixture_roundtrip_and_byte_reproducibility(self):
        cases = generate_cases(seed=17, random_count=3)
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first"
            second = Path(directory) / "second"
            write_vectors(cases, first, seed=17, random_count=3)
            write_vectors(generate_cases(seed=17, random_count=3), second, 17, 3)
            for filename in ["vectors.txt", "vectors.json"]:
                self.assertEqual((first / filename).read_bytes(), (second / filename).read_bytes())
            document = json.loads((first / "vectors.json").read_text())
            self.assertEqual(document["cases"], cases)
            self.assertEqual(document["case_count"], len(cases))
            words = (first / "vectors.txt").read_text().split()
            self.assertEqual(int(words[0], 10), len(cases))
            self.assertEqual(len(words), 1 + 80 * len(cases))
            for index, case in enumerate(cases):
                tokens = words[1 + 80 * index:1 + 80 * (index + 1)]
                decoded = []
                for position, token in enumerate(tokens):
                    bits = 8 if position < 72 else 32
                    self.assertEqual(len(token), bits // 4)
                    raw = int(token, 16)
                    decoded.append(raw - (1 << bits) if raw >= (1 << (bits - 1)) else raw)
                expected = [value for row in case["a"] for value in row] + case["x"] + case["y"]
                self.assertEqual(decoded, expected)


if __name__ == "__main__":
    unittest.main()
