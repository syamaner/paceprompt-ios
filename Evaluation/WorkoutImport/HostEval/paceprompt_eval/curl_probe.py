"""Direct-curl compatibility probes with bounded spend and redacted evidence."""

from __future__ import annotations

import asyncio
from decimal import Decimal
import json
from pathlib import Path
import time
from typing import Any

from .openrouter import OPENROUTER_URL, redact
from .runner import utc_now, write_json


MARKER = b"\n__PACEPROMPT_CURL_META__"


def _response_body(raw: bytes, api_key: str) -> Any:
    try:
        decoded: Any = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        decoded = {"unparsedUtf8": raw.decode("utf-8", errors="replace")}
    return redact(decoded, (api_key,))


async def invoke_curl(
    *, payload_path: Path, api_key: str, connect_timeout: int, attempt_timeout: int
) -> tuple[int, float | None, Any, str, int]:
    if any(character in api_key for character in "\r\n\0"):
        raise RuntimeError("OPENROUTER_API_KEY contains an unsupported control character")
    command = (
        "curl",
        "--config",
        "-",
        "--silent",
        "--show-error",
        "--request",
        "POST",
        OPENROUTER_URL,
        "--header",
        "Content-Type: application/json",
        "--data-binary",
        f"@{payload_path}",
        "--retry",
        "0",
        "--connect-timeout",
        str(connect_timeout),
        "--max-time",
        str(attempt_timeout),
        "--write-out",
        "\n__PACEPROMPT_CURL_META__%{http_code}\t%{time_total}",
    )
    process = await asyncio.create_subprocess_exec(
        *command,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    config = f'header = "Authorization: Bearer {api_key}"\n'.encode("utf-8")
    try:
        stdout, stderr = await process.communicate(config)
    except asyncio.CancelledError:
        process.terminate()
        try:
            await asyncio.wait_for(process.wait(), timeout=15)
        except asyncio.TimeoutError:
            process.kill()
            await process.wait()
        raise
    if MARKER not in stdout:
        body_raw = stdout
        status_code = 0
        elapsed = None
    else:
        body_raw, metadata = stdout.rsplit(MARKER, 1)
        status_text, elapsed_text = metadata.decode("ascii").strip().split("\t", 1)
        status_code = int(status_text)
        elapsed = float(elapsed_text)
    stderr_text = redact(stderr.decode("utf-8", errors="replace"), (api_key,))
    return status_code, elapsed, _response_body(body_raw, api_key), stderr_text, process.returncode


class CurlProbeRun:
    def __init__(
        self,
        *,
        run_dir: Path,
        gate: dict[str, Any],
        api_key: str,
        execution_policy: dict[str, Any],
        spending_limit_usd: str,
    ) -> None:
        from .task import SpendGuard

        self.run_dir = run_dir
        self.gate = gate
        self.api_key = api_key
        self.execution_policy = execution_policy
        self.guard = SpendGuard(spending_limit_usd)
        self.attempts: list[dict[str, Any]] = []
        self.last_call_finished_at: float | None = None

    def _write_state(self, status: str) -> None:
        write_json(
            self.run_dir / "curl-live-state.json",
            {
                "runID": self.run_dir.name,
                "status": status,
                "updatedAt": utc_now(),
                "attempts": self.attempts,
                "guardChargedUSD": format(self.guard.actual, "f"),
                "guardReservedUSD": format(self.guard.reserved, "f"),
            },
        )

    async def execute(self) -> dict[str, Any]:
        (self.run_dir / "curl-responses").mkdir(exist_ok=False)
        (self.run_dir / "curl-logs").mkdir(exist_ok=False)
        self._write_state("runningCurlProbe")
        delay = float(self.execution_policy["minimumInterCallDelaySeconds"])
        costs = self.gate["costPreflight"]["perAttemptWorstCaseUSD"]
        try:
            for probe in self.gate["probeManifest"]:
                attempt_id = probe["attemptID"]
                inter_call_delay: float | None = None
                if self.last_call_finished_at is not None:
                    remaining = delay - (time.monotonic() - self.last_call_finished_at)
                    if remaining > 0:
                        await asyncio.sleep(remaining)
                    inter_call_delay = time.monotonic() - self.last_call_finished_at
                worst = Decimal(costs[attempt_id])
                self.guard.reserve(attempt_id, worst)
                started = utc_now()
                payload_path = self.run_dir / probe["payloadPath"]
                status_code, elapsed, response, stderr, exit_code = await invoke_curl(
                    payload_path=payload_path,
                    api_key=self.api_key,
                    connect_timeout=self.execution_policy["connectTimeoutSeconds"],
                    attempt_timeout=self.execution_policy["attemptTimeoutSeconds"],
                )
                ended = utc_now()
                self.last_call_finished_at = time.monotonic()
                usage = response.get("usage", {}) if isinstance(response, dict) else {}
                reported_cost = (
                    Decimal(str(usage["cost"])) if usage.get("cost") is not None else None
                )
                self.guard.settle(attempt_id, reported_cost if reported_cost is not None else worst)
                write_json(
                    self.run_dir / "curl-responses" / f"{attempt_id}.json",
                    {
                        "statusCode": status_code,
                        "headersCaptured": False,
                        "body": response,
                    },
                )
                write_json(
                    self.run_dir / "curl-logs" / f"{attempt_id}.json",
                    {
                        "curlExitCode": exit_code,
                        "stderr": stderr,
                        "completeResponseLatencySeconds": elapsed,
                    },
                )
                self.attempts.append(
                    {
                        "attemptID": attempt_id,
                        "modelID": probe["modelID"],
                        "stageID": probe["stageID"],
                        "startedAt": started,
                        "endedAt": ended,
                        "interCallDelaySeconds": inter_call_delay,
                        "curlExitCode": exit_code,
                        "statusCode": status_code,
                        "httpAccepted": exit_code == 0 and 200 <= status_code < 300,
                        "reportedCostUSD": (
                            format(reported_cost, "f") if reported_cost is not None else None
                        ),
                        "guardChargeUSD": format(
                            reported_cost if reported_cost is not None else worst, "f"
                        ),
                        "terminal": True,
                    }
                )
                self._write_state("runningCurlProbe")
        except (asyncio.CancelledError, KeyboardInterrupt):
            self._write_state("cancelledNonResumable")
            raise
        report = {
            "reportContractVersion": "paceprompt-host-eval-curl-probe-report/v2.6",
            "purpose": self.gate["purpose"],
            "heldoutCalls": 0,
            "attempts": self.attempts,
            "providerDecision": "requiresHumanRatification",
        }
        write_json(self.run_dir / "curl-probe-report.json", report)
        self._write_state("completeAwaitingHumanEvidenceRatification")
        return report
