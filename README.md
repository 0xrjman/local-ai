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
╔══════════════════════════════════════════════════╗
║  5090-ai  ·  Qwen3.6 NVFP4+MTP  ·  RTX 5090   ║
╚══════════════════════════════════════════════════╝

  ▸ [1] >  Start server
    [2] x  Stop server
    [3] o  Status
    [4] [log] Logs (tail -f)
    [5] [bench] Benchmark
    [6] [test] Test request
    [7] [model] Model info
    [8] [cfg]  Config (.env)
    [9] [install] Install 5090-ai to system
    [a] [hermes] Install Hermes Agent
    [b] [hermes-cfg] Configure Hermes for Local LLM
    [c] [multica] Multica (localhost:3000)

  [↑↓] move  [Enter] select  [1-9/a/b/c] direct  [q/0] quit
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

- **Qwen3.6-27B-Text-NVFP4-MTP** by sakamakismile
- https://huggingface.co/sakamakismile/Qwen3.6-27B-Text-NVFP4-MTP
- NVFP4 (Blackwell FP4 tensor cores)
- MTP n=3 (Multi-Token Prediction)
- fp8_e4m3 KV cache
- 224K context

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
│   └── mtp.yml             # Docker Compose for vLLM
├── scripts/
│   ├── bench.sh            # Benchmark script
│   └── launch.sh           # Standalone launcher
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
