# MTP Config Concurrent Bench Results

Date: 2026-06-12
Config: vLLM NVFP4+MTP (compose/mtp.yml)

| Param | Value |
|-------|-------|
| Model | Qwen3.6-27B NVFP4+MTP |
| KV cache | fp8_e4m3 |
| Context | 219,200 tokens |
| MTP | n=3 (speculative decoding) |
| max_num_seqs | 2 |
| GPU | RTX 5090, 32GB |

## Results

### 20K prompt (actual: 12,812 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 88.8 | 88.8 | 5630ms | 5630ms |
| 2 | 80.1 | 58.0 | 9537ms | 12491ms |
| 4 | 86.5 | 43.3 | 14627ms | 23133ms |
| 6 | **88.9** | 36.3 | 19479ms | 33753ms |

Peak: 88.9 TPS @ concurrency 6

### 50K prompt (actual: 32,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | **89.0** | 89.0 | 5619ms | 5619ms |
| 2 | 79.3 | 58.0 | 9581ms | 12607ms |
| 4 | 81.3 | 42.0 | 15532ms | 24608ms |
| 6 | 85.4 | 34.8 | 20389ms | 35138ms |

Peak: 89.0 TPS @ concurrency 1

### 100K prompt (actual: 64,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 67.2 | 67.2 | 7437ms | 7437ms |
| 2 | 69.0 | 53.5 | 10690ms | 14484ms |
| 4 | 74.9 | 37.5 | 16923ms | 26719ms |
| 6 | **75.6** | 30.8 | 23103ms | 39687ms |

Peak: 75.6 TPS @ concurrency 6

## Analysis

- **Short prompt (20K)**: throughput scales with concurrency, peak 88.9 TPS @ c=6
- **Medium prompt (50K)**: best at concurrency 1 (89.0 TPS), no benefit from concurrency
- **Long prompt (100K)**: peak 75.6 TPS @ c=6, but TTFT degrades severely (23-40s)
- Single-request TPS: 88-89 (short/medium), 67 (long) — MTP speculation boosts decode speed
- Concurrency 2 always hurts per-request TPS without improving aggregate (except 100K)
- GPU bottleneck is compute-bound; higher concurrency just queues requests

## Conclusion

MTP config optimal concurrency:
- Short prompts (≤20K): concurrency 6 for throughput, 1 for latency
- Medium prompts (~50K): concurrency 1 (no benefit from concurrency)
- Long prompts (~100K): concurrency 6 if throughput matters, but TTFT >20s

For interactive use: **concurrency 1-2** is best. MTP gives ~89 TPS single-request.
max_num_seqs=2 is a good default — balances throughput and latency.
