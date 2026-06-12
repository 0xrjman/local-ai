# MTP Config Concurrent Bench Results (max_num_seqs=6)

Date: 2026-06-12
Config: vLLM NVFP4+MTP (compose/mtp.yml)

| Param | Value |
|-------|-------|
| Model | Qwen3.6-27B NVFP4+MTP |
| KV cache | fp8_e4m3 |
| Context | 219,200 tokens |
| MTP | n=3 (speculative decoding) |
| max_num_seqs | 6 |
| GPU | RTX 5090, 32GB, 98% util, 251W, 58°C |

## Results

### 20K prompt (actual: 12,812 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 72.8 | 72.8 | 6865ms | 6865ms |
| 2 | 133.3 | 70.0 | 7155ms | 7503ms |
| 4 | 245.2 | 62.9 | 7951ms | 8157ms |
| 6 | **390.6** | 67.4 | 7424ms | 7680ms |
| 8 | 279.6 | 58.1 | 9230ms | 14308ms |
| 10 | 336.5 | 53.1 | 10410ms | 14858ms |
| 12 | 390.6 | 49.7 | 11280ms | 15361ms |
| 14 | 321.4 | 45.3 | 12943ms | 21777ms |
| 16 | 359.2 | 41.9 | 14225ms | 22269ms |

Peak: 390.6 TPS @ concurrency 6

### 50K prompt (actual: 32,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 76.2 | 76.2 | 6566ms | 6566ms |
| 2 | 134.8 | 68.0 | 7356ms | 7419ms |
| 4 | 231.1 | 60.3 | 8298ms | 8655ms |
| 6 | **360.3** | 61.9 | 8076ms | 8327ms |
| 8 | 264.8 | 53.1 | 10014ms | 15107ms |
| 10 | 316.4 | 48.5 | 11288ms | 15803ms |
| 12 | 354.8 | 45.0 | 12364ms | 16910ms |
| 14 | 304.4 | 41.9 | 13799ms | 22995ms |
| 16 | 333.4 | 39.3 | 15133ms | 23992ms |

Peak: 360.3 TPS @ concurrency 6

### 100K prompt (actual: 64,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 65.3 | 65.3 | 7655ms | 7655ms |
| 2 | 120.0 | 61.0 | 8196ms | 8330ms |
| 4 | 201.0 | 52.9 | 9458ms | 9949ms |
| 6 | **282.4** | 49.0 | 10218ms | 10623ms |
| 8 | 248.5 | 49.2 | 10765ms | 16095ms |
| 10 | 286.4 | 43.3 | 12551ms | 17458ms |
| 12 | 310.8 | 40.1 | 13866ms | 19305ms |
| 14 | 276.4 | 36.6 | 15682ms | 25323ms |
| 16 | 296.1 | 33.5 | 17433ms | 27015ms |

Peak: 310.8 TPS @ concurrency 12

## Analysis

- **Concurrency 6 is the sweet spot** — peaks at 20K and 50K, near-peak at 100K
- 20K: 391 TPS @ c=6 — 5.4x single-request throughput
- 50K: 360 TPS @ c=6 — 4.7x single-request throughput
- 100K: 282 TPS @ c=6, but c=12 reaches 311 TPS (still acceptable)
- Beyond c=6: TPS plateaus or drops, TTFT degrades significantly (15-27s p99)
- Per-request TPS at c=6: 49-67 (vs 65-76 at c=1) — excellent scaling
- TTFT at c=6: 7-10s avg — very reasonable
- All prompt sizes work at c=6 with max_num_seqs=6 — no OOM

## Conclusion

**max_num_seqs=6 with concurrency 6 is optimal.**
- 391 TPS peak (20K), 360 TPS (50K), 282 TPS (100K)
- 5x throughput with minimal latency penalty
- Works across all prompt sizes — no OOM on 100K prompts
- Beyond c=6: diminishing returns + TTFT degrades sharply
