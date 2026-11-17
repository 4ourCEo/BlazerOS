from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
import validate_oanda_archive as validator  # noqa: E402


def candle(source_time: int, **overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "instrument": "EUR_USD",
        "granularity": "M1",
        "sourceTime": source_time,
        "complete": True,
        "bidOpen": 1.1,
        "bidHigh": 1.102,
        "bidLow": 1.099,
        "bidClose": 1.101,
        "askOpen": 1.1002,
        "askHigh": 1.1022,
        "askLow": 1.0992,
        "askClose": 1.1012,
    }
    value.update(overrides)
    return value


def batch(candles: list[dict[str, object]], **overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "instrument": "EUR_USD",
        "granularity": "M1",
        # Cocoa reference-date seconds: the fractional request endpoints cover
        # the :01 and :02 candles; includeFirst returns the candle covering from.
        "requestedFrom": 73.25,
        "requestedTo": 127.5,
        "candles": candles,
        "transport": {"ok": {}},
        "practiceOnlyRejected": False,
        "httpStatus": 200,
    }
    value.update(overrides)
    return value


def write_batch(root: Path, name: str, value: dict[str, object] | bytes) -> Path:
    path = root / name
    if isinstance(value, bytes):
        path.write_bytes(value)
    else:
        path.write_text(json.dumps(value, separators=(",", ":")), encoding="utf-8")
    return path


class ArchiveValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "historical-bid-ask"
        self.root.mkdir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_fractional_from_and_to_include_grid_boundary_candles(self) -> None:
        write_batch(self.root, "oanda-practice-EUR_USD-M1-1-2.json",
                    batch([candle(60), candle(120)]))
        manifest = validator.build_manifest(self.root)
        self.assertTrue(manifest["archiveIntegrityValid"])
        record = manifest["files"][0]
        self.assertEqual(record["requestFromGridFloorUTC"], "2001-01-01T00:01:00Z")
        self.assertEqual(record["requestToGridFloorUTC"], "2001-01-01T00:02:00Z")
        self.assertEqual(record["firstCandleUTC"], "2001-01-01T00:01:00Z")
        self.assertEqual(record["lastCandleUTC"], "2001-01-01T00:02:00Z")

    def test_candle_outside_aligned_request_bound_invalidates_batch(self) -> None:
        write_batch(self.root, "oanda-practice-EUR_USD-M1-1-2.json",
                    batch([candle(0)]))
        manifest = validator.build_manifest(self.root)
        self.assertFalse(manifest["archiveIntegrityValid"])
        self.assertIn("candle_outside_request_grid_bounds", manifest["files"][0]["issues"][0])

    def test_batch_envelope_rejects_bad_http_transport_practice_and_identity(self) -> None:
        cases = [
            ("http", {"httpStatus": 503}, "http_status_not_200"),
            ("null_http", {"httpStatus": None}, "http_status_not_200"),
            ("transport", {"transport": {"network": {}}}, "transport_not_ok"),
            ("practice", {"practiceOnlyRejected": True}, "practice_only_rejected_or_missing"),
            ("identity", {"instrument": "GBP_JPY"}, "filename_batch_identity_mismatch"),
            ("interval", {"requestedTo": 70}, "requested_interval_invalid"),
        ]
        for name, changes, expected in cases:
            with self.subTest(name=name):
                for child in self.root.iterdir():
                    child.unlink()
                payload = batch([candle(60)], **changes)
                path = write_batch(self.root, "oanda-practice-EUR_USD-M1-1-2.json", payload)
                record, _ = validator.validate_batch(path, path.name)
                self.assertFalse(record["valid"])
                self.assertTrue(any(issue.endswith(expected) for issue in record["issues"]))

    def test_m5_from_and_to_boundaries_use_five_minute_grid(self) -> None:
        value = batch([candle(300, granularity="M5"), candle(600, granularity="M5")],
                      granularity="M5", requestedFrom=313.25, requestedTo=617.5)
        write_batch(self.root, "oanda-practice-EUR_USD-M5-1-2.json", value)
        manifest = validator.build_manifest(self.root)
        self.assertTrue(manifest["archiveIntegrityValid"])
        record = manifest["files"][0]
        self.assertEqual(record["requestFromGridFloorUTC"], "2001-01-01T00:05:00Z")
        self.assertEqual(record["requestToGridFloorUTC"], "2001-01-01T00:10:00Z")

    def test_candle_identity_completeness_price_and_ordering_are_validated(self) -> None:
        cases = [
            ("instrument", [candle(60, instrument="GBP_JPY")], "candle_instrument_mismatch"),
            ("granularity", [candle(60, granularity="M5")], "candle_granularity_mismatch"),
            ("incomplete", [candle(60, complete=False)], "candle_incomplete"),
            ("bad_ohlc", [candle(60, bidHigh=1.0)], "candle_ohlc_invalid"),
            ("crossed", [candle(60, askClose=1.0)], "candle_bid_ask_crossed"),
            ("out_of_order", [candle(120), candle(60)], "candles_not_strictly_chronological"),
        ]
        for name, rows, expected in cases:
            with self.subTest(name=name):
                for child in self.root.iterdir():
                    child.unlink()
                path = write_batch(self.root, "oanda-practice-EUR_USD-M1-1-2.json", batch(rows))
                record, _ = validator.validate_batch(path, path.name)
                self.assertFalse(record["valid"])
                self.assertTrue(any(issue.endswith(expected) for issue in record["issues"]))

    def test_strict_json_rejects_duplicate_keys_nonfinite_and_trailing_data(self) -> None:
        for raw, expected in (
            (b'{"instrument":"EUR_USD","instrument":"GBP_JPY"}', "duplicate_json_key:instrument"),
            (b'{"price":NaN}', "non_finite_json_number:NaN"),
            (b'{"price":Infinity}', "non_finite_json_number:Infinity"),
            (b'{"price":1} trailing', "json_invalid"),
        ):
            with self.subTest(raw=raw):
                with self.assertRaises(validator.ValidationError) as error:
                    validator.strict_json(raw)
                self.assertIn(expected, str(error.exception))

    def test_exact_duplicates_are_reported_and_conflicts_invalidate(self) -> None:
        one = candle(60)
        write_batch(self.root, "oanda-practice-EUR_USD-M1-1-2.json", batch([one]))
        write_batch(self.root, "oanda-practice-EUR_USD-M1-3-4.json", batch([one]))
        manifest = validator.build_manifest(self.root)
        self.assertTrue(manifest["archiveIntegrityValid"])
        series = manifest["series"][0]
        self.assertEqual(series["exactDuplicateRows"], 1)
        self.assertEqual(series["uniqueTimestamps"], 1)

        for child in self.root.iterdir():
            child.unlink()
        conflicting = candle(60, bidClose=1.1005, askClose=1.1007)
        write_batch(self.root, "oanda-practice-EUR_USD-M1-1-2.json", batch([one]))
        write_batch(self.root, "oanda-practice-EUR_USD-M1-3-4.json", batch([conflicting]))
        manifest = validator.build_manifest(self.root)
        self.assertFalse(manifest["archiveIntegrityValid"])
        self.assertEqual(manifest["series"][0]["conflictingDuplicateRows"], 1)

    def test_duplicate_conflict_beyond_decimal_context_precision_is_detected(self) -> None:
        prices = ["1.101" + ("0" * 30) + digit for digit in ("1", "2")]
        for index, price in enumerate(prices):
            payload = json.dumps(batch([candle(60)]), separators=(",", ":"))
            payload = payload.replace('"bidClose":1.101,', f'"bidClose":{price},', 1)
            write_batch(self.root, f"oanda-practice-EUR_USD-M1-{index}-2.json",
                        payload.encode("utf-8"))
        manifest = validator.build_manifest(self.root)
        self.assertFalse(manifest["archiveIntegrityValid"])
        self.assertEqual(manifest["series"][0]["conflictingDuplicateRows"], 1)

    def test_signed_decimal_zero_has_one_exact_canonical_form(self) -> None:
        self.assertEqual(
            validator.normalized_value(validator.decimal.Decimal("0.000")),
            validator.normalized_value(validator.decimal.Decimal("-0E+20")),
        )

    def test_gap_is_reported_without_invalidating_data(self) -> None:
        write_batch(self.root, "oanda-practice-EUR_USD-M1-1-4.json",
                    batch([candle(60), candle(240)], requestedTo=247.5))
        manifest = validator.build_manifest(self.root)
        self.assertTrue(manifest["archiveIntegrityValid"])
        self.assertEqual(manifest["campaignReadiness"], "NOT_ASSESSED_BY_ARCHIVE_VALIDATOR")
        self.assertEqual(manifest["series"][0]["gapCount"], 1)
        self.assertEqual(manifest["series"][0]["gaps"][0]["missingExpectedGridCandles"], 2)

    def test_symlink_is_rejected_and_does_not_read_target(self) -> None:
        outside = Path(self.temp.name) / "outside.json"
        outside.write_text("{}", encoding="utf-8")
        link = self.root / "escape.json"
        link.symlink_to(outside)
        manifest = validator.build_manifest(self.root)
        self.assertFalse(manifest["archiveIntegrityValid"])
        self.assertEqual(manifest["issues"][0]["code"], "symlink_escape_rejected")

    def test_selected_root_symlink_is_rejected(self) -> None:
        link = Path(self.temp.name) / "root-link"
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(validator.ValidationError, "archive_root_symlink_rejected"):
            validator.build_manifest(link)

    def test_hashes_are_deterministic_and_path_set_serialization_is_pinned(self) -> None:
        write_batch(self.root, "b.json", batch([candle(60)]))
        write_batch(self.root, "a.json", batch([candle(120)]))
        first = validator.build_manifest(self.root)
        second = validator.build_manifest(self.root)
        expected = hashlib.sha256(b'["a.json","b.json"]').hexdigest()
        self.assertEqual(first["pathSetSHA256"], expected)
        self.assertEqual(first["manifestSHA256"], second["manifestSHA256"])
        self.assertNotIn("createdAt", first)
        self.assertEqual([r["relativePath"] for r in first["files"]], ["a.json", "b.json"])
        for record in first["files"]:
            source = self.root / record["relativePath"]
            self.assertEqual(record["sha256"], hashlib.sha256(source.read_bytes()).hexdigest())

    def test_output_refuses_to_overwrite_existing_file(self) -> None:
        write_batch(self.root, "oanda-practice-EUR_USD-M1-1-2.json", batch([candle(60)]))
        output = Path(self.temp.name) / "manifest.json"
        output.write_text("keep", encoding="utf-8")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = validator.main(["--root", str(self.root), "--output", str(output)])
        self.assertEqual(code, 2)
        self.assertEqual(output.read_text(encoding="utf-8"), "keep")
        self.assertIn("output_exists_refusing_overwrite", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
