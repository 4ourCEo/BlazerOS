#!/usr/bin/env python3
"""Least-privilege OANDA Practice preflight and bounded research collector."""

import argparse
import hashlib
import http.client
import json
import math
import os
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


CREDENTIAL_PATH = Path.home() / "Library/Application Support/BlazerOS/credentials/practice.json"
API = "https://api-fxpractice.oanda.com"
INSTRUMENTS = {
    "EUR/USD": "EUR_USD", "GBP/USD": "GBP_USD", "USD/JPY": "USD_JPY",
    "EUR/GBP": "EUR_GBP", "AUD/USD": "AUD_USD", "USD/CAD": "USD_CAD",
    "EUR/JPY": "EUR_JPY", "GBP/JPY": "GBP_JPY", "XAU/USD": "XAU_USD",
}
ALLOWED_GRANULARITIES = ("M1", "M5", "M15", "H1")
DEFAULT_GRANULARITIES = ("M1", "M5")
SCRIPT_REPO = Path(__file__).resolve().parents[1]


class PreflightError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def read_credentials(path=CREDENTIAL_PATH):
    try:
        info = path.lstat()
    except FileNotFoundError:
        raise PreflightError("CREDENTIAL_FILE_MISSING", "Practice credential file is missing")
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
        raise PreflightError("CREDENTIAL_FILE_UNSAFE", "Credential file must be a regular owner-owned 0600 file")
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise PreflightError("CREDENTIAL_FILE_INVALID", "Credential file is unreadable or invalid JSON")
    if not isinstance(config, dict):
        raise PreflightError("CREDENTIAL_FILE_INVALID", "Credential file must contain a JSON object")
    token, account, environment = (config.get(k) for k in ("OANDA_API_TOKEN", "OANDA_ACCOUNT_ID", "OANDA_ENV"))
    if not isinstance(token, str) or not token.strip() or not isinstance(account, str) or not account.strip():
        raise PreflightError("CREDENTIALS_MISSING", "Practice token or account ID is missing")
    if environment != "practice":
        raise PreflightError("WRONG_ENVIRONMENT", "Credential environment must be exactly practice")
    return {"OANDA_API_TOKEN": token.strip(), "OANDA_ACCOUNT_ID": account.strip(), "OANDA_ENV": "practice"}


def request_json(path, credentials, query=None):
    url = API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, headers={
        "Authorization": "Bearer " + credentials["OANDA_API_TOKEN"],
        "Accept": "application/json",
        "User-Agent": "BlazerOS-Research-Preflight/1",
    })
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            if response.status != 200:
                raise PreflightError("NETWORK_FAILURE", "OANDA returned an unexpected HTTP status")
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            raise PreflightError("INVALID_TOKEN", "OANDA Practice rejected the token (HTTP 401)")
        if exc.code == 403:
            raise PreflightError("INACCESSIBLE_ACCOUNT", "OANDA denied access (HTTP 403)")
        if exc.code in (400, 404, 405):
            raise PreflightError("UNSUPPORTED_DATA_REQUEST", f"OANDA rejected the requested resource (HTTP {exc.code})")
        raise PreflightError("NETWORK_FAILURE", f"OANDA request failed (HTTP {exc.code})")
    except urllib.error.URLError as exc:
        reason = exc.reason
        if isinstance(reason, TimeoutError) or "timed out" in str(reason).lower():
            detail = "timeout"
        else:
            detail = "connection error"
        raise PreflightError("NETWORK_FAILURE", f"OANDA {detail}")
    except (TimeoutError, json.JSONDecodeError, UnicodeError):
        raise PreflightError("NETWORK_FAILURE", "OANDA response timed out or was invalid")
    except (OSError, http.client.HTTPException):
        raise PreflightError("NETWORK_FAILURE", "OANDA connection failed")


def preflight(credentials, asset):
    instrument = INSTRUMENTS.get(asset)
    if instrument is None:
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Instrument is not supported by the Practice collector")
    account_payload = request_json("/v3/accounts", credentials)
    accounts = account_payload.get("accounts")
    if not isinstance(accounts, list):
        raise PreflightError("NETWORK_FAILURE", "OANDA account-list response was malformed")
    account_ids = {row.get("id") for row in accounts if isinstance(row, dict)}
    if credentials["OANDA_ACCOUNT_ID"] not in account_ids:
        raise PreflightError("INACCESSIBLE_ACCOUNT", "Configured account ID is not accessible to this Practice token")
    candles = request_json(f"/v3/instruments/{instrument}/candles", credentials,
                           {"granularity": "M1", "count": 10, "price": "BA", "smooth": "false"})
    rows = candles.get("candles")
    usable = lambda row: isinstance(row, dict) and row.get("complete") is True \
        and isinstance(row.get("bid"), dict) and isinstance(row.get("ask"), dict) \
        and all(row[side].get(field) is not None for side in ("bid", "ask") for field in ("o", "h", "l", "c"))
    if not isinstance(rows, list) or not rows or not any(usable(row) for row in rows):
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Practice M1 candle endpoint returned no usable candle")
    print(f"OANDA_PREFLIGHT state=READY environment=practice account_match=true instrument={instrument} granularity=M1 candle_count={len(rows)}")


