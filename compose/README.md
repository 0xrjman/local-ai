# Compose Files

## Available Engines

### vLLM NVFP4+MTP
- File: `mtp.yml`
- Model: Qwen3.6-27B NVFP4 (sakamakismile)
- Engine: vLLM v0.22.1
- Features: NVFP4, MTP n=3, fp8 KV, 224K ctx

### Beellama DFlash Vision
- File: `beellama/dflash-vision.yml`
- Model: Qwen3.6-27B Q5_K_S GGUF
- Engine: beellama.cpp (Anbeeld fork)
- Features: DFlash spec-dec, vision (mmproj), 262K ctx

## Usage

Set COMPOSE_FILE env or use 5090-ai menu to switch engines.
