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

    def _diagnostics(self, model_id: str, response: Any) -> dict[str, Any]:
        expected = self.gate.get("diagnosticExpectedOutput")
        if expected is None:
            return {}
        selected = next(
            item
            for item in self.gate["selectedEndpoints"]
            if item["requestedModelID"] == model_id
        )
        body = response if isinstance(response, dict) else {}
        returned_model = body.get("model")
        returned_provider = body.get("provider")
        valid_models = {selected["requestedModelID"], selected["canonicalRevision"]}
        valid_providers = {
            selected["providerEndpoint"],
            selected["reportedProviderName"],
        }
        choices = body.get("choices") if isinstance(body.get("choices"), list) else []
        content = None
        tool_calls: list[Any] = []
        if len(choices) == 1 and isinstance(choices[0], dict):
            message = choices[0].get("message")
            if isinstance(message, dict):
                content = message.get("content")
                if isinstance(message.get("tool_calls"), list):
                    tool_calls = message["tool_calls"]
        parsed = None
        json_valid = False
        tool_arguments = None
        tool_name = None
        diagnostic_transport = self.gate.get(
            "diagnosticTransport", "messageContentJson"
        )
        if diagnostic_transport == "forcedToolArguments":
            if len(tool_calls) == 1 and isinstance(tool_calls[0], dict):
                function = tool_calls[0].get("function")
                if isinstance(function, dict):
                    tool_name = function.get("name")
                    tool_arguments = function.get("arguments")
            if isinstance(tool_arguments, str):
                try:
                    parsed = json.loads(tool_arguments)
                    json_valid = True
                except json.JSONDecodeError:
                    pass
        elif isinstance(content, str):
            try:
                parsed = json.loads(content)
                json_valid = True
            except json.JSONDecodeError:
                pass
        diagnostics = {
            "returnedModel": returned_model,
            "returnedProvider": returned_provider,
            "routeIdentityPresent": returned_model is not None and returned_provider is not None,
            "routeIdentityMatches": returned_model in valid_models and returned_provider in valid_providers,
            "choiceCount": len(choices),
            "contentIsString": isinstance(content, str),
            "contentJSONValid": (
                json_valid if diagnostic_transport == "messageContentJson" else False
            ),
            "strictSchemaSatisfied": parsed == expected,
        }
        if diagnostic_transport == "forcedToolArguments":
            diagnostics.update(
                {
                    "toolCallCount": len(tool_calls),
                    "toolNameMatches": tool_name == self.gate.get("diagnosticToolName"),
                    "toolArgumentsIsString": isinstance(tool_arguments, str),
                    "toolArgumentsJSONValid": json_valid,
                }
            )
        return diagnostics

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
            remaining_probes: list[dict[str, Any]] = []
            for index, probe in enumerate(self.gate["probeManifest"]):
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
                attempt = {
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
                attempt.update(self._diagnostics(probe["modelID"], response))
                self.attempts.append(attempt)
                self._write_state("runningCurlProbe")
                if status_code in set(self.execution_policy.get("abortHTTPStatusCodes", [])):
                    remaining_probes = self.gate["probeManifest"][index + 1 :]
                    break
            for probe in remaining_probes:
                self.attempts.append(
                    {
                        "attemptID": probe["attemptID"],
                        "modelID": probe["modelID"],
                        "stageID": probe["stageID"],
                        "status": "notStarted",
                        "reasonCategory": "globalHTTPAbort",
                        "reportedCostUSD": None,
                        "guardChargeUSD": "0",
                        "terminal": True,
                    }
                )
            if remaining_probes:
                self._write_state("abortedByGlobalHTTPStatus")
        except (asyncio.CancelledError, KeyboardInterrupt):
            self._write_state("cancelledNonResumable")
            raise
        report = {
            "reportContractVersion": self.gate.get(
                "reportContractVersion", "paceprompt-host-eval-curl-probe-report/v2.6"
            ),
            "purpose": self.gate["purpose"],
            "heldoutCalls": self.gate.get("scope", {}).get("heldoutCalls", 0),
            "attempts": self.attempts,
            "providerDecision": "requiresHumanRatification",
        }
        final_status = (
            "abortedByGlobalHTTPStatusAwaitingHumanEvidenceRatification"
            if remaining_probes
            else "completeAwaitingHumanEvidenceRatification"
        )
        if "reportContractVersion" in self.gate:
            report["status"] = final_status
        write_json(self.run_dir / "curl-probe-report.json", report)
        self._write_state(final_status)
        return report
