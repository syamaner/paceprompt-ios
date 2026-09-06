# Open-weight candidate matrix v4

Research date: 2026-09-05

This matrix records the nine routes ratified for issue #17. It is research and
host-evaluation configuration, not authority to use a provider or to implement
production inference.

## Evidence boundary

The exact evaluation identity is the OpenRouter canonical model revision plus
the provider endpoint and quantisation tag in `models-v4-open-weight.json`.
That does **not** prove which commit of a publisher's weight repository the
provider deployed. No reviewed provider source attests that mapping, so it is
recorded as unverified for every candidate. The publisher repositories establish
that weights are available and identify their governing licences; they do not
establish the bytes behind an OpenRouter route.

In this document, **open-source** is used only for weights under an OSI-style
software licence such as Apache-2.0 or MIT. **Open-weight** includes models whose
weights can be obtained but are governed by a model-specific community licence.
This is an engineering review, not legal advice.

## Common evaluation contract

- All routes use the unchanged v3 prompt, corpus, nested v2.3 provider
  transport, host semantic schema, deterministic scorer, gates and thresholds.
- OpenRouter routing is pinned to one provider and, where known, one
  quantisation: `order` and `only` contain only that endpoint,
  `allow_fallbacks=false`, `require_parameters=true`,
  `data_collection=deny`, and `zdr=true`. OpenRouter documents that `zdr=true`
  restricts routing to zero-data-retention endpoints, while in-memory prompt
  caching may still qualify as ZDR. The evaluator separately disables its own
  cache and prompt cache. See [provider routing](https://openrouter.ai/docs/guides/routing/provider-selection)
  and [ZDR](https://openrouter.ai/docs/guides/features/zdr).
- Eight routes carry the complete schema in native
  `response_format.json_schema`. Nemotron Ultra on BaseTen instead carries the
  same schema in one forced function definition and accepts only the arguments
  of exactly one `submit_workout_import_result` call. Both paths then pass the
  same unchanged host semantic schema and scorer.
- Every request sets `max_tokens=8192`. It omits temperature, top-p, seed, stop
  sequences and reasoning controls because no common explicit setting survived
  the route probes. Omission is intentional and is part of each measured route
  profile; it is not a claim that internal reasoning is disabled.
- Prices below are indicative list prices per million tokens observed on
  OpenRouter on the research date. Reasoning has no separately advertised rate
  for these pinned routes; any billed reasoning is provider-reported output.
  The zero-inference operator gate refreshes the exact endpoint catalogue,
  seals token prices, and computes a conservative full-run upper bound. It is
  authoritative for admission, not this table.
- OpenRouter dashboard latency and throughput are transient and sometimes
  aggregate several endpoints. The compatibility probes establish only that
  the exact request contract worked at least once. The evaluation reports host
  p95 over all 237 scheduled scored attempts per model; it does not substitute
  dashboard telemetry for measured evidence.

## Ratified routes and model evidence

| Evaluation identity and route | Publisher artefact and licence | Authoritative size and limits | Structured contract and parameters | Indicative pinned-route price (input/output) | Credibility and limitations before evaluation |
|---|---|---|---|---|---|
| `qwen/qwen3.8-27b-20260814`; Parasail FP8 | [Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B), Apache-2.0; open-source weights | Dense 27B. Publisher states 262,144 native context, extensible to 1M; evaluation output capped at 8,192. | Native JSON Schema. Requires `max_tokens`, `response_format`, `structured_outputs`. No sampling or reasoning fields sent. | $0.28 / $2.20 ([route listing](https://openrouter.ai/qwen/qwen3.8-27b)) | Credible modern dense candidate with publisher-described structured and agentic capability. Output cost is relatively high and the route's real 237-call latency/validity are unmeasured. |
| `mistralai/mistral-small-2603`; Venice FP8 | [Mistral-Small-4-119B-2603](https://huggingface.co/mistralai/Mistral-Small-4-119B-2603), Apache-2.0; open-source weights | 119B total, 6.5B active, 256K context. Evaluation output capped at 8,192. | Native JSON Schema. Same three required parameters. Reasoning field omitted even though the model offers configurable reasoning. | $0.1875 / $0.75 on Venice ([route listing](https://openrouter.ai/mistralai/mistral-small-2603/pricing)) | Credible because the publisher explicitly describes native function calling and JSON output. Venice is slower than some alternative routes in transient dashboard data; only the host run can decide. |
| `nvidia/nemotron-3.5-lightning-20260807`; DeepInfra BF16 | [NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4) and publisher BF16 variant; OpenMDW-1.1; open-weight, not classified here as OSI open-source | 30B total, 3B active, up to 1M publisher context. Evaluation output capped at 8,192. | Native JSON Schema. Same three required parameters; sampling and reasoning fields omitted. | $0.08 / $0.20 model-route headline ([route listing](https://openrouter.ai/nvidia/nemotron-3.5-lightning)); exact DeepInfra price is resealed at the gate. | Strong cost/active-size candidate and the publisher says commercial use is supported subject to OpenMDW-1.1. The evaluated BF16 host route is not the linked NVFP4 artefact, and its exact deployed commit remains unverified. |
| `deepseek/deepseek-v4-flash-20260731`; OpenInference FP8 | [DeepSeek-V4-Flash](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash), MIT; open-source weights | 284B total, 13B active, 1M publisher context. Evaluation output capped at 8,192. | Native JSON Schema. Same three required parameters; sampling and reasoning fields omitted. | $0.05 / $0.16 on OpenInference ([route listing](https://openrouter.ai/deepseek/deepseek-v4-flash-0731)) | Very low indicative cost and credible scale. The publisher recommends sampling parameters that this cross-route evaluation intentionally omits, so the measured profile may not be its publisher-optimal profile. |
| `z-ai/glm-5.3-flash-20260826`; DeepInfra FP4 | [GLM-5.3-Flash](https://huggingface.co/zai-org/GLM-5.3-Flash), MIT; open-source weights | Parameter and active-parameter counts were not stated in the reviewed authoritative model card. OpenRouter advertises about 1M context; evaluation output capped at 8,192. | Native JSON Schema. Same three required parameters; sampling and reasoning fields omitted. | $0.075 / $0.25 on DeepInfra ([provider listing](https://openrouter.ai/provider/deepinfra)) | Credible low-cost route after its replacement probe passed. Missing authoritative size metadata is retained as unknown rather than inferred. |
| `minimax/minimax-m3-20260531`; CoreWeave FP4 | [MiniMax-M3](https://huggingface.co/MiniMaxAI/MiniMax-M3), MiniMax Community License; open-weight, not open-source | About 428B total and 23B active, 1M publisher context. Evaluation output capped at 8,192. | Native JSON Schema. Same three required parameters. The route probe supports this contract without a tool; sampling and `thinking` fields are omitted. | $0.23 / $0.96 on CoreWeave ([route listing](https://openrouter.ai/minimax/minimax-m3/pricing)) | Technically credible and fast in transient route telemetry. Commercial use requires attribution and a notice at or below the licence's revenue threshold, and prior written authorisation above it; prohibited-use terms also apply. Legal acceptability therefore needs human review before production selection. |
| `nvidia/nemotron-3-ultra-550b-a55b-20260604`; BaseTen FP4 | [NVIDIA-Nemotron-3-Ultra-550B-A55B-NVFP4](https://huggingface.co/nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B-NVFP4), OpenMDW-1.1; open-weight, not classified here as OSI open-source | 550B total, 55B active, up to 1M publisher context; OpenRouter currently exposes a lower route context/output ceiling. Evaluation output capped at 8,192. | Forced tool arguments, not native JSON Schema: requires `max_tokens`, `tools`, `tool_choice`, the exact tool name, exactly one call, and the complete unchanged schema. | $0.60 / $2.40 on BaseTen ([route listing](https://openrouter.ai/nvidia/nemotron-3-ultra-550b-a55b/pricing)) | Highest-capacity candidate, and the one-call BaseTen forced-tool probe passed. It has the highest cost and most complex contract. DeepInfra repeatedly returned `engine_overloaded`, so fallback is deliberately disabled rather than hiding route instability. |
| `qwen/qwen-2.5-7b-instruct`; Phala, quantisation unreported | [Qwen2.5-7B-Instruct](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct), Apache-2.0; open-source weights | 7.61B total, 6.53B non-embedding. Publisher describes 128K context and 8,192 generation, while the current Phala endpoint exposes 32,768 context. | Native JSON Schema. Same three required parameters; sampling and reasoning fields omitted. | $0.10 / $0.20 in the current endpoint API ([endpoint record](https://openrouter.ai/api/v1/models/qwen/qwen-2.5-7b-instruct/endpoints)); resealed at the gate because the web page has shown different prices. | Useful small/cost baseline with explicit publisher claims for JSON output. Quantisation is unknown and retained as such. The smaller 32K hosted context is ample for this corpus but limits broader inference from the result. |
| `mistralai/mistral-small-3.2-24b-instruct-2506`; DeepInfra FP8 | [Mistral-Small-3.2-24B-Instruct-2506](https://huggingface.co/mistralai/Mistral-Small-3.2-24B-Instruct-2506), Apache-2.0; open-source weights | 24B, 131,072 context. Evaluation output capped at 8,192. | Native JSON Schema. Same three required parameters; sampling and reasoning fields omitted. | $0.075 / $0.20 on DeepInfra ([route listing](https://openrouter.ai/mistralai/mistral-small-3.2-24b-instruct/pricing)) | Mature, inexpensive baseline whose publisher specifically reports improved function calling. It is older than the other candidates and remains credible only if the unchanged corpus demonstrates comparable quality. |

## Licence details requiring explicit attention

- Apache-2.0 and MIT candidates are labelled open-source above, but use still
  requires compliance with their notice and other licence terms.
- NVIDIA's two candidates are governed by the
  [OpenMDW-1.1 text](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4/blob/refs%2Fpr%2F2/LICENSE).
  The publisher describes commercial use as supported, but the model-specific
  agreement remains the governing authority.
- MiniMax M3's
  [licence](https://huggingface.co/MiniMaxAI/MiniMax-M3/blob/main/LICENSE)
  requires a visible “Built with MiniMax M3” attribution for commercial use,
  a one-time notice for products or services at or below USD 20 million annual
  revenue, prior written authorisation above that threshold, and compliance
  with its prohibited-use appendix. It must not be described as unconditionally
  open-source.

## Decision boundary

All nine candidates are credible enough to measure because their exact routes
passed the ratified compatibility probes. None is selected by this matrix. The
fixed Sol evidence from issue #15 remains the human-selected reference. A v4
report may compare eligible candidates with that published reference, but it
sets no automatic winner and cannot change the production provider without a
new explicit human decision.
