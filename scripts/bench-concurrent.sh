#!/usr/bin/env bash
#
# Concurrent throughput benchmark for vLLM server.
#   - Tests multiple concurrency levels (1, 2, 4, 6, 8, ...)
#   - Measures aggregate TPS, per-request TPS, TTFT at each level
#   - Finds throughput ceiling
#
# Env vars:
#   URL            endpoint            (default: http://localhost:8020)
#   MODEL          served model name   (default: qwen3.6)
#   LEVELS         concurrency levels  (default: "1 2 4 6 8 10")
#   RUNS           requests per level  (default: 8)
#   WARMUPS        warmup requests     (default: 2)
#   MAX_TOKENS     tokens per request  (default: 500)
#   PROMPT         prompt text         (default: essay prompt)
#
# Usage:
#   bash scripts/bench-concurrent.sh
#   LEVELS="1 2 4 8 16" RUNS=10 bash scripts/bench-concurrent.sh

set -euo pipefail

URL="${URL:-http://localhost:8020}"
MODEL="${MODEL:-qwen3.6}"
LEVELS="${LEVELS:-1 2 4 6 8 10}"
RUNS="${RUNS:-8}"
WARMUPS="${WARMUPS:-2}"
MAX_TOKENS="${MAX_TOKENS:-500}"
PROMPT="${PROMPT:-Write a detailed explanation of how transformer attention mechanisms work, covering self-attention, multi-head attention, and positional encoding.}"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not in PATH." >&2; exit 1; }
}
need curl
need python3

if ! curl -sf "${URL}/v1/models" >/dev/null; then
  echo "ERROR: service not reachable at ${URL}/v1/models" >&2
  exit 1
fi

echo "=== Concurrent Throughput Benchmark ==="
echo "  URL:         ${URL}"
echo "  Model:       ${MODEL}"
echo "  Levels:      ${LEVELS}"
echo "  Requests:    ${RUNS} per level"
echo "  Max tokens:  ${MAX_TOKENS}"
echo ""

python3 - "$URL" "$MODEL" "$RUNS" "$WARMUPS" "$MAX_TOKENS" "$PROMPT" $LEVELS << 'PYEOF'
import json, sys, time, urllib.request, statistics as s
from concurrent.futures import ThreadPoolExecutor, as_completed

URL = sys.argv[1]
MODEL = sys.argv[2]
RUNS = int(sys.argv[3])
WARMUPS = int(sys.argv[4])
MAX_TOKENS = int(sys.argv[5])
PROMPT = sys.argv[6]
LEVELS = [int(x) for x in sys.argv[7:]]

