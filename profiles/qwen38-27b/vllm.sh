#!/usr/bin/env bash
# Qwen3.8-27B-NVFP4 - unsloth build - vLLM
# ckpt (HF): unsloth/Qwen3.8-27B-NVFP4 (base: Qwen/Qwen3.8-27B)
# refetch:   hf download unsloth/Qwen3.8-27B-NVFP4 --local-dir $HOME/data/models/qwen3.8-27b-nvfp4-unsloth
set -euo pipefail
# load repo-root .env (gitignored) — real API key etc.
_sdir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
if [ -f "$_sdir/../../.env" ]; then set -a; . "$_sdir/../../.env"; set +a; fi
NAME=vllm-qwen38
IMG=vllm/vllm-openai:v0.27.1
MODEL=$HOME/data/models/qwen3.8-27b-nvfp4-unsloth
PORT=8020
API_KEY="${API_KEY:-}"
API_ARGS=()
if [ -n "$API_KEY" ]; then API_ARGS+=(--api-key "$API_KEY"); fi

SPEC_CONFIG='{"method": "mtp", "num_speculative_tokens": 2}'

start() {
  docker ps -a --format '{{.Names}}' | grep -qx "$NAME" && docker rm -f "$NAME" >/dev/null
  docker run -d --name "$NAME" --runtime=nvidia --gpus all --restart=always \
    -p "$PORT":8000 --shm-size 16g \
    -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,max_split_size_mb:512 \
    -e VLLM_USE_FLASHINFER_SAMPLER=1 \
    -e VLLM_NO_USAGE_STATS=1 \
    -v "$MODEL":/models \
    "$IMG" \
    /models \
    --served-model-name local \
    "${API_ARGS[@]}" \
    --max-model-len 160000 \
    --gpu-memory-utilization 0.98 \
    --kv-cache-dtype fp8_e4m3 \
    --max-num-seqs 8 \
    --max-num-batched-tokens 4096 \
    --enable-prefix-caching \
    --enable-chunked-prefill \
    --performance-mode interactivity \
    --reasoning-parser qwen3 \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --speculative-config "$SPEC_CONFIG"
  echo "started: $NAME (port $PORT, auth=$([ -n "$API_KEY" ] && echo on || echo off), restart=always, spec=mtp)"
  echo "log:   bash $0 logs"
  echo "stop:  bash $0 stop"
  _profiles_dir="$(cd "$_sdir/.." && pwd)"
  echo "vllm" > "$_profiles_dir/watchdog/.last-engine" 2>/dev/null || true
  _dash="$_profiles_dir/dashboard/dashboard.sh"
  [ -f "$_dash" ] && bash "$_dash" start || true
}

stop()   { docker rm -f "$NAME" >/dev/null 2>&1 && echo "stopped: $NAME" || echo "not running"; }
status() { docker ps --filter name="$NAME" --format '{{.Names}} {{.Status}} {{.Ports}}'; }
logs()   { docker logs -f "$NAME"; }

case "${1:-start}" in
  start|stop|status|logs) "${1:-start}" ;;
  *) echo "usage: $0 [start|stop|status|logs]"; exit 1 ;;
esac