#!/usr/bin/env bash
#
# Benchmark the running vLLM NVFP4+MTP server.
#   - 3 warmup + 5 measured runs per prompt (narrative + code)
#   - Reports wall_TPS, decode_TPS, TTFT, and prompt-processing throughput
#   - Shows MTP SpecDecoding metrics from docker logs
#
# Env vars:
#   URL            endpoint            (default: http://localhost:8020)
#   MODEL          served model name   (default: local)
#   CONTAINER      container name      (default: vllm-qwen36-nvfp4-mtp)
#   RUNS           measured runs       (default: 5)
#   WARMUPS        warmup runs         (default: 3)
#   ONLY           "narr" or "code"    (default: both)
#   QUIET          1 to skip per-run   (default: 0)
#
# Usage:
#   bash scripts/bench.sh
#   ONLY=code RUNS=10 bash scripts/bench.sh

set -euo pipefail

URL="${URL:-http://localhost:8020}"
MODEL="${MODEL:-local}"
CONTAINER="${CONTAINER:-vllm-qwen36-nvfp4-mtp}"
RUNS="${RUNS:-5}"
WARMUPS="${WARMUPS:-3}"
MAX_TOKENS_NARR="${MAX_TOKENS_NARR:-1000}"
MAX_TOKENS_CODE="${MAX_TOKENS_CODE:-800}"
PROMPT_NARR="${PROMPT_NARR:-Write a detailed 800-word essay explaining transformer attention.}"
PROMPT_CODE="${PROMPT_CODE:-Write a Python implementation of quicksort with comments explaining each step.}"
ONLY="${ONLY:-both}"
QUIET="${QUIET:-0}"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not in PATH." >&2; exit 1; }
}
need curl
need python3

if ! curl -sf "${URL}/v1/models" >/dev/null; then
  echo "ERROR: service not reachable at ${URL}/v1/models" >&2
  echo "  Start with: bash scripts/launch.sh" >&2
  exit 1
fi

python3 - "$URL" "$MODEL" "$WARMUPS" "$RUNS" "$QUIET" "$ONLY" \
            "$CONTAINER" "$PROMPT_NARR" "$MAX_TOKENS_NARR" \
            "$PROMPT_CODE" "$MAX_TOKENS_CODE" << 'PYEOF'
import json, re, shutil, subprocess, sys, time, urllib.request, statistics as s

(URL, MODEL, WARMUPS, RUNS, QUIET, ONLY,
 CONTAINER, PROMPT_NARR, MAX_NARR, PROMPT_CODE, MAX_CODE) = sys.argv[1:]
WARMUPS = int(WARMUPS); RUNS = int(RUNS); QUIET = int(QUIET) == 1
MAX_NARR = int(MAX_NARR); MAX_CODE = int(MAX_CODE)

def run_once(prompt, max_tokens):
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
    if not prompt_tokens:
        prompt_tokens = max(1, len(prompt.split()))
    return wall, ttft, completion_tokens, prompt_tokens

def fmt(label, wall, ttft, toks):
    decode_t = max(wall - ttft, 1e-6)
    wtps = toks / wall if wall > 0 else 0
    dtps = toks / decode_t
    line = f"  {label:<10s} wall={wall:6.2f}s  ttft={ttft*1000:6.0f}ms  toks={toks:>4d}  wall_TPS={wtps:6.2f}  decode_TPS={dtps:6.2f}"
    return wtps, dtps, ttft, line

def stats(name, xs, unit=""):
    m = s.mean(xs)
    sd = s.stdev(xs) if len(xs) > 1 else 0
    cv = (sd / m * 100) if m > 0 else 0
    return f"  {name:<14s} mean={m:7.2f}{unit}   std={sd:6.2f}   CV={cv:4.1f}%   min={min(xs):.2f}   max={max(xs):.2f}"

def scrape_prompt_throughput(container, n):
    if not container or container == "none" or shutil.which("docker") is None:
        return []
    try:
        proc = subprocess.run(
            ["docker", "logs", container],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, errors="replace", timeout=10, check=False,
        )
    except Exception:
        return []
    vals = [
        float(m.group(1))
        for m in re.finditer(r"Avg prompt throughput:\s*([0-9]+(?:\.[0-9]+)?)\s*tokens/s", proc.stdout)
    ]
    return vals[-max(n, 1):]

def run_set(label, prompt, max_tokens):
    print(f"\n========== {label.upper()} (prompt={len(prompt)} chars, max_tokens={max_tokens}) ==========")
    print(f"=== warmups ({WARMUPS}) ===")
    for i in range(WARMUPS):
        try:
            w, t, k, _ = run_once(prompt, max_tokens)
            _, _, _, line = fmt(f"warm-{i+1}", w, t, k)
            if not QUIET:
                print(line)
        except Exception as e:
            print(f"  warm-{i+1}  FAIL: {e}")
    print(f"\n=== measured ({RUNS}) ===")
    walls, decodes, ttfts = [], [], []
    for i in range(RUNS):
        try:
            w, t, k, _ = run_once(prompt, max_tokens)
            wtps, dtps, ttft, line = fmt(f"run-{i+1}", w, t, k)
            if not QUIET:
                print(line)
            walls.append(wtps); decodes.append(dtps); ttfts.append(ttft)
        except Exception as e:
            print(f"  run-{i+1}  FAIL: {e}")
    if walls:
        print(f"\n=== summary [{label}] (n={len(walls)}) ===")
        print(stats("wall_TPS",   walls))
        print(stats("decode_TPS", decodes))
        print(f"  TTFT          mean={s.mean(ttfts)*1000:6.0f}ms  std={s.stdev(ttfts)*1000 if len(ttfts) > 1 else 0:5.0f}ms  min={min(ttfts)*1000:.0f}ms  max={max(ttfts)*1000:.0f}ms")
        pp_vals = scrape_prompt_throughput(CONTAINER, len(walls))
        if pp_vals:
            print(stats("PP tok/s", pp_vals))
        else:
            print("  PP tok/s       n/a (docker log scrape unavailable)")

if ONLY in ("both", "narr"):
    run_set("narrative", PROMPT_NARR, MAX_NARR)
if ONLY in ("both", "code"):
    run_set("code", PROMPT_CODE, MAX_CODE)
PYEOF

# GPU state
if command -v nvidia-smi >/dev/null 2>&1; then
  echo ""
  echo "=== GPU state ==="
  nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total,power.draw,temperature.gpu \
             --format=csv,noheader
fi

# MTP / spec-decode stats
if command -v docker >/dev/null 2>&1 && docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo ""
  echo "=== Last 3 SpecDecoding metrics ==="
  docker logs "$CONTAINER" 2>&1 | grep "SpecDecoding metrics" | tail -3 || true
fi
