import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "oanda-practice-research.py"
SPEC = importlib.util.spec_from_file_location("oanda_practice_research", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PracticeLauncherTests(unittest.TestCase):
    def credential_file(self, config, mode=0o600):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / "practice.json"
        path.write_text(json.dumps(config), encoding="utf-8")
        path.chmod(mode)
        return path

    def test_credential_read_validates_owner_only_mode_without_echo(self):
        path = self.credential_file({
            "OANDA_API_TOKEN": "secret-test-value",
            "OANDA_ACCOUNT_ID": "practice-account",
            "OANDA_ENV": "practice",
        })
        result = MODULE.read_credentials(path)
        self.assertEqual(result["OANDA_ENV"], "practice")
        self.assertEqual(result["OANDA_ACCOUNT_ID"], "practice-account")

    def test_credential_file_must_be_owner_only(self):
        path = self.credential_file({
            "OANDA_API_TOKEN": "unused", "OANDA_ACCOUNT_ID": "id", "OANDA_ENV": "practice",
        }, mode=0o640)
        with self.assertRaises(MODULE.PreflightError) as error:
            MODULE.read_credentials(path)
        self.assertEqual(error.exception.code, "CREDENTIAL_FILE_UNSAFE")

    def test_missing_file_and_wrong_environment_have_distinct_errors(self):
        with self.assertRaises(MODULE.PreflightError) as missing:
            MODULE.read_credentials(Path(tempfile.gettempdir()) / "no-such-blazeros-practice-file")
        self.assertEqual(missing.exception.code, "CREDENTIAL_FILE_MISSING")
        wrong = self.credential_file({
            "OANDA_API_TOKEN": "unused", "OANDA_ACCOUNT_ID": "id", "OANDA_ENV": "live",
        })
        with self.assertRaises(MODULE.PreflightError) as environment:
            MODULE.read_credentials(wrong)
        self.assertEqual(environment.exception.code, "WRONG_ENVIRONMENT")

    def test_credential_file_must_contain_json_object(self):
        path = self.credential_file(["not", "an", "object"])
        with self.assertRaises(MODULE.PreflightError) as error:
            MODULE.read_credentials(path)
        self.assertEqual(error.exception.code, "CREDENTIAL_FILE_INVALID")

    def test_preflight_checks_account_membership_and_m1_candle_access(self):
        credentials = {"OANDA_API_TOKEN": "never-printed", "OANDA_ACCOUNT_ID": "selected", "OANDA_ENV": "practice"}
        with patch.object(MODULE, "request_json", side_effect=[
            {"accounts": [{"id": "selected"}]}, {"candles": [{"complete": True,
                "bid": {"o": "1", "h": "2", "l": "1", "c": "2"},
                "ask": {"o": "3", "h": "4", "l": "3", "c": "4"}}]},
        ]) as request:
            with patch("builtins.print"):
                MODULE.preflight(credentials, "EUR/USD")
        self.assertEqual(request.call_count, 2)
        self.assertEqual(request.call_args_list[0].args[0], "/v3/accounts")
        self.assertEqual(request.call_args_list[1].args[0], "/v3/instruments/EUR_USD/candles")
        self.assertEqual(request.call_args_list[1].args[2]["count"], 10)

    def test_preflight_rejects_without_a_completed_candle(self):
        credentials = {"OANDA_API_TOKEN": "unused", "OANDA_ACCOUNT_ID": "selected", "OANDA_ENV": "practice"}
        with patch.object(MODULE, "request_json", side_effect=[
            {"accounts": [{"id": "selected"}]}, {"candles": [{"complete": False}]},
        ]):
            with self.assertRaises(MODULE.PreflightError) as error:
                MODULE.preflight(credentials, "EUR/USD")
        self.assertEqual(error.exception.code, "UNSUPPORTED_DATA_REQUEST")

    def test_preflight_rejects_inaccessible_account_and_unknown_instrument(self):
        credentials = {"OANDA_API_TOKEN": "unused", "OANDA_ACCOUNT_ID": "not-listed", "OANDA_ENV": "practice"}
        with patch.object(MODULE, "request_json", return_value={"accounts": [{"id": "other"}]}):
            with self.assertRaises(MODULE.PreflightError) as account:
                MODULE.preflight(credentials, "EUR/USD")
        self.assertEqual(account.exception.code, "INACCESSIBLE_ACCOUNT")
        with self.assertRaises(MODULE.PreflightError) as instrument:
            MODULE.preflight(credentials, "NOT/A_PAIR")
        self.assertEqual(instrument.exception.code, "UNSUPPORTED_DATA_REQUEST")

    def test_research_child_environment_is_allowlisted(self):
        credentials = {"OANDA_API_TOKEN": "approved", "OANDA_ACCOUNT_ID": "selected", "OANDA_ENV": "practice"}
        with patch.dict(os.environ, {"CLEARSTREET_API_KEY": "must-not-pass", "UNRELATED_SECRET": "must-not-pass",
                                    "OANDA_API_TOKEN": "ambient-value"}, clear=True):
            env = MODULE.research_child_environment(credentials)
        self.assertEqual(env["OANDA_API_TOKEN"], "approved")
        self.assertEqual(env["OANDA_ACCOUNT_ID"], "selected")
        self.assertEqual(env["OANDA_ENV"], "practice")
        self.assertNotIn("CLEARSTREET_API_KEY", env)
        self.assertNotIn("UNRELATED_SECRET", env)
        self.assertNotIn("ambient-value", env.values())

    def test_build_environment_is_allowlisted(self):
        with patch.dict(os.environ, {"PATH": "/bin", "HOME": "/home/test", "CLEARSTREET_API_KEY": "secret",
                                     "OANDA_API_TOKEN": "token", "UNRELATED_SECRET": "secret"}, clear=True):
            env = MODULE.clean_build_environment()
        self.assertEqual(env, {"PATH": "/bin", "HOME": "/home/test"})

    def test_api_auth_and_http_errors_are_classified_without_response_body(self):
        credentials = {"OANDA_API_TOKEN": "never-printed"}
        for status, expected in ((401, "INVALID_TOKEN"), (403, "INACCESSIBLE_ACCOUNT"),
                                 (400, "UNSUPPORTED_DATA_REQUEST")):
            error = MODULE.urllib.error.HTTPError("https://example.invalid", status, "", {}, None)
            with patch.object(MODULE.urllib.request, "urlopen", side_effect=error):
                with self.assertRaises(MODULE.PreflightError) as result:
                    MODULE.request_json("/v3/accounts", credentials)
            self.assertEqual(result.exception.code, expected)
            error.close()

    def test_verifies_synthesized_codable_transport_and_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "batch.json"
            path.write_text(json.dumps({
                "transport": {"ok": {}}, "instrument": "EUR_USD", "granularity": "M1",
                "requestedFrom": 100, "requestedTo": 200,
                 "candles": [{"complete": True, "sourceTime": 100,
                              "instrument": "EUR_USD", "granularity": "M1",
                              "bidOpen": 1.0, "bidHigh": 1.1, "bidLow": 0.9, "bidClose": 1.05,
                              "askOpen": 1.01, "askHigh": 1.11, "askLow": 0.91, "askClose": 1.06}],
            }), encoding="utf-8")
            name, digest, count, granularity = MODULE.verify_archive(path, "EUR/USD")
        self.assertEqual(name, "batch.json")
        self.assertEqual(len(digest), 64)
        self.assertEqual(count, 1)
        self.assertEqual(granularity, "M1")

    def test_archive_verification_rejects_false_transport_and_incomplete_quotes(self):
        candle = {"complete": True, "sourceTime": 100, "instrument": "EUR_USD", "granularity": "M1",
                  "bidOpen": 1.0, "bidHigh": 1.1, "bidLow": 0.9, "bidClose": 1.05,
                  "askOpen": 1.01, "askHigh": 1.11, "askLow": 0.91, "askClose": 1.06}
        for transport, complete in (({"ok": False}, True), ({"ok": {}}, False)):
            with tempfile.TemporaryDirectory() as temp:
                path = Path(temp) / "batch.json"
                row = dict(candle, complete=complete)
                path.write_text(json.dumps({"transport": transport, "instrument": "EUR_USD", "granularity": "M1",
                                            "requestedFrom": 100, "requestedTo": 200, "candles": [row]}),
                                encoding="utf-8")
                with self.assertRaises(MODULE.PreflightError) as error:
                    MODULE.verify_archive(path, "EUR/USD")
                self.assertEqual(error.exception.code, "PROVENANCE_VERIFICATION_FAILED")

    def test_verifies_all_allowlisted_granularities(self):
        for granularity in MODULE.ALLOWED_GRANULARITIES:
            with tempfile.TemporaryDirectory() as temp:
                path = Path(temp) / "batch.json"
                path.write_text(json.dumps({
                    "transport": "ok", "instrument": "GBP_JPY", "granularity": granularity,
                    "requestedFrom": 100, "requestedTo": 200,
                    "candles": [{"complete": True, "sourceTime": 100,
                                 "instrument": "GBP_JPY", "granularity": granularity,
                                 "bidOpen": 1, "bidHigh": 2, "bidLow": 1, "bidClose": 2,
                                 "askOpen": 3, "askHigh": 4, "askLow": 3, "askClose": 4}],
                }), encoding="utf-8")
                self.assertEqual(MODULE.verify_archive(path, "GBP/JPY")[3], granularity)

    def test_verifies_foundation_date_values_and_rejects_out_of_range_candle(self):
        # 815,692,800 is 2026-11-12 in Foundation-Date seconds; request bounds
        # use the same Codable representation as the Swift archive.
        candle = {"complete": True, "sourceTime": 815692800,
                  "instrument": "EUR_USD", "granularity": "H1",
                  "bidOpen": 1, "bidHigh": 2, "bidLow": 1, "bidClose": 2,
                  "askOpen": 3, "askHigh": 4, "askLow": 3, "askClose": 4}
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "batch.json"
            path.write_text(json.dumps({"transport": "ok", "instrument": "EUR_USD",
                "granularity": "H1", "requestedFrom": 815692740, "requestedTo": 815692860,
                "candles": [candle]}), encoding="utf-8")
            self.assertEqual(MODULE.verify_archive(path, "EUR/USD")[2], 1)
            candle["sourceTime"] = 815693000
            path.write_text(json.dumps({"transport": "ok", "instrument": "EUR_USD",
                "granularity": "H1", "requestedFrom": 815692740, "requestedTo": 815692860,
                "candles": [candle]}), encoding="utf-8")
            with self.assertRaises(MODULE.PreflightError):
                MODULE.verify_archive(path, "EUR/USD")

    def test_collection_rejects_non_allowlisted_granularity_before_build(self):
        with self.assertRaises(MODULE.PreflightError) as error:
            MODULE.collect(MODULE.SCRIPT_REPO, Path("/bin/true"), {}, "EUR/USD", 1, 0,
                           Path(tempfile.gettempdir()), ("M30",))
        self.assertEqual(error.exception.code, "UNSUPPORTED_DATA_REQUEST")

    def test_runner_rejects_arbitrary_repo_option(self):
        with self.assertRaises(SystemExit):
            MODULE.main(["collect", "--repo", "/tmp/untrusted", "--asset", "EUR/USD"])

    def test_connection_failure_is_distinct(self):
        with patch.object(MODULE.urllib.request, "urlopen", side_effect=OSError("offline")):
            with self.assertRaises(MODULE.PreflightError) as result:
                MODULE.request_json("/v3/accounts", {"OANDA_API_TOKEN": "unused"})
        self.assertEqual(result.exception.code, "NETWORK_FAILURE")


if __name__ == "__main__":
    unittest.main()
