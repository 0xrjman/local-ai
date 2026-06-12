# MTP Config Concurrent Bench Results (max_num_seqs=3)

Date: 2026-06-12
Config: vLLM NVFP4+MTP (compose/mtp.yml)

| Param | Value |
|-------|-------|
| Model | Qwen3.6-27B NVFP4+MTP |
| KV cache | fp8_e4m3 |
| Context | 219,200 tokens |
| MTP | n=3 (speculative decoding) |
| max_num_seqs | 3 |
| GPU | RTX 5090, 32GB, 98% util |

## Results

### 20K prompt (actual: 12,812 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 73.7 | 73.7 | 6786ms | 6786ms |
| 2 | 130.2 | 65.8 | 7601ms | 7680ms |
| 4 | 112.1 | 39.9 | 13021ms | 17839ms |
| 6 | **202.2** | 50.0 | 11150ms | 14840ms |

Peak: 202.2 TPS @ concurrency 6

### 50K prompt (actual: 32,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 72.1 | 72.1 | 6937ms | 6937ms |
| 2 | 132.1 | 66.3 | 7543ms | 7567ms |
| 4 | 137.4 | 55.5 | 9648ms | 14554ms |
| 6 | **180.0** | 45.1 | 12289ms | 16671ms |

Peak: 180.0 TPS @ concurrency 6

### 100K prompt (actual: 64,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 62.5 | 62.5 | 8004ms | 8004ms |
| 2 | 121.7 | 61.0 | 8197ms | 8219ms |
| 4 | 118.3 | 47.2 | 11306ms | 16900ms |
| 6 | **166.4** | 41.1 | 13473ms | 18033ms |

Peak: 166.4 TPS @ concurrency 6

## Comparison: max_num_seqs 2 vs 3

| Prompt | max_seqs=2 peak | max_seqs=3 peak | Gain |
|--------|----------------|----------------|------|
| 20K | 144.6 TPS @ c=2 | 202.2 TPS @ c=6 | +40% |
| 50K | 134.1 TPS @ c=4 | 180.0 TPS @ c=6 | +34% |
| 100K | 127.9 TPS @ c=2 | 166.4 TPS @ c=6 | +30% |

## Analysis

- **max_num_seqs=3 unlocks concurrency 6** — aggregate TPS jumps significantly
- 20K: 202 TPS (was 145) — 40% improvement at concurrency 6
- 50K: 180 TPS (was 134) — 34% improvement at concurrency 6
- 100K: 166 TPS (was 128) — 30% improvement at concurrency 6
- Concurrency 6 beats concurrency 4 at all prompt sizes
- TTFT at c=6 is reasonable: 11-18s (vs 13-24s with max_seqs=2)
- Per-request TPS at c=6: 41-50 (still decent)

## Conclusion

**max_num_seqs=3 is a significant upgrade over 2.**
Throughput ceiling increases 30-40% across all prompt sizes.
TTFT stays manageable even at concurrency 6.
For batch/high-throughput workloads, this is the better default.
For latency-sensitive single requests, concurrency 1 still gives ~73 TPS.
