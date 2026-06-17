# Compose Files

## vLLM — Unified (`vllm.yml`)

All vLLM configs use a single compose file driven by env vars:

| Mode | Model | KV Cache | Context | Notes |
|---|---|---|---|---|
| `text-mtp` | AEON-XS Text | fp8\_e4m3 | 228K | Text-only, fastest prefill |
| `vision-mtp` | AEON-XS Vision | fp8\_e4m3 | 208K | Baseline vision |
| `vision-tq-mtp` | AEON-XS Vision | turboquant | 324K | Max context, Genesis patches |
| `huihui-vision-mtp` | Huihui Vision | fp8\_e4m3 | 208K | [deprecated] compressed-tensors |
| `huihui-vision-tq-mtp` | Huihui Vision | turboquant | 312K | [deprecated] Genesis patches |

**Add a new base model**: just add a case in `5090-ai.sh:export_vllm_vars()` — no new compose files needed.

## Beellama Configs

| File | Draft | Context | Vision |
|---|---|---|---|
| `beellama/dflash-vision.yml` | DFlash IQ4\_XS | 262K | yes |
| `beellama/qwopus-mtp-vision.yml` | MTP draft=2 | 262K | yes |

## Usage

Run `./5090-ai.sh` menu to switch configs, or:

```bash
# Switch
ENGINE=vision-tq-mtp ./5090-ai.sh up
```
