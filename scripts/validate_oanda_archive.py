#!/usr/bin/env python3
"""Read-only integrity manifest for OANDA candle archive batches.

The tool validates local JSON only. A path/name containing "oanda-practice" is
reported as an archive label, not authenticated broker provenance.
"""

from __future__ import annotations

import argparse
import datetime as dt
import decimal
import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any


TOOL_VERSION = "1"
SCHEMA_VERSION = 1
UTC = dt.timezone.utc
COCOA_EPOCH = dt.datetime(2001, 1, 1, tzinfo=UTC)
UNIX_EPOCH = dt.datetime(1970, 1, 1, tzinfo=UTC)
GRANULARITY_SECONDS = {"M1": 60, "M5": 300}
PRICE_FIELDS = (
    "bidOpen", "bidHigh", "bidLow", "bidClose",
    "askOpen", "askHigh", "askLow", "askClose",
)
REQUIRED_BATCH_FIELDS = {
    "instrument", "granularity", "requestedFrom", "requestedTo",
    "candles", "transport", "practiceOnlyRejected", "httpStatus",
}


class ValidationError(Exception):
    pass


def reject_constant(value: str) -> None:
    raise ValidationError(f"non_finite_json_number:{value}")


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValidationError(f"duplicate_json_key:{key}")
        result[key] = value
    return result


def strict_json(data: bytes) -> Any:
    try:
        source = data.decode("utf-8", errors="strict")
        return json.loads(
            source,
            object_pairs_hook=unique_object,
            parse_constant=reject_constant,
            parse_float=decimal.Decimal,
            parse_int=decimal.Decimal,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, decimal.InvalidOperation) as exc:
        raise ValidationError("json_invalid") from exc


def decimal_value(value: Any) -> decimal.Decimal | None:
    if isinstance(value, decimal.Decimal):
        return value if value.is_finite() else None
    if isinstance(value, int) and not isinstance(value, bool):
        return decimal.Decimal(value)
    return None


def date_from_cocoa_seconds(value: Any) -> dt.datetime | None:
    seconds = decimal_value(value)
    if seconds is None:
        return None
    micros = int((seconds * decimal.Decimal(1_000_000)).to_integral_value(
        rounding=decimal.ROUND_HALF_EVEN
    ))
    try:
        return COCOA_EPOCH + dt.timedelta(microseconds=micros)
    except OverflowError:
        return None


def datetime_to_unix_micros(value: dt.datetime) -> int:
    delta = value.astimezone(UTC) - UNIX_EPOCH
    return ((delta.days * 86_400 + delta.seconds) * 1_000_000) + delta.microseconds


def utc_string(value: dt.datetime | None) -> str | None:
    if value is None:
        return None
    value = value.astimezone(UTC)
    base = value.strftime("%Y-%m-%dT%H:%M:%S")
    return f"{base}.{value.microsecond:06d}Z" if value.microsecond else f"{base}Z"