def send_request(prompt, max_tokens):
    """Send a single streaming request, return (wall_time, ttft, completion_tokens, prompt_tokens)."""
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.6,
        "top_p": 0.95,
        "stream": True,
        "stream_options": {"include_usage": True},
    }).encode()
    req = urllib.request.Request(f"{URL}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    t_send = time.time()
    ttft = None
    completion_tokens = 0
    prompt_tokens = 0
    with urllib.request.urlopen(req, timeout=600) as r:
        for line in r:
            line = line.decode("utf-8", errors="ignore").rstrip()
            if not line.startswith("data: "):
                continue
            payload = line[6:]
            if payload == "[DONE]":
                break
            try:
                chunk = json.loads(payload)
            except json.JSONDecodeError:
                continue
            choices = chunk.get("choices") or []
            if choices:
                delta = choices[0].get("delta", {})
                content = delta.get("content")
                if content and ttft is None:
                    ttft = time.time() - t_send
            usage = chunk.get("usage")
            if usage:
                completion_tokens = usage.get("completion_tokens", completion_tokens)
                prompt_tokens = usage.get("prompt_tokens", prompt_tokens)
    t_end = time.time()
    wall = t_end - t_send
    if ttft is None:
        ttft = wall
    return wall, ttft, completion_tokens, prompt_tokens

def run_concurrent(n_requests, prompt, max_tokens):
    """Run n_requests in parallel, return list of results."""
    results = []
    with ThreadPoolExecutor(max_workers=n_requests) as pool:
        futures = [pool.submit(send_request, prompt, max_tokens) for _ in range(n_requests)]
        for f in as_completed(futures):
            try:
                results.append(f.result())
            except Exception as e:
                results.append(None)
    return results

def analyze(results, label):
    """Analyze concurrent results, return dict of metrics."""
    ok = [r for r in results if r is not None]
    failed = len(results) - len(ok)
    if not ok:
        return {"label": label, "failed": failed, "n": 0}

    walls = [r[0] for r in ok]
    ttfts = [r[1] for r in ok]
    toks = [r[2] for r in ok]
    prompt_toks = [r[3] for r in ok]

    total_tokens = sum(toks)
    total_time = max(walls)  # wall clock = slowest request
    aggregate_tps = total_tokens / total_time if total_time > 0 else 0
    per_request_tps = [t / w for t, w in zip(toks, walls)]

    return {
        "label": label,
        "n": len(ok),
        "failed": failed,
        "total_tokens": total_tokens,
        "total_time": total_time,
        "aggregate_tps": aggregate_tps,
        "per_req_tps_mean": s.mean(per_request_tps),
        "per_req_tps_min": min(per_request_tps),
        "per_req_tps_max": max(per_request_tps),
        "ttft_mean": s.mean(ttfts),
        "ttft_p50": sorted(ttfts)[len(ttfts) // 2],
        "ttft_p99": sorted(ttfts)[int(len(ttfts) * 0.99)] if len(ttfts) > 1 else ttfts[0],
        "toks_mean": s.mean(toks),
    }

# ── Warmup ──────────────────────────────────────────────────────────────────
print("Warming up server...")
for i in range(WARMUPS):
    try:
        send_request(PROMPT, 100)
        print(f"  warm-{i+1}  OK")
    except Exception as e:
        print(f"  warm-{i+1}  FAIL: {e}")
print()

# ── Benchmark ───────────────────────────────────────────────────────────────
header = f"{'Conc':>4s}  {'Reqs':>4s}  {'AggTPS':>8s}  {'ReqTPS':>8s}  {'TTFT avg':>8s}  {'TTFT p99':>8s}  {'Toks/req':>8s}  {'Fail':>4s}"
print(header)
print("-" * len(header))

results_table = []

for level in LEVELS:
    t0 = time.time()
    raw = run_concurrent(level, PROMPT, MAX_TOKENS)
    m = analyze(raw, f"concurrency={level}")
    results_table.append(m)

    if m["n"] == 0:
        print(f"{level:>4d}  {'ALL FAILED':>4s}")
        continue

    print(f"{level:>4d}  {m['n']:>4d}  {m['aggregate_tps']:>8.1f}  "
          f"{m['per_req_tps_mean']:>8.1f}  {m['ttft_mean']*1000:>7.0f}ms  "
          f"{m['ttft_p99']*1000:>7.0f}ms  {m['toks_mean']:>8.0f}  "
          f"{m['failed']:>4d}")

# ── Summary ─────────────────────────────────────────────────────────────────
print("\n=== Summary ===")
valid = [m for m in results_table if m["n"] > 0]
if valid:
    best = max(valid, key=lambda m: m["aggregate_tps"])
    print(f"  Peak aggregate TPS:  {best['aggregate_tps']:.1f} at concurrency={best['label'].split('=')[1]}")
    print(f"  Per-request TPS:     {best['per_req_tps_mean']:.1f} (mean)")

    # Find where TTFT starts degrading
    baseline_ttft = valid[0]["ttft_mean"]
    for m in valid[1:]:
        if m["ttft_mean"] > baseline_ttft * 2:
            prev = valid[valid.index(m) - 1]
            print(f"  TTFT degrades at:    concurrency={m['label'].split('=')[1]} (2x baseline)")
            break
PYEOF

# GPU state
if command -v nvidia-smi >/dev/null 2>&1; then
  echo ""
  echo "=== GPU state ==="
  nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total,power.draw,temperature.gpu \
             --format=csv,noheader
fi
