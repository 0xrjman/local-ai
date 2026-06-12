# TurboQuant Config Concurrent Bench Results

Date: 2026-06-12
Config: vLLM NVFP4 + TurboQuant 4-bit KV (compose/nvfp4-turboquant.yml)

| Param | Value |
|-------|-------|
| Model | Qwen3.6-27B NVFP4 (no MTP) |
| KV cache | turboquant_4bit_nc |
| Context | 120,000 tokens |
| MTP | none |
| max_num_seqs | 6 |
| GPU | RTX 5090, 32GB, 94% util |

## Results

### 20K prompt (actual: 12,812 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 75.7 | 75.7 | 6605ms | 6605ms |
| 2 | **144.6** | 72.3 | 6914ms | 6918ms |
| 4 | 143.4 | 53.7 | 10425ms | 13949ms |
| 6 | 138.4 | 42.4 | 14350ms | 21673ms |

Peak: 144.6 TPS @ concurrency 2

### 50K prompt (actual: 32,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 70.5 | 70.5 | 7093ms | 7093ms |
| 2 | 127.1 | 65.6 | 7624ms | 7870ms |
| 4 | **134.1** | 49.8 | 11205ms | 14910ms |
| 6 | 131.7 | 41.0 | 14939ms | 22784ms |

Peak: 134.1 TPS @ concurrency 4

### 100K prompt (actual: 64,012 tokens)
| Concurrency | AggTPS | ReqTPS | TTFT avg | TTFT p99 |
|-------------|--------|--------|----------|----------|
| 1 | 65.4 | 65.4 | 7646ms | 7646ms |
| 2 | **127.9** | 64.1 | 7800ms | 7821ms |
| 4 | 120.8 | 43.4 | 12641ms | 16555ms |
| 6 | 125.6 | 37.8 | 15973ms | 23884ms |

Peak: 127.9 TPS @ concurrency 2

## Analysis

- **Short prompt (20K)**: optimal concurrency=2, throughput ceiling ~145 TPS
- **Medium prompt (50K)**: optimal concurrency=4, but TTFT already degrades noticeably
- **Long prompt (100K)**: optimal concurrency=2, TTFT degrades sharply at concurrency 4
- Longer prompt → lower per-request TPS (75→70→65) due to prefill overhead
- GPU fully loaded: 98% util, 31956/32607 MiB VRAM, 229W, 55°C
- Zero failures; bottleneck is compute, not VRAM

## Conclusion

TurboQuant default max_num_seqs=6 is too aggressive.
Best concurrency is 2 for 20K/100K prompts, 4 for 50K.
Without MTP speculation, single-request TPS is lower (~75 vs MTP's ~92),
but aggregate throughput ceiling is similar (~145 TPS).
Throughput bottleneck is GPU compute, not speculative decoding.
