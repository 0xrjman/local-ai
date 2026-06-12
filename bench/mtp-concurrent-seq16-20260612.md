# MTP Config Concurrent Bench Results (max_num_seqs=16)

Date: 2026-06-12
Config: vLLM NVFP4+MTP (compose/mtp.yml)

| Param | Value |
|-------|-------|
| Model | Qwen3.6-27B NVFP4+MTP |
| KV cache | fp8_e4m3 |
| Context | 219,200 tokens |
| MTP | n=3 (speculative decoding) |
| max_num_seqs | 16 |
| GPU | RTX 5090, 32GB, 98% util |

## Results

### 20K prompt (actual: 12,812 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 76.6 | 76.6 | 6528ms | 6528ms |
| 2 | 127.4 | 64.8 | 7716ms | 7851ms |
| 4 | 247.1 | 63.3 | 7903ms | 8095ms |
| 6 | 385.9 | 68.3 | 7332ms | 7774ms |
| 8 | 485.3 | 62.1 | 8060ms | 8243ms |
| 10 | 551.9 | 58.1 | 8622ms | 9059ms |
| 12 | **624.3** | 54.8 | 9137ms | 9610ms |
| 14 | 442.5 | 51.3 | 10117ms | 15820ms |
| 16 | 492.3 | 48.8 | 10843ms | 16249ms |

Peak: 624.3 TPS @ concurrency 12

### 50K prompt (actual: 32,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 69.7 | 69.7 | 7177ms | 7177ms |
| 2 | 128.2 | 66.1 | 7569ms | 7799ms |
| 4 | FAIL | - | - | - |
| 6-16 | ALL FAIL | - | - | - |

Peak: 128.2 TPS @ concurrency 2

### 100K prompt (actual: 100,000 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1-16 | ALL FAIL | - | - | - |

Peak: N/A

## Analysis

- **20K: 624 TPS @ c=12!** — 8x single-request throughput, incredible scaling
- 20K sweet spot: c=12 (624 TPS), c=14-16 drops due to scheduling overhead
- 50K: fails at c≥4 — max_num_seqs=16 allocates too little KV per sequence
- 100K: fails at c=1 — 100K tokens likely exceeds per-sequence KV allocation
- max_num_seqs=16 is too aggressive for large prompts — KV cache partitioning issue

## Conclusion

**max_num_seqs=16 works brilliantly for short prompts (624 TPS!) but breaks on large prompts.**

The optimal max_num_seqs depends on prompt size:
- Short (≤20K): seqs=16, c=12 → 624 TPS
- Medium (~50K): seqs=6, c=6 → 345 TPS
- Long (~100K): seqs=4, c=4 → 205 TPS

For a general-purpose config, **max_num_seqs=6 is the best compromise** — works at all prompt sizes with strong throughput.