def timestamp_seconds(value):
    """Decode Foundation Date JSON and common ISO/Unix representations."""
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        seconds = float(value)
        if not math.isfinite(seconds):
            raise ValueError
        # JSONEncoder's default Date strategy uses seconds since 2001-01-01.
        return seconds + 978307200 if seconds < 1_500_000_000 else seconds
    if isinstance(value, str):
        from datetime import datetime
        text = value.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(text)
        if parsed.tzinfo is None:
            from datetime import timezone
            parsed = parsed.replace(tzinfo=timezone.utc)
        seconds = parsed.timestamp()
        if not math.isfinite(seconds):
            raise ValueError
        return seconds
    raise ValueError


def research_child_environment(credentials):
    env = {k: os.environ[k] for k in ("PATH", "HOME", "TMPDIR") if k in os.environ}
    env.update(credentials)
    return env


def clean_build_environment():
    allowed = ("PATH", "HOME", "TMPDIR", "DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS")
    return {key: os.environ[key] for key in allowed if key in os.environ}


def build_isolated(repo, build_root):
    env = clean_build_environment()
    built = subprocess.run(["swift", "build", "-c", "release", "--target", "ForwardTest",
                            "--build-path", str(build_root)], cwd=repo, env=env,
                           check=False, stdout=subprocess.DEVNULL)
    if built.returncode:
        raise PreflightError("COLLECTOR_UNAVAILABLE", "Isolated ForwardTest release build failed")
    location = subprocess.run(["swift", "build", "-c", "release", "--show-bin-path",
                               "--build-path", str(build_root)], cwd=repo, env=env,
                              check=False, capture_output=True, text=True)
    if location.returncode:
        raise PreflightError("COLLECTOR_UNAVAILABLE", "Could not locate isolated ForwardTest binary")
    binary = Path(location.stdout.strip()) / "ForwardTest"
    if binary.is_symlink() or not binary.is_file() or not os.access(binary, os.X_OK):
        raise PreflightError("COLLECTOR_UNAVAILABLE", "Isolated ForwardTest binary is missing or unsafe")
    return binary


def collect(repo, binary, credentials, asset, hours, offset, archive_root,
            granularities=DEFAULT_GRANULARITIES):
    if asset not in INSTRUMENTS:
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Instrument is not supported by the Practice collector")
    if not 1 <= hours <= 24 or not 0 <= offset <= 720:
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Collection bound must be 1–24 hours and offset 0–720 hours")
    if not granularities or any(granularity not in ALLOWED_GRANULARITIES for granularity in granularities):
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Granularity must be one of M1, M5, M15, H1")
    archive_root.mkdir(parents=True, exist_ok=True)
    instrument = INSTRUMENTS[asset]
    archive_pattern = f"oanda-practice-{instrument}-*.json"
    before = set(archive_root.glob(archive_pattern))
    child_env = research_child_environment(credentials)
    for granularity in granularities:
        command = [str(binary), "--historical-bid-ask", "--asset", asset,
                   "--historical-granularity", granularity,
                   "--historical-hours", str(hours), "--historical-offset-hours", str(offset),
                   "--root", str(archive_root.parent)]
        result = subprocess.run(command, cwd=repo, env=child_env, check=False)
        if result.returncode:
            raise PreflightError("COLLECTION_FAILED", "ForwardTest historical collector failed")
    # Collections for different instruments may run concurrently in one archive.
    created = sorted(set(archive_root.glob(archive_pattern)) - before)
    expected = set(granularities)
    if len(created) != len(expected):
        raise PreflightError("PROVENANCE_VERIFICATION_FAILED", "Unexpected number of new archive batches")
    verified = []
    for path in created:
        verified.append(verify_archive(path, asset))
    if {granularity for _, _, _, granularity in verified} != expected:
        raise PreflightError("PROVENANCE_VERIFICATION_FAILED", "Archive batches did not match requested granularities")
    for name, digest, count, granularity in verified:
        print(f"OANDA_ARCHIVE status=VERIFIED granularity={granularity} candle_count={count} sha256={digest} file={name}")


