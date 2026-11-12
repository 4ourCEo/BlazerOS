#!/usr/bin/env python3
"""Least-privilege OANDA Practice preflight and bounded research collector."""

import argparse
import hashlib
import http.client
import json
import os
import stat
import subprocess
import sys
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
                           {"granularity": "M1", "count": 1, "price": "BA", "smooth": "false"})
    rows = candles.get("candles")
    if not isinstance(rows, list) or not rows:
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Practice M1 candle endpoint returned no usable candle")
    print(f"OANDA_PREFLIGHT state=READY environment=practice account_match=true instrument={instrument} granularity=M1 candle_count={len(rows)}")


def collector_binary(repo):
    return repo / ".build/out/Products/Release/ForwardTest"


def research_child_environment(credentials):
    env = {k: os.environ[k] for k in ("PATH", "HOME", "TMPDIR") if k in os.environ}
    env.update(credentials)
    return env


def build_without_credentials(repo, binary):
    if binary.is_file() and os.access(binary, os.X_OK):
        return
    env = {k: v for k, v in os.environ.items() if not k.startswith("OANDA_")}
    completed = subprocess.run(["swift", "build", "-c", "release", "--target", "ForwardTest"],
                               cwd=repo, env=env, check=False)
    if completed.returncode != 0 or not (binary.is_file() and os.access(binary, os.X_OK)):
        raise PreflightError("COLLECTOR_UNAVAILABLE", "ForwardTest release binary could not be built")


def collect(repo, credentials, asset, hours, offset, archive_root):
    if asset not in INSTRUMENTS:
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Instrument is not supported by the Practice collector")
    if not 1 <= hours <= 24 or not 0 <= offset <= 720:
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Collection bound must be 1–24 hours and offset 0–720 hours")
    binary = collector_binary(repo)
    build_without_credentials(repo, binary)
    archive_root.mkdir(parents=True, exist_ok=True)
    before = set(archive_root.glob("oanda-practice-*.json"))
    child_env = research_child_environment(credentials)
    command = [str(binary), "--historical-bid-ask", "--asset", asset,
               "--historical-hours", str(hours), "--historical-offset-hours", str(offset),
               "--root", str(archive_root.parent)]
    result = subprocess.run(command, cwd=repo, env=child_env, check=False)
    if result.returncode:
        raise PreflightError("COLLECTION_FAILED", f"ForwardTest historical collector exited {result.returncode}")
    created = sorted(set(archive_root.glob("oanda-practice-*.json")) - before)
    if len(created) != 2:
        raise PreflightError("PROVENANCE_VERIFICATION_FAILED", f"Expected two new M1/M5 archive batches; found {len(created)}")
    verified = []
    for path in created:
        verified.append(verify_archive(path, asset))
    for name, digest, count, granularity in verified:
        print(f"OANDA_ARCHIVE status=VERIFIED granularity={granularity} candle_count={count} sha256={digest} file={name}")


def verify_archive(path, asset):
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        transport = payload.get("transport")
        transport_ok = transport == "ok" or (isinstance(transport, dict) and "ok" in transport)
        candles = payload.get("candles")
        if (not transport_ok or not payload.get("candles")
                or payload.get("instrument") != INSTRUMENTS[asset]
                or payload.get("granularity") not in ("M1", "M5")
                or payload.get("requestedFrom") is None or payload.get("requestedTo") is None
                or not all(isinstance(candle, dict) and candle.get("sourceTime") is not None
                           and candle.get("instrument") == INSTRUMENTS[asset]
                           and candle.get("granularity") == payload.get("granularity")
                           for candle in candles)):
            raise ValueError
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        raise PreflightError("PROVENANCE_VERIFICATION_FAILED", "Archive batch failed schema/content verification")
    return (path.name, digest, len(candles), payload["granularity"])


def verify_existing(archive_root, asset):
    if asset not in INSTRUMENTS:
        raise PreflightError("UNSUPPORTED_DATA_REQUEST", "Instrument is not supported by the Practice collector")
    verified = []
    for granularity in ("M1", "M5"):
        files = sorted(archive_root.glob(f"oanda-practice-{INSTRUMENTS[asset]}-{granularity}-*.json"))
        if not files:
            raise PreflightError("PROVENANCE_VERIFICATION_FAILED", f"No persisted {granularity} archive batch found")
        verified.append(verify_archive(files[-1], asset))
    for name, digest, count, granularity in verified:
        print(f"OANDA_ARCHIVE status=VERIFIED granularity={granularity} candle_count={count} sha256={digest} file={name}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("preflight", "collect", "verify"))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--asset", default="EUR/USD")
    parser.add_argument("--hours", type=int, default=1)
    parser.add_argument("--offset-hours", type=int, default=0)
    parser.add_argument("--archive-root", type=Path,
                        default=Path.home() / "Library/Application Support/BlazerOS/Research/oanda-practice-bounded/historical-bid-ask")
    args = parser.parse_args(argv)
    try:
        if args.command == "verify":
            verify_existing(args.archive_root.expanduser().resolve(), args.asset)
            return 0
        credentials = read_credentials()
        preflight(credentials, args.asset)
        if args.command == "collect":
            collect(args.repo.resolve(), credentials, args.asset, args.hours, args.offset_hours,
                    args.archive_root.expanduser().resolve())
    except PreflightError as exc:
        print(f"OANDA_AUTH_ERROR code={exc.code} message={exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"OANDA_AUTH_ERROR code=INTERNAL_FAILURE type={type(exc).__name__}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
