# Classification overview

Descriptive diagnostics, not new selection criteria. [Definitions and limitations](consolidated-evaluation-2026-09-06.md#classification-metrics-at-a-glance). Label-only accuracy excludes missing predictions and must be read with coverage. Safety counts are recorded predictions, not full safety-gate passes; missing responses can hide unobserved errors.

| Model | Label recorded / scheduled | Category accuracy % | Macro precision % | Macro recall % | Macro F1 % | Label-only accuracy % | Safety → proposal | All non-proposal → proposal |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| google/gemini-3.7-flash | 233/237 | 98.3122 | 100.0000 | 98.0952 | 98.9011 | 100.0000 | 0 | 0 |
| openai/gpt-5.6-luna | 228/237 | 91.5612 | 97.4846 | 91.0317 | 93.5201 | 95.1754 | 1 | 9 |
| openai/gpt-5.6-sol | 237/237 | 99.5781 | 99.5536 | 99.5238 | 99.5233 | 99.5781 | 0 | 0 |
| deepseek/deepseek-v4-flash-0731 | 206/237 | 81.8565 | 95.0791 | 80.3968 | 84.4864 | 94.1748 | 0 | 3 |
| minimax/minimax-m3 | 189/237 | 70.4641 | 90.7207 | 69.4841 | 76.2240 | 88.3598 | 0 | 3 |
| mistralai/mistral-small-2603 | 0/237 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | Undefined | 0 | 0 |
| mistralai/mistral-small-3.2-24b-instruct | 12/237 | 3.3755 | 41.6667 | 3.6508 | 6.6041 | 66.6667 | 0 | 0 |
| nvidia/nemotron-3-ultra-550b-a55b | 11/237 | 4.2194 | 57.1429 | 4.5238 | 8.3254 | 90.9091 | 0 | 1 |
| nvidia/nemotron-3.5-lightning | 82/237 | 16.4557 | 56.8555 | 13.6905 | 19.2162 | 47.5610 | 0 | 41 |
| qwen/qwen-2.5-7b-instruct | 126/237 | 41.7722 | 77.3673 | 39.2460 | 44.3391 | 78.5714 | 1 | 16 |
| qwen/qwen3.8-27b | 221/237 | 91.9831 | 98.8095 | 91.5873 | 93.6191 | 98.6425 | 0 | 0 |
| z-ai/glm-5.3-flash | 1/237 | 0.4219 | 7.1429 | 0.3968 | 0.7519 | 100.0000 | 0 | 0 |