def verify_archive(path, asset):
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        transport = payload.get("transport")
        transport_ok = transport == "ok" or transport == {"ok": {}}
        candles = payload.get("candles")
        fields = ("bidOpen", "bidHigh", "bidLow", "bidClose", "askOpen", "askHigh", "askLow", "askClose")
        granularity = payload.get("granularity")
        requested_from = timestamp_seconds(payload["requestedFrom"])
        requested_to = timestamp_seconds(payload["requestedTo"])
        if (not transport_ok or not isinstance(candles, list) or not candles
                or payload.get("instrument") != INSTRUMENTS[asset]
                or granularity not in ALLOWED_GRANULARITIES
                or requested_from >= requested_to
                or not all(isinstance(candle, dict) and candle.get("complete") is True
                           and requested_from <= timestamp_seconds(candle.get("sourceTime")) <= requested_to
                           and candle.get("instrument") == INSTRUMENTS[asset]
                           and candle.get("granularity") == granularity
                           and all(math.isfinite(float(candle[field])) and float(candle[field]) > 0
                                   for field in fields)
                           and all(candle[bid] < candle[ask] for bid, ask in zip(
                               ("bidOpen", "bidHigh", "bidLow", "bidClose"),
                               ("askOpen", "askHigh", "askLow", "askClose")))
                           for candle in candles)):
            raise ValueError
        times = [timestamp_seconds(candle["sourceTime"]) for candle in candles]
        if times != sorted(times) or len(times) != len(set(times)):
            raise ValueError
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
    except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError, ValueError):
        raise PreflightError("PROVENANCE_VERIFICATION_FAILED", "Archive batch failed schema/content verification")
    return (path.name, digest, len(candles), granularity)


def verify_existing(archive_root, asset, granularities=DEFAULT_GRANULARITIES):
    if asset not in INSTRUMENTS:
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Instrument is not supported by the Practice collector")
    verified = []
    for granularity in granularities:
        files = sorted(archive_root.glob(f"oanda-practice-{INSTRUMENTS[asset]}-{granularity}-*.json"))
        if not files:
            raise PreflightError("PROVENANCE_VERIFICATION_FAILED", f"No persisted {granularity} archive batch found")
        verified.append(verify_archive(files[-1], asset))
    for name, digest, count, granularity in verified:
        print(f"OANDA_ARCHIVE status=VERIFIED granularity={granularity} candle_count={count} sha256={digest} file={name}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("preflight", "collect", "verify"))
    parser.add_argument("--asset", default="EUR/USD")
    parser.add_argument("--hours", type=int, default=1)
    parser.add_argument("--offset-hours", type=int, default=0)
    parser.add_argument("--granularity", action="append", choices=ALLOWED_GRANULARITIES,
                        help="Interval to collect or verify; repeat for multiple intervals (default: M1 M5)")
    parser.add_argument("--archive-root", type=Path,
                        default=Path.home() / "Library/Application Support/BlazerOS/Research/oanda-practice-bounded/historical-bid-ask")
    args = parser.parse_args(argv)
    try:
        if args.command == "verify":
            verify_existing(args.archive_root.expanduser().resolve(), args.asset,
                            tuple(args.granularity or DEFAULT_GRANULARITIES))
            return 0
        repo = Path(__file__).resolve().parents[1]
        archive_root = args.archive_root.expanduser().resolve()
        if args.command == "collect":
            if not 1 <= args.hours <= 24 or not 0 <= args.offset_hours <= 720:
                raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Collection bound must be 1–24 hours and offset 0–720 hours")
            with tempfile.TemporaryDirectory(prefix="blazeros-forwardtest-build-") as temp_build:
                binary = build_isolated(repo, Path(temp_build) / "build")
                credentials = read_credentials()
                preflight(credentials, args.asset)
                collect(repo, binary, credentials, args.asset, args.hours, args.offset_hours,
                        archive_root, tuple(args.granularity or DEFAULT_GRANULARITIES))
            return 0
        credentials = read_credentials()
        preflight(credentials, args.asset)
    except PreflightError as exc:
        print(f"OANDA_AUTH_ERROR code={exc.code} message={exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"OANDA_AUTH_ERROR code=INTERNAL_FAILURE type={type(exc).__name__}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