def floor_grid(value: dt.datetime, step_seconds: int) -> dt.datetime:
    micros = datetime_to_unix_micros(value)
    step_micros = step_seconds * 1_000_000
    floored = (micros // step_micros) * step_micros
    return UNIX_EPOCH + dt.timedelta(microseconds=floored)


def normalized_value(value: Any) -> Any:
    """Comparable exact JSON value; Decimal numbers have canonical text."""
    if isinstance(value, decimal.Decimal):
        if not value.is_finite():
            raise ValidationError("non_finite_json_number")
        sign, coefficient, exponent = value.as_tuple()
        digits = list(coefficient)
        if not any(digits):
            # JSON numeric equality treats +0 and -0 as the same value.
            return {"$number": [0, "0", 0]}
        while len(digits) > 1 and digits[-1] == 0:
            digits.pop()
            exponent += 1
        return {"$number": [sign, "".join(str(digit) for digit in digits), exponent]}
    if isinstance(value, dict):
        return {key: normalized_value(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [normalized_value(item) for item in value]
    return value


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
        allow_nan=False,
    ).encode("utf-8")


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def transport_is_ok(value: Any) -> bool:
    return isinstance(value, dict) and value == {"ok": {}}


def validate_candle(candle: Any, *, instrument: str, granularity: str,
                    earliest: dt.datetime, latest: dt.datetime) -> tuple[list[str], dt.datetime | None]:
    issues: list[str] = []
    if not isinstance(candle, dict):
        return ["candle_not_object"], None

    if candle.get("instrument") != instrument:
        issues.append("candle_instrument_mismatch")
    if candle.get("granularity") != granularity:
        issues.append("candle_granularity_mismatch")
    if candle.get("complete") is not True:
        issues.append("candle_incomplete")

    source_time = date_from_cocoa_seconds(candle.get("sourceTime"))
    if source_time is None:
        issues.append("candle_timestamp_invalid")
        return issues, None

    step = GRANULARITY_SECONDS[granularity]
    source_us = datetime_to_unix_micros(source_time)
    if source_us % (step * 1_000_000) != 0:
        issues.append("candle_timestamp_off_grid")
    if source_time < earliest or source_time > latest:
        issues.append("candle_outside_request_grid_bounds")

    values: dict[str, decimal.Decimal] = {}
    for field in PRICE_FIELDS:
        number = decimal_value(candle.get(field))
        if number is None or number <= 0:
            issues.append(f"{field}_invalid")
        else:
            values[field] = number

    if len(values) == len(PRICE_FIELDS):
        if (values["bidHigh"] < max(values["bidOpen"], values["bidClose"])
                or values["bidLow"] > min(values["bidOpen"], values["bidClose"])
                or values["askHigh"] < max(values["askOpen"], values["askClose"])
                or values["askLow"] > min(values["askOpen"], values["askClose"])):
            issues.append("candle_ohlc_invalid")
        for side in ("Open", "High", "Low", "Close"):
            if values[f"bid{side}"] >= values[f"ask{side}"]:
                issues.append("candle_bid_ask_crossed")
                break
    return issues, source_time


def file_entries(root: Path) -> tuple[list[tuple[Path, str]], list[dict[str, str]]]:
    entries: list[tuple[Path, str]] = []
    issues: list[dict[str, str]] = []
    try:
        children = sorted(root.iterdir(), key=lambda path: path.name)
    except OSError as exc:
        raise ValidationError(f"archive_root_unreadable:{type(exc).__name__}") from exc

    root_real = root.resolve(strict=True)
    for path in children:
        if path.suffix.lower() != ".json":
            continue
        relative = path.relative_to(root).as_posix()
        try:
            item_stat = path.lstat()
        except OSError as exc:
            issues.append({"path": relative, "code": f"path_stat_failed:{type(exc).__name__}"})
            continue
        if stat.S_ISLNK(item_stat.st_mode):
            try:
                target = path.resolve(strict=True)
                target.relative_to(root_real)
                code = "symlink_rejected"
            except (OSError, ValueError):
                code = "symlink_escape_rejected"
            issues.append({"path": relative, "code": code})
            continue
        if not stat.S_ISREG(item_stat.st_mode):
            issues.append({"path": relative, "code": "non_regular_json_path"})
            continue
        entries.append((path, relative))
    return entries, sorted(issues, key=lambda item: (item["path"], item["code"]))


def read_one(path: Path) -> tuple[bytes | None, str | None]:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, "rb") as stream:
            before = os.fstat(stream.fileno())
            data = stream.read()
            after = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or not stat.S_ISREG(after.st_mode):
            return None, "input_not_regular_file"
        before_state = (before.st_dev, before.st_ino, before.st_size,
                        before.st_mtime_ns, before.st_ctime_ns)
        after_state = (after.st_dev, after.st_ino, after.st_size,
                       after.st_mtime_ns, after.st_ctime_ns)
        if before_state != after_state:
            return None, "input_identity_changed_during_read"
        if len(data) != after.st_size:
            return None, "input_size_changed_during_read"
        try:
            path_state = os.stat(path, follow_symlinks=False)
        except OSError:
            return None, "input_path_changed_during_read"
        if stat.S_ISLNK(path_state.st_mode) or (path_state.st_dev, path_state.st_ino) != (after.st_dev, after.st_ino):
            return None, "input_path_changed_during_read"
        return data, None
    except OSError as exc:
        return None, f"input_read_failed:{type(exc).__name__}"


def validate_batch(path: Path, relative: str) -> tuple[dict[str, Any], list[tuple[str, dt.datetime, Any]]]:
    data, read_issue = read_one(path)
    if data is None:
        return ({"relativePath": relative, "sha256": None, "valid": False,
                 "issues": [read_issue or "input_read_failed"]}, [])

    file_digest = digest(data)
    record: dict[str, Any] = {
        "relativePath": relative,
        "sha256": file_digest,
        "sourceLabel": "PRACTICE_LABEL_FROM_FILENAME" if "practice" in path.name.lower() else "UNSPECIFIED_FILENAME_LABEL",
        "valid": True,
        "issues": [],
    }
    parsed: Any
    try:
        parsed = strict_json(data)
    except ValidationError as exc:
        record["valid"] = False
        record["issues"].append(str(exc))
        return record, []

    issues: list[str] = []
    if not isinstance(parsed, dict):
        record["valid"] = False
        record["issues"] = ["batch_not_object"]
        return record, []

    missing = sorted(REQUIRED_BATCH_FIELDS - parsed.keys())
    if missing:
        issues.extend(f"batch_field_missing:{name}" for name in missing)

    instrument = parsed.get("instrument")
    granularity = parsed.get("granularity")
    if not isinstance(instrument, str) or not instrument:
        issues.append("batch_instrument_invalid")
        instrument = ""
    if granularity not in GRANULARITY_SECONDS:
        issues.append("batch_granularity_unsupported")
        granularity = ""

    requested_from = date_from_cocoa_seconds(parsed.get("requestedFrom"))
    requested_to = date_from_cocoa_seconds(parsed.get("requestedTo"))
    if requested_from is None:
        issues.append("requested_from_invalid")
    if requested_to is None:
        issues.append("requested_to_invalid")
    if requested_from is not None and requested_to is not None and requested_to <= requested_from:
        issues.append("requested_interval_invalid")

    if parsed.get("transport") != {"ok": {}}:
        issues.append("transport_not_ok")
    if parsed.get("httpStatus") != decimal.Decimal(200):
        issues.append("http_status_not_200")
    if parsed.get("practiceOnlyRejected") is not False:
        issues.append("practice_only_rejected_or_missing")

    name_match = re.fullmatch(
        r"oanda-practice-([A-Z0-9_]+)-(M1|M5)-(\d+)-(\d+)\.json",
        path.name,
    )
    if name_match:
        if name_match.group(1) != instrument or name_match.group(2) != granularity:
            issues.append("filename_batch_identity_mismatch")

    candles = parsed.get("candles")
    if not isinstance(candles, list):
        issues.append("candles_not_array")
        candles = []

    source_records: list[tuple[str, dt.datetime, Any]] = []
    batch_source_times: list[dt.datetime] = []
    boundary_floor_from = boundary_floor_to = None
    if requested_from is not None and requested_to is not None and granularity:
        step = GRANULARITY_SECONDS[granularity]
        boundary_floor_from = floor_grid(requested_from, step)
        boundary_floor_to = floor_grid(requested_to, step)
        if boundary_floor_to < boundary_floor_from:
            issues.append("request_grid_bounds_invalid")
    record.update({
        "instrument": instrument or None,
        "granularity": granularity or None,
        "requestedFromUTC": utc_string(requested_from),
        "requestedToUTC": utc_string(requested_to),
        "rawCandles": len(candles),
        "firstCandleUTC": None,
        "lastCandleUTC": None,
        "exactDuplicateCandles": 0,
        "conflictingDuplicateCandles": 0,
    })
    if boundary_floor_from is not None:
        record["requestFromGridFloorUTC"] = utc_string(boundary_floor_from)
    if boundary_floor_to is not None:
        record["requestToGridFloorUTC"] = utc_string(boundary_floor_to)

    previous: dt.datetime | None = None
    for index, candle in enumerate(candles):
        if not granularity:
            break
        candle_issues, candle_time = validate_candle(
            candle,
            instrument=instrument,
            granularity=granularity,
            earliest=boundary_floor_from or requested_from or COCOA_EPOCH,
            latest=boundary_floor_to or requested_to or COCOA_EPOCH,
        )
        issues.extend(f"candle[{index}]:{issue}" for issue in candle_issues)
        if candle_time is not None:
            batch_source_times.append(candle_time)
            if previous is not None and candle_time <= previous:
                issues.append("candles_not_strictly_chronological")
            previous = candle_time
            normalized = normalized_value(candle)
            source_records.append((instrument, candle_time, normalized))

    if batch_source_times:
        record["firstCandleUTC"] = utc_string(batch_source_times[0])
        record["lastCandleUTC"] = utc_string(batch_source_times[-1])
    record["valid"] = not issues
    record["issues"] = sorted(set(issues))
    return record, source_records


def build_manifest(root_arg: Path) -> dict[str, Any]:
    try:
        if stat.S_ISLNK(root_arg.lstat().st_mode):
            raise ValidationError("archive_root_symlink_rejected")
        root = root_arg.resolve(strict=True)
    except OSError as exc:
        raise ValidationError(f"archive_root_missing:{type(exc).__name__}") from exc
    if not root.is_dir():
        raise ValidationError("archive_root_not_directory")

    entries, path_issues = file_entries(root)
    paths = sorted([relative for _, relative in entries] + [item["path"] for item in path_issues])
    path_set_sha = digest(canonical_json_bytes(paths))
    file_records: list[dict[str, Any]] = []
    all_source_records: dict[tuple[str, str], list[tuple[dt.datetime, Any]]] = {}
    issues = list(path_issues)

    for path, relative in entries:
        record, records = validate_batch(path, relative)
        file_records.append(record)
        if not record["valid"]:
            issues.extend({"path": relative, "code": issue} for issue in record["issues"])
        for instrument, timestamp, normalized in records:
            granularity = record.get("granularity") or "UNKNOWN"
            all_source_records.setdefault((instrument, granularity), []).append((timestamp, normalized))

    series_records: list[dict[str, Any]] = []
    for (instrument, granularity), values in sorted(all_source_records.items()):
        exact_by_time: dict[str, Any] = {}
        timestamps: list[dt.datetime] = []
        exact_duplicates = conflicting_duplicates = 0
        for timestamp, candle in values:
            key = utc_string(timestamp)
            prior = exact_by_time.get(key)
            if prior is None:
                exact_by_time[key] = candle
                timestamps.append(timestamp)
            elif prior == candle:
                exact_duplicates += 1
            else:
                conflicting_duplicates += 1
        ordered_times = sorted(set(timestamps))
        step = GRANULARITY_SECONDS[granularity]
        gaps = []
        for left, right in zip(ordered_times, ordered_times[1:]):
            delta_us = datetime_to_unix_micros(right) - datetime_to_unix_micros(left)
            step_us = step * 1_000_000
            if delta_us > step_us:
                missing = max(0, (delta_us // step_us) - 1)
                gaps.append({
                    "fromUTC": utc_string(left),
                    "toUTC": utc_string(right),
                    "elapsedMicroseconds": delta_us,
                    "missingExpectedGridCandles": missing,
                })
        if conflicting_duplicates:
            issues.append({
                "path": f"series/{instrument}/{granularity}",
                "code": "conflicting_duplicate_timestamps",
            })
        series_records.append({
            "instrument": instrument,
            "granularity": granularity,
            "rawRows": len(values),
            "uniqueTimestamps": len(ordered_times),
            "exactDuplicateRows": exact_duplicates,
            "conflictingDuplicateRows": conflicting_duplicates,
            "firstCandleUTC": utc_string(ordered_times[0]) if ordered_times else None,
            "lastCandleUTC": utc_string(ordered_times[-1]) if ordered_times else None,
            "gapCount": len(gaps),
            "gaps": gaps,
        })

    issues.sort(key=lambda item: (item["path"], item["code"]))
    files_valid = bool(file_records) and all(record["valid"] for record in file_records)
    eligible = files_valid and not path_issues and not any(
        issue["code"] == "conflicting_duplicate_timestamps" for issue in issues
    )
    manifest: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "toolVersion": TOOL_VERSION,
        "selectedRootLabel": f"{root.parent.name}/{root.name}",
        "provenanceNote": "Path/file labels are claims only; the batch schema does not authenticate broker, account, or environment.",
        "selectedRelativePaths": paths,
        "pathSetSHA256": path_set_sha,
        "archiveIntegrityValid": eligible,
        "campaignReadiness": "NOT_ASSESSED_BY_ARCHIVE_VALIDATOR",
        "readinessNote": "Strategy profile, session-calendar gap classification, costs, and campaign rules are not assessed here.",
        "fileCount": len(paths),
        "validBatchCount": sum(record["valid"] for record in file_records),
        "invalidBatchCount": sum(not record["valid"] for record in file_records),
        "files": sorted(file_records, key=lambda record: record["relativePath"]),
        "series": series_records,
        "issues": issues,
    }
    manifest["manifestSHA256"] = digest(canonical_json_bytes(manifest))
    return manifest


def render_human(manifest: dict[str, Any]) -> str:
    lines = [
        f"Archive label: {manifest['selectedRootLabel']}",
        f"Archive integrity: {'valid' if manifest['archiveIntegrityValid'] else 'invalid'}",
        "Campaign readiness: not assessed (strategy profile and gap/session rules are outside this validator)",
        f"Batches: {manifest['validBatchCount']} valid / {manifest['invalidBatchCount']} invalid / {manifest['fileCount']} selected",
        f"Path set SHA-256: {manifest['pathSetSHA256']}",
        f"Manifest SHA-256: {manifest['manifestSHA256']}",
    ]
    for series in manifest["series"]:
        lines.append(
            f"{series['instrument']} {series['granularity']}: "
            f"{series['uniqueTimestamps']} unique, "
            f"{series['exactDuplicateRows']} exact duplicate rows, "
            f"{series['conflictingDuplicateRows']} conflicts, "
            f"{series['gapCount']} unclassified gaps; "
            f"{series['firstCandleUTC']} .. {series['lastCandleUTC']}"
        )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.home() / "Library/Application Support/BlazerOS/Research/oanda-proxy/historical-bid-ask",
        help="one archive directory to validate (default: selected oanda-proxy history)",
    )
    parser.add_argument("--output", type=Path, help="write JSON to a new file; existing paths are refused")
    parser.add_argument("--human", action="store_true", help="print a short human-readable summary")
    args = parser.parse_args(argv)
    if args.output and args.human:
        parser.error("--human cannot be combined with --output")
    try:
        manifest = build_manifest(args.root)
        payload = render_human(manifest) if args.human else json.dumps(
            manifest, sort_keys=True, indent=2, ensure_ascii=True, allow_nan=False
        ) + "\n"
        if args.output:
            destination = args.output
            if destination.exists() or destination.is_symlink():
                raise ValidationError("output_exists_refusing_overwrite")
            destination.parent.mkdir(parents=True, exist_ok=True)
            descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
                stream.write(payload)
        else:
            print(payload, end="")
        return 0 if manifest["archiveIntegrityValid"] else 1
    except (ValidationError, OSError) as exc:
        print(f"archive validation failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
