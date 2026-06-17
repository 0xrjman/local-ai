# Compose Files

## vLLM Configs (AEON-XS series — recommended)

| File | KV Cache | Context | Vision | Notes |
|---|---|---|---|---|
| `text-mtp.yml` | fp8\_e4m3 | 228K | no | Text-only, fastest prefill |
| `vision-mtp.yml` | fp8\_e4m3 | 208K | yes | Baseline vision |
| `vision-tq-mtp.yml` | turboquant\_4bit\_nc | 324K | yes | Max context, Genesis patches + prealloc v2 |

## vLLM Configs (Huihui series — [deprecated])

| File | KV Cache | Context | Vision | Notes |
|---|---|---|---|---|
| `huihui-vision-mtp.yml` | fp8\_e4m3 | 208K | yes | compressed-tensors quant |
| `huihui-vision-tq-mtp.yml` | turboquant\_4bit\_nc | 312K | yes | All Genesis patches + prealloc v2 |

## Beellama Configs

| File | Draft | Context | Vision | Notes |
|---|---|---|---|---|
| `beellama/dflash-vision.yml` | DFlash IQ4\_XS | 262K | yes | Q5\_K\_S target |
| `beellama/qwopus-mtp-vision.yml` | MTP draft=2 | 262K | yes | Qwopus coder, no-thinking |

## Usage

Set `COMPOSE_FILE` env or use `./5090-ai.sh` menu to switch engines.
