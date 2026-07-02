# local-ai 🚀

Multi-engine LLM serving for **NVIDIA RTX 5090**, **1–8× B200** — AEON, Huihui, GLM-5.2, Beellama.

```bash
git clone https://github.com/0xrjman/local-ai && cd local-ai
./local-ai.sh
```

## Quick Start

```text
┌────────────────────────────────────────────────────────┐
│  local-ai  ·  AEON-XS MTP (Vision)                    │
│  RTX 5090                                             │
└────────────────────────────────────────────────────────┘

  Config:    AEON-XS MTP (Vision) (vision-mtp)
  Compose:   ~/yubo/yubo/llm/compose/vllm.yml
  Container: vllm-vision-mtp
  Status:    o stopped
  GPU:     0, NVIDIA B200, 0 MiB, 183359 MiB
  Models:  ~/yubo/yubo/llm/models

  ▸ [1] >  Start server
    [2] x  Stop server
    [3] o  Status
    ...
    [a] [install] Install local-ai to system
```

## Engine Configurations

Access via `./local-ai.sh config` or set `ENGINE=... ./local-ai.sh up`.

| # | Engine | GPU | VRAM/GPU | Context | Notes |
|---|--------|-----|----------|---------|-------|
| 1 | **AEON-XS MTP (Vision)** 🟢 | 1 × 5090/B200 | ~170 GB | 208K | FP8 KV · MTP3 · Qwen3.6-27B |
| 2 | **AEON-XS MTP+TQ (Vision)** | 1 × B200 | ~170 GB | 324K | TurboQuant KV · Genesis patches |
| 3 | **AEON-XS MTP (Text)** 🟢 | 1 × 5090/B200 | ~170 GB | 228K | Text-only, lower VRAM |
| 4 | **Huihui NVFP4+MTP (Vision)** | 1 × B200 | ~170 GB | 208K | Abliterated variant [deprecated] |
| 5 | **Huihui NVFP4+MTP+TQ (Vision)** | 1 × B200 | ~170 GB | 312K | Full Genesis [deprecated] |
| 6 | **Beellama DFlash Vision** | 1 × 5090/B200 | ~24 GB | 262K | GGUF · iMatrix |
| 7 | **Beellama Qwopus MTP Vision** | 1 × 5090/B200 | ~24 GB | 262K | GGUF · MTP · Coder |
| 8 | **GLM-5.2 NVFP4 · vLLM** 🆕 | **8 × B200** | ~116 GB | **1M** | 753B MoE · 256 experts · TP=8 |
| 9 | **GLM-5.2 NVFP4 · SGLang** 🆕 | **8 × B200** | ~116 GB | **1M** | SGLang dev · TP=8 [WIP] |

> 🟢 = production-ready  ·  🆕 = newly added

## Hardware Matrix

| Hardware | Configs | Notes |
|----------|---------|-------|
| **RTX 5090** (32 GB) | #6, #7 | GGUF quantized models only |
| **1 × B200** (179 GB) | #1–#5 | Full NVFP4 + MTP |
| **8 × B200** (1.4 TB) | #8, #9 | GLM-5.2 753B · TP=8 |

## Install to System

```bash
./local-ai.sh  →  choose [a] Install local-ai to system
# Then use from anywhere:
local-ai up
```

## Manual CLI

| Command | Description |
|---------|-------------|
| `./local-ai.sh` | Interactive TUI menu |
| `./local-ai.sh up` | Start server |
| `./local-ai.sh down` | Stop server |
| `./local-ai.sh status` | Show server status |
| `./local-ai.sh logs` | Tail server logs |
| `./local-ai.sh bench` | Run benchmark |
| `./local-ai.sh config` | Edit `.env` |
| `./local-ai.sh model` | Show/set weights path |

Select engine inline:
```bash
ENGINE=vision-tq-mtp ./local-ai.sh up
ENGINE=glm-5.2-vllm ./local-ai.sh up
```

## Project Layout

```
local-ai/
├── local-ai.sh                  # Main TUI + config center
├── compose/
│   ├── vllm.yml                 # Unified vLLM compose (AEON/Huihui)
│   ├── glm-vllm.yml             # GLM-5.2 vLLM compose (TP=8)
│   ├── glm-sglang.yml           # GLM-5.2 SGLang compose (TP=8) [WIP]
│   ├── beellama/
│   │   ├── dflash-vision.yml
│   │   └── qwopus-mtp-vision.yml
│   └── _archive/                # Legacy configs
├── chat-templates/
│   ├── aeon-vision/
│   ├── aeon-text/
│   ├── huihui/
│   └── glm-5.2/
├── genesis/vllm/                # Genesis performance patches
├── cache/                       # Persistent torch/flashinfer/triton caches
├── models/                      # Weight files (symlink or download)
└── scripts/
    ├── bench.sh
    └── bench-scheduling.sh
```

## Adding a New Model

1. Add a `case` in `local-ai.sh:export_vllm_vars()`
2. Create compose file if using a different runtime
3. Add menu entry in `do_select_config()`
4. Add helpers in `config_label()`, `get_weights_subdir()`, `get_hf_repo()`

## Overview

- **Auto-install** — Install to system as `local-ai` command
- **Auto-config** — Prompts for first-time weight download/link
- **Benchmarks** — Built-in throughput & latency benchmarking
- **Multi-arch** — AEON, Huihui, GLM-5.2, Beellama
- **Dual runtime** — vLLM & SGLang support for GLM-5.2

---

<p align="center"><sub>Built for RTX 5090 · B200 · Blackwell</sub></p>
