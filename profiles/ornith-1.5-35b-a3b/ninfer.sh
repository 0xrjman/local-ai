#!/usr/bin/env bash
# Ornith-1.5-35B-A3B (qwen3.6-35b-a3b artifact) - NInfer build (.ninfer)
# local: $HOME/models/ninfer/Ornith-1.5-35B-A3B-NInfer/ornith_1_5_35b_a3b.ninfer (22783246080 B, groupwise-int)
# refetch: huggingJDE/Ornith-1.5-35B-A3B-NInfer (ornith_1_5_35b_a3b.ninfer, 22783246080 B, downloaded 2026-09-09)
# sha256: bc58fa4900d99560904bb94987704e712091a8e72a1a91d07242313631a919a3
# Artifact embeds MTP + DFlash drafts and a 27-layer vision tower, so SPEC=dflash
# (v1 — the 35B target compiles DFlashConfig::backend=DFlash; dflash2 is 27B-only
# and FATALs here: "selected masked draft backend is not supported by this target")
# needs no companion file.
set -euo pipefail
# load repo-root .env (gitignored) — real API key etc.
_sdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_sdir/../../.env" ]; then set -a; . "$_sdir/../../.env"; set +a; fi

CONTAINER=ninfer-ornith-35b-a3b
IMAGE="${IMAGE:-ninfer:latest}"
MODEL_DIR=$HOME/models/ninfer/Ornith-1.5-35B-A3B-NInfer
MODEL_FILE=/models/ornith_1_5_35b_a3b.ninfer
PORT=8020
# See qwen38-27b/ninfer.sh: the JSONL sink is the only place an engine failure's
# exception text survives. Shared dir by design — segment by server_instance_id.
JSONL_DIR="${JSONL_DIR:-$HOME/ninfer-logs}"
API_KEY="${API_KEY:-}"
API_ARGS=()
if [ -n "$API_KEY" ]; then API_ARGS+=(--api-key "$API_KEY"); fi
MODEL_ID=local
# ---- capacity model, recomputed from the artifact manifest ------------------
# 40 text layers: 30 GDN (no KV) + 10 full attention (3,7,...,39), plus the
# flat mtp layer's attention = 11 KV stores. Each is 2 kv_heads x head_dim 256
# (query_key_gate_value [9216,2048]; O [2048,4096]). Bytes/token (K+V per head)
# from the 27B table: nvfp4 288, k8v4 402, fp8 516.
#   nvfp4: 11 x 2 x 288 = 6336 B/token   (vs 27B's 19584 — 3.09x cheaper)
#   k8v4:  11 x 2 x 402 = 8844 B/token
# A full 262144-token context costs 1.52 GiB at nvfp4 (3.9% of the 32.6 GiB
# card). Weights ~21.2 GiB resident leaves ~11.4 GiB; StateImages at
# MAX_CONCURRENCY=4 are (4+4) x 147 MiB = 1.15 GiB; the 6-layer dflash draft is
# in-artifact (~2-4.5 GiB by the 27B dflash2 pool-shrink precedent) plus auto's
# 1 GiB headroom. Every dtype fits 262144 with room to spare, so unlike the 27B
# cell there is no (SPEC:VISION:KV_DTYPE) pool table to look up — 262144 is
# ceiling-bound (256K native context for the qwen3.6 family), not pool-bound.
# nvfp4 stays the default for the same reason as 27B: pool capacity, not speed.
# Verified 2026-09-09 (SPEC=dflash K=7, VISION=1, nvfp4 auto):
# kv_capacity_tokens=342848 (pages 5,357/16,384, runtime 5.83 GiB, free 1.63 GiB,
# weights 20.4 GiB, ready in 19.8s, ~435 decode TPS on a 200-token Chinese chat).
# Engine validates reservations at startup and exits clean, so raising anything
# here is safe to try.
KV_DTYPE="${KV_DTYPE:-nvfp4}"
MAX_CONTEXT="${MAX_CONTEXT:-262144}"
KV_CAPACITY="${KV_CAPACITY:-auto}"
# 8 host state slots (engine constant) x a max-length 1.52 GiB session needs
# ~12.2 GiB pinned; 16 GiB covers it with margin. Keep total Shmem < ~40 GiB
# on this 62.5 GiB box (zram swap makes it unreclaimable).
HOST_KV_MIB="${HOST_KV_MIB:-16384}"
# max_concurrency stays at 4 (hard limit [1,8]; device_state_slots tracks it,
# so raising it costs VRAM twice and shrinks the pool). All context-cache
# capacity flags stay at engine defaults — every override tried on this box
# made TTFT worse (see qwen38-27b/ninfer.sh header + skill: issue #144).
# max_shared_prefixes deliberately NOT passed: = max_concurrency (4) is the
# engine default; the msp=0 wedge dodge was a confirmed misattribution.
MAX_CONCURRENCY="${MAX_CONCURRENCY:-4}"
# Override per-run without editing (fish login shell: use env):
#   env VISION=0 bash ninfer.sh start
VISION="${VISION:-1}"
VISION_FLAG=(--vision)
if [ "$VISION" = 0 ]; then VISION_FLAG=(); fi
# SPEC=dflash (default, K range [1,15]) | mtp ([1,5]); drafts are embedded.
# K=7 verified on this artifact (dflash) / mtp 3 is its manifest value.
SPEC="${SPEC:-dflash}"
case "$SPEC" in
  dflash) DRAFT_TOKENS="${DRAFT_TOKENS:-7}" ;;
  mtp)    DRAFT_TOKENS="${DRAFT_TOKENS:-3}" ;;
  *) echo "SPEC must be dflash|mtp (got '$SPEC')" >&2; exit 1 ;;
