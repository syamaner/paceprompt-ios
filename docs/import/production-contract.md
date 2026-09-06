# Production import contract — issue 19

Frozen before adapter implementation on 6 September 2026, based on remote main
`5fea298b07eedd19b816fd5eb70a8e6ae750ac2e` and the complete current issue 19.
Dependencies 6, 10, 11, 15 and 17 were verified closed. This is a mocked implementation
contract, not live-route acceptance. No credential read, inference or spend is authorised.

## Complete outbound request

[outbound-request.json](outbound-request.json) is the complete synthetic body,
including all 24 messages and the entire schema. Only the final user message varies.
POST `https://openrouter.ai/api/v1/chat/completions`, Content-Type and Accept
`application/json`, Authorization `Bearer <credential>` (synthetic in tests).
No attribution, user identifier, tools, plugins, transforms or optional generation
settings are added. The credential component authorises only this exact URL.

Final message uses the evaluated `Locale`, `Capabilities`, `Workout request` format.
Locale is explicitly en-GB. Vocabulary is seconds/minutes, km/h/mph and percent,
already enumerated by prompt/schema. Only speed/inclination capability **states**
(unknown, unsupported, supported) are disclosed and sent; ranges stay local because
the prompt delegates range and increment validation to the device. Nothing else
from Settings, saved plans, Bluetooth or health data is sent. Capability changes
invalidate the disclosure, request and preview, including changes to local ranges.

Ephemeral URLSession: no URL cache, cookies or URL credential storage; 60-second
inactivity timeout and independent 180-second deadline. One POST, no redirects,
authentication challenge retries, application retries, fallback or background session.
Cancellation, backgrounding and protected-data loss cancel transport and invalidate
request identity. Late callbacks cannot restore preview or save authority.

## Closed accepted response envelope

[accepted-response.json](accepted-response.json) is a synthetic complete fixture
showing every permitted optional metadata field. It is not a provider transcript.

Success requires HTTP 200 and application/json, with a single complete UTF-8 JSON
object and no duplicate keys at any depth. Required top-level keys:
`id` (nonempty string), `object` (`chat.completion`), `created` (nonnegative integer),
`model` (`openai/gpt-5.6-sol-20260709` or the requested alias
`openai/gpt-5.6-sol`), `provider` (`openai` or exactly `OpenAI`),
`choices` (exactly one item). Optional top-level keys: `system_fingerprint`
(string/null), `usage` (closed object described below), `service_tier`
(null or `default`). No other fields are accepted, including opt-in router metadata.
The required provider field is issue 19's explicit identity requirement even though
OpenRouter's OpenAPI ChatResult does not currently enumerate it; absence fails closed.
The model and provider are validated as one identity tuple: the requested alias is
accepted only with the pinned provider identity, while an absent, non-string,
unqualified or different model and an absent or different provider fail closed.
This narrow amendment follows a live response classified as `identityModelAlias`
while the provider-side generation record reported the selected canonical revision
and OpenAI route. No received value or provider record is retained in the repository.

Choice requires `index` (integer 0), `finish_reason` (`stop`), `message`.
Optional `native_finish_reason` must be `stop`; optional `logprobs` must be null.
Message requires `role` (`assistant`) and `content` (one structured JSON string).
Optional `refusal` and `reasoning` must be null or empty string; optional
`reasoning_details` and `tool_calls` must be empty arrays. Optional message `model`
must equal the canonical identity. Any nonempty tools, reasoning, refusal metadata,
content parts, images, audio, truncation or unexpected fields fails structurally.
Refusal is accepted only as the contracted structured model outcome.

Optional usage requires nonnegative integer `prompt_tokens`, `completion_tokens`,
`total_tokens`; total must equal prompt + completion. Optional `cost` is nonnegative
number/null, `is_byok` boolean. Optional `prompt_tokens_details` is null or a closed
object containing nonnegative integer `cached_tokens`, `cache_write_tokens`,
`audio_tokens`, `video_tokens`. Optional `completion_tokens_details` is null or a
closed object containing nullable nonnegative integers `reasoning_tokens`,
`audio_tokens`, `accepted_prediction_tokens`, `rejected_prediction_tokens`.
Optional `cost_details` is null or a closed object of nullable nonnegative numbers
`upstream_inference_cost`, `upstream_inference_prompt_cost`,
`upstream_inference_completions_cost`, `server_tool_cost`. Optional
`server_tool_use_details` is null or a closed object of nullable nonnegative integers
`tool_calls_executed`, `tool_calls_requested`, `web_search_requests`. These accounting
fields do not enable tools or alter the request; all usage metadata is validated then
discarded.

