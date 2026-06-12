# MTP Config Concurrent Bench Results (max_num_seqs=4)

Date: 2026-06-12
Config: vLLM NVFP4+MTP (compose/mtp.yml)

| Param | Value |
|-------|-------|
| Model | Qwen3.6-27B NVFP4+MTP |
| KV cache | fp8_e4m3 |
| Context | 219,200 tokens |
| MTP | n=3 (speculative decoding) |
| max_num_seqs | 4 |
| GPU | RTX 5090, 32GB, 98% util, 236W, 56°C |

## Results

### 20K prompt (actual: 12,812 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 69.4 | 69.4 | 7203ms | 7203ms |
| 2 | 129.1 | 65.8 | 7605ms | 7744ms |
| 4 | **242.8** | 62.5 | 8003ms | 8236ms |
| 6 | 220.9 | 59.2 | 9254ms | 13579ms |

Peak: 242.8 TPS @ concurrency 4

### 50K prompt (actual: 32,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 71.7 | 71.7 | 6974ms | 6974ms |
| 2 | 131.6 | 66.4 | 7535ms | 7602ms |
| 4 | **221.6** | 58.4 | 8569ms | 9024ms |
| 6 | 199.3 | 55.6 | 9875ms | 15053ms |

Peak: 221.6 TPS @ concurrency 4

### 100K prompt (actual: 64,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 63.5 | 63.5 | 7871ms | 7871ms |
| 2 | 121.2 | 60.7 | 8233ms | 8254ms |
| 4 | **204.5** | 51.9 | 9634ms | 9781ms |
| 6 | 192.9 | 50.0 | 10833ms | 15552ms |

Peak: 204.5 TPS @ concurrency 4

## Comparison: max_num_seqs scaling

| Prompt | seqs=2 peak | seqs=3 peak | seqs=4 peak | Best |
|--------|------------|------------|------------|------|
| 20K | 145 TPS @ c=2 | 202 TPS @ c=6 | **243 TPS @ c=4** | seqs=4 |
| 50K | 134 TPS @ c=4 | 180 TPS @ c=6 | **222 TPS @ c=4** | seqs=4 |
| 100K | 128 TPS @ c=2 | 166 TPS @ c=6 | **205 TPS @ c=4** | seqs=4 |

## Analysis

- **Concurrency 4 is the sweet spot** — peaks at all prompt sizes
- 20K: 243 TPS — 3.3x single-request throughput
- 50K: 222 TPS — 3.1x single-request throughput
- 100K: 205 TPS — 3.2x single-request throughput
- Concurrency 6 still works but TTFT degrades (13-16s p99) with minimal TPS gain
- Per-request TPS barely drops from c=1 to c=4 (69→63 for 20K), excellent scaling
- TTFT at c=4 is very reasonable: 8-10s avg across all prompt sizes

## Conclusion

**max_num_seqs=4 is optimal for MTP config.**
- 243 TPS aggregate throughput (best across all configs tested)
- Concurrency 4 = 3.3x throughput with minimal latency penalty
- Concurrency 6 is diminishing returns