esac
PRESERVE_THINKING="${PRESERVE_THINKING:-0}"
PRESERVE_FLAG=()
if [ "$PRESERVE_THINKING" = 1 ]; then PRESERVE_FLAG=(--preserve-thinking); fi

action="${1:-status}"

start() {
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "already running"
    return
  fi
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  echo "stopping ninfer-qwen38-27b / sglang-qwen38 / vllm-qwen38 (one GPU)..."
  docker stop ninfer-qwen38-27b >/dev/null 2>&1 || true
  docker stop sglang-qwen38 >/dev/null 2>&1 || true
  docker stop vllm-qwen38 >/dev/null 2>&1 || true
  docker rm -f ninfer-qwen38-27b >/dev/null 2>&1 || true
  echo "vision=$VISION  max-context=$MAX_CONTEXT  kv-dtype=$KV_DTYPE"
  docker run -d --name "$CONTAINER" --restart unless-stopped \
    --runtime=nvidia --gpus all \
    -p ${PORT}:${PORT} \
    -v ${MODEL_DIR}:/models:ro,z \
    -v ${JSONL_DIR}:/reqlog:z \
    "$IMAGE" ninfer-serve "$MODEL_FILE" \
    --host 0.0.0.0 --port ${PORT} --cors \
    --request-log-jsonl /reqlog/requests.jsonl \
    "${API_ARGS[@]}" --model-id ${MODEL_ID} \
    --max-context ${MAX_CONTEXT} --kv-capacity ${KV_CAPACITY} --kv-dtype ${KV_DTYPE} \
    --max-concurrency ${MAX_CONCURRENCY} --pending-timeout-ms 90000 --host-kv-mib ${HOST_KV_MIB} \
    "${VISION_FLAG[@]}" \
    "${PRESERVE_FLAG[@]}" \
    --spec "$SPEC" --draft-tokens "$DRAFT_TOKENS" --lm-head-draft
  echo "started, tail logs with: $0 logs"
  # resolve symlink first: when invoked via a symlink, BASH_SOURCE is the link
  _self="$(readlink -f "${BASH_SOURCE[0]}")"
  _profiles_dir="$(cd "$(dirname "$_self")/.." && pwd)"
  echo "ninfer" > "$_profiles_dir/watchdog/.last-engine" 2>/dev/null || true
  _dash="$_profiles_dir/dashboard/dashboard.sh"
  if [ "${NINFER_NO_DASH:-0}" != "1" ]; then
    [ -f "$_dash" ] && bash "$_dash" start || true
  fi
}

stop() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  echo "stopped. siblings left stopped -- restart yourself if needed: bash ../qwen38-27b/ninfer.sh start | docker start sglang-qwen38 | docker start vllm-qwen38"
}

status() {
  if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "${CONTAINER}: not running"
  else
    docker ps -a --filter "name=$CONTAINER" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  fi
  echo "---"
  nvidia-smi --query-gpu=memory.used,memory.total,memory.free --format=csv
}

logs() {
  docker logs -f --tail 100 "$CONTAINER"
}

case "$action" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  logs) logs ;;
  *) echo "usage: $0 {start|stop|status|logs}"; exit 1 ;;
esac
