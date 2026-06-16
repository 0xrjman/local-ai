# 5090-ai

Standalone AI server management for **RTX 5090** — vLLM NVFP4+MTP, Hermes Agent, and more.

## What this is

A unified TUI to manage your local AI stack:

## Quick Start

```bash
# Clone
git clone https://github.com/0xrjman/5090-ai && cd 5090-ai

# Run TUI
./5090-ai.sh
```

## Menu

```
╔══════════════════════════════════════════════════════════╗
║  5090-ai  ·  NVFP4+MTP  ·  RTX 5090                   ║
╚══════════════════════════════════════════════════════════╝

  Config: vllm (NVFP4+MTP)  |  Container: vllm-qwen36-nvfp4-mtp

  ▸ [1] >  Start server
    [2] x  Stop server
    [3] o  Status
    [4] [log] Logs (tail -f)
    [5] [bench] Benchmark
    [6] [test] Test request
    [7] [model] Model info
    [8] [config] Select Config
    [9] [cfg]  Config (.env)
    [a] [install] Install 5090-ai to system
    [b] [hermes] Install Hermes Agent
    [c] [hermes-cfg] Configure Hermes for Local LLM

  [↑↓] move  [Enter] select  [1-9/a/b/c] direct  [q/ESC] quit
```

## First Run

1. Select **[1] Start server**
2. If weights not found, guided setup:
   - Download from HuggingFace (~19 GB)
   - Specify existing weights directory
   - Symlink from another location
3. Progress bar with live logs during startup

## Features

- **Arrow key navigation** — ↑↓ + Enter
- **Number shortcuts** — 1-9, a, b, c for direct access
- **Live progress** — Progress bar with % and log streaming
- **Crash detection** — Auto-detects container restart loops
- **GPU monitoring** — nvidia-smi integration (temp, power, VRAM)
- **Auto-install** — Install to system as `5090-ai` command

## Model

**Qwen3.6-27B-Text-NVFP4-MTP** by sakamakismile
https://huggingface.co/sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP

| Config | NVFP4+MTP | NVFP4+TurboQuant |
|--------|-----------|-----------------|
| KV cache | fp8_e4m3 | turboquant_4bit_nc |
| Context | 219K (224K safe) | 120K |
| MTP | n=3 | none |
| max_num_seqs | **6** (default) | 6 |
| Single TPS | ~75-89 | ~16 (enforce-eager) |
| Peak AggTPS | **376 TPS** @ c=6 | 145 TPS @ c=2 |
| Status | **Production ready** | Experimental (workspace bug) |

## Benchmark Results (RTX 5090, MTP config, max_num_seqs=6)

Aggregate throughput (AggTPS) across concurrency levels and prompt sizes:

| Concurrency | 20K tokens | 50K tokens | 100K tokens |
|-------------|-----------|-----------|------------|
| 1 | 73 TPS | 76 TPS | 65 TPS |
| 2 | 133 TPS | 135 TPS | 120 TPS |
| 4 | 245 TPS | 231 TPS | 201 TPS |
| 6 | **391 TPS** | **360 TPS** | **282 TPS** |
| 8 | 280 TPS | 265 TPS | 249 TPS |
| 10 | 337 TPS | 316 TPS | 286 TPS |

- **Peak: 391 TPS** at concurrency 6, 20K prompt — 5.4x single-request throughput
- Single requests support up to **220K tokens** context (max_model_len=219200)
- Per-request TPS: ~75 TPS (short), ~63 TPS (100K) — MTP speculation boosts decode
- Per-request TPS barely drops at c=6 (65 vs 69) — near-linear GPU scaling
- TTFT stays flat at c=6: 7-9s avg — no queuing penalty
- `max_num_seqs=12` can reach 624 TPS for short prompts, but breaks on long prompts (OOM)
- `max_num_seqs=6` chosen for stability across all prompt sizes (20K-100K)

Detailed results in `bench/` directory.

## Configuration

### .env (vLLM)
```bash
MODEL_DIR=/path/to/models   # Where weights live
PORT=8020                    # API port
GPU_DEVICE=0                 # GPU index
```

### Hermes Config
Option **[b]** automatically configures:
- Model → qwen3.6 @ localhost:8020
- Compression → 85% threshold, 40% target
- Display → show reasoning, streaming
- Agent → disable env_probe, auto_bashrc

## Install as System Command

```bash
./5090-ai.sh
# Select [9] Install 5090-ai to system
# Creates symlink in ~/.local/bin/5090-ai
```

Then run `5090-ai` from anywhere.

## Structure

```
5090-ai/
├── 5090-ai.sh              # Main TUI script
├── compose/
│   └── mtp.yml             # vLLM NVFP4+MTP (default)
├── scripts/
│   ├── bench.sh            # Sequential benchmark
│   └── bench-concurrent.sh # Concurrent throughput benchmark
├── bench/                  # Benchmark result logs
├── cache/                  # vLLM/Triton/FlashInfer caches (gitignored)
├── models/                 # Model weights (gitignored)
├── .env.example            # Environment template
├── .gitignore
└── README.md
```

## Requirements

- Linux (Fedora/Ubuntu tested)
- NVIDIA RTX 5090 (32GB, sm_120 Blackwell)
- Docker + Docker Compose
- NVIDIA Container Toolkit

## Credits

- **vLLM** — https://github.com/vllm-project/vllm
- **Hermes Agent** — https://hermes-agent.nousresearch.com
- **Multica** — https://github.com/multica-ai/multica
- **Weights** — https://huggingface.co/sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP
