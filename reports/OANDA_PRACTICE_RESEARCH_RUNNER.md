# OANDA Practice research runner

`scripts/oanda-practice-research.py` is the only repository launcher that reads
the owner-managed `~/Library/Application Support/BlazerOS/credentials/practice.json`.
The file must be a regular, current-user-owned `0600` file containing
`OANDA_API_TOKEN`, `OANDA_ACCOUNT_ID`, and `OANDA_ENV: practice`. Never put it in
the repository or print its contents.

The runner performs a read-only authenticated `/v3/accounts` check and verifies
that the configured account is in the token's accessible Practice accounts. It
then requests a bounded M1 bid/ask sample and requires at least one completed
candle for the selected supported instrument. The
`collect` command builds `ForwardTest` in a fresh temporary build directory with
an allowlisted, credential-free environment before it loads credentials. It
invokes only that freshly built binary, with the three OANDA variables in that
collector child process only. Collection is limited to 1–24 hours and supports
allowlisted M1, M5, M15, and H1 archive batches (default M1/M5). The default
archive path is under the user's
`Library/Application Support/BlazerOS/Research` directory.

Examples:

```sh
scripts/oanda-practice-research.py preflight --asset EUR/USD
scripts/oanda-practice-research.py collect --asset EUR/USD --hours 1 --offset-hours 1
scripts/oanda-practice-research.py collect --asset EUR/USD --granularity M1 --granularity M5 --granularity M15 --granularity H1
scripts/oanda-practice-research.py preflight --asset EUR/USD
scripts/oanda-practice-research.py verify --asset EUR/USD
```

Run the preflight again as a new process after a fresh authorized launch. The
runner reports sanitized status codes for missing/unsafe credentials, wrong
environment, invalid token, inaccessible account, network failure, and
unsupported data request. It never reports the token or account ID. `verify`
checks archived request bounds, instrument, granularity, complete source-
timestamped bid/ask OHLC, and recomputed SHA-256 without loading credentials.
Pass repeated `--granularity` flags to verify each requested interval.

The archives are market-data observations, not executable prices or fills. This
runner adds no broker-order capability and does not access Keychain.