Non-200 responses never parse provider error text: 401/402/403/404/429/503 map to
providerUnavailable with stable local reasons; other HTTP errors to providerFailure.
Transport, timeout, cancellation, redirect, response content type, identity and
structural failures have separate local codes. Identity failure codes distinguish the response URL, missing,
non-string, unqualified-revision or other mismatched top-level model,
missing or mismatched provider, service tier and optional message model without retaining
or displaying any received value. No error body or
native error description is shown or stored.

## Proposal and local authority

The copied nested v2.3 schema is checked completely, followed by exact sentinel,
reason/outcome pairing and ordered unique path rules. Proposal transport v2 projects
explicitly into a separate untrusted `workout-proposal/v1` value, with no other
version coercion. Decimal numeric tokens retain their lexical value and use checked
arithmetic. Minutes multiply by exactly 60; mph by exactly 1.609344. Nonintegral or
nonrepresentable seconds fail mapping. Order and values are never repaired.
The existing validator, readable preview and separate confirm-save operation remain
authoritative. Local capability unknown blocks preview and save.

## Resource provenance

Production owns only system.md, transport.json and 22 ordered example messages.
The production app has no Evaluation runtime dependency. The examples are the
model-visible projection of eleven development examples in the v3 manifest order,
using the evaluated nested sentinel projection. No IDs, labels, rationales, held-out
cases, loaders, scorer or evidence are bundled.

| Resource | SHA-256 |
| --- | --- |
| system.md | d58800efc4b0e01994a1a5be1a1d644ce52dbb6bb7c12655745dc78b6e355fd3 |
| transport.json | d4901b2dc3b1a57654ed5d6f7e96bdce30687062913036f86e616fb2f5a9bba0 |
| examples.json | 0313c531454bae3545ec97118be33232f53b0b62613a2339d8a96dbe21a680fd |

Source paths: Evaluation/WorkoutImport/HostEval/prompts/v3/system.md,
schemas/v2.3/workout-import-provider-transport-v2.3.schema.json,
datasets/v3/development/{cases,manifest}.json, and the reviewed projection in
paceprompt_eval/{v3,scorer_adapter}.py. Verification is development-only.

## Public authority inspected without authentication or inference

- [API overview](https://openrouter.ai/docs/api/reference/overview) and
  [OpenAPI](https://openrouter.ai/openapi.json): request controls and response fields.
- [Provider routing](https://openrouter.ai/docs/guides/routing/provider-selection):
  only/order, no fallback, required parameters and data collection denial.
  Service-tier endpoints require explicit opt-in and do not match base slugs.
- [Sol catalogue](https://openrouter.ai/api/v1/models/openai/gpt-5.6-sol/endpoints):
  current `openai` endpoint lists the ratified revision and structured output support.
- [Structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs):
  strict json_schema request format; local validation remains mandatory.
- [Data collection](https://openrouter.ai/docs/guides/privacy/data-collection):
  remote metadata and account-controlled logging. data_collection=deny is not ZDR;
  omit zdr as ratified and never promise zero retention.

The consolidated evaluation used deterministic scoring, not an LLM judge. No
open-weight candidate qualified; on-device inference is deferred under 14.
Live evidence established that OpenRouter can return the requested alias in the API
envelope while its provider-side record attributes the generation to the selected
canonical revision and OpenAI route. Production therefore accepts only that exact
alias/provider tuple as equivalent; it does not accept a different alias or provider.

## DEBUG-only redacted validation tracing

Issue 26 adds an observational diagnostic path compiled only when `DEBUG` is set.
The production parser remains the sole response-acceptance authority: a separate
inspector emits closed stage, result and classification enums, then the unchanged
parser independently accepts or rejects the response. The injectable sink therefore
cannot provide retry, routing, validation, preview or save authority.

The trace distinguishes disclosure and request lifecycle; endpoint, HTTP status class
and content type; outer JSON syntax and field allowlist; model/provider classification;
service tier and usage contract; choice count/allowlist/index; finish reasons and
logprobs; message allowlist, role, content, refusal, reasoning, reasoning details,
tool calls and optional model identity; structured-content JSON/contract; mapping,
local validation, preview eligibility and terminal outcome. Request count and elapsed
time use numeric counts and coarse predefined buckets only.

No diagnostic event can contain prompts, request/response bodies, received identity
strings, URLs, IDs, workout values, provider errors, native error descriptions,
credentials, headers or Keychain bytes. The default DEBUG sink writes only stable
public event codes to Apple unified logging. Those development logs may persist under
Apple's OS logging policy; PacePrompt adds no in-app history, export, remote logging,
analytics or telemetry upload. Release compilation excludes the implementation and
every call site, and Release UI/behaviour remain unchanged.
