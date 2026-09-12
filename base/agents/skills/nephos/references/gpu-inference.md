# Discrete-GPU inference

Use this reference when choosing or troubleshooting models on Nephos's NVIDIA
laptops. Re-check `nephos nodes` before placement; capability reporting is live and
a physical GPU is not schedulable when its driver is unhealthy.

## Fleet fit

As verified on 2026-09-07:

| Node | GPU | Architecture | VRAM | SGLang role |
|---|---|---:|---:|---|
| `gpu1` | RTX 3080 Laptop | Ampere, SM 8.6 | 8 GiB | Preferred always-on SGLang node when CUDA is healthy |
| `gpu2` | RTX 4070 Laptop | Ada, SM 8.9 | 8 GiB | Preferred fallback; newer kernels, otherwise the same memory ceiling |
| `fedora` | RTX 5070 Laptop | Blackwell | 8 GiB | Capable, but avoid by default because it hosts the main service stack |
| Mac Studio | Apple GPU | unified memory | 96 GiB | Use MLX, not CUDA SGLang |

An 8 GiB card needs room for weights, CUDA/SGLang overhead, activations, and KV
cache. A checkpoint being smaller than 8 GiB does not prove it fits. Request at
most `vram: 7Gi` so Nephos preserves operational headroom, and begin with a 16K
context. Raise context only after measuring startup and generation under load.

## Recommended models

These are ranked for SGLang on one 8 GiB NVIDIA card, not for the 96 GiB MLX node.
Repository sizes were checked against Hugging Face on 2026-09-07.

| Rank | Model | Weight files | Best use | Tradeoff |
|---:|---|---:|---|---|
| 1 | `cyankiwi/Qwen3.5-4B-AWQ-4bit` | 3.76 GiB | Best overall: reasoning, coding, tools, multilingual, and optional vision | Community quantization; validate quality and the exact SGLang image before promoting |
| 2 | `Qwen/Qwen3-8B-AWQ` | 5.69 GiB | Strongest mature text-only choice and switchable thinking | Little KV-cache headroom; start at 8K–16K and concurrency 1 |
| 3 | `Qwen/Qwen3-4B-Instruct-2507-FP8` | 4.85 GiB | Fast, stable non-thinking extraction/chat; already used in Nephos | FP8 is a better match for newer GPUs than Ampere; no thinking mode |
| 4 | `gaunernst/gemma-3-4b-it-int4-awq` | 3.8 GiB | Alternative 4B vision-language model | Community quantization and weaker fit for Nephos tool use than Qwen |

Start evaluation with Qwen3.5 4B AWQ. Keep Qwen3 8B AWQ as the quality-oriented
text model if its smaller usable context is acceptable. Do not select a model from
parameter count alone: the available Qwen3.5 9B AWQ repositories checked here are
8.47–11.55 GiB before runtime overhead and therefore do not fit reliably.

SGLang supports Qwen3.5 and offline AWQ on NVIDIA. Offline pre-quantized models are
preferred by SGLang; do not also pass `--quantization` when the repository is
already AWQ. For Qwen thinking/tool behavior, use the matching reasoning and tool
parsers supported by the installed SGLang version.

Baseline launch shape for the first Qwen3.5 4B AWQ test:

```yaml
resources:
  memory: 8Gi
  cpu: 4
  vram: 7Gi
command:
  - python3
  - -m
  - sglang.launch_server
  - --model-path
  - cyankiwi/Qwen3.5-4B-AWQ-4bit
  - --served-model-name
  - qwen3.5-4b-awq
  - --host
  - 0.0.0.0
  - --port
  - "30000"
  - --mem-fraction-static
  - "0.80"
  - --context-length
  - "16384"
  - --reasoning-parser
  - qwen3
  - --tool-call-parser
  - qwen3_coder
```

Treat this as a benchmark starting point. Confirm that the pinned SGLang image
supports the checkpoint, then record cold-start time, idle CPU, idle VRAM, prompt
throughput, decode throughput, and quality on representative prompts before making
it a gateway tier. Qwen3.5 requires a recent SGLang build.

## `gpu1` NVIDIA recovery

Known failure signature:

- `nephos nodes` omits `cuda` and VRAM for `gpu1`.
- `lspci -nnk` still shows the RTX 3080 with `Kernel driver in use: nvidia`.
- `nvidia-smi` reports `Unable to determine the device handle ... Unknown Error`.
- The kernel journal contains `NVRM` allocation failures or a failed
  `nv_pmops_runtime_suspend`.

The 2026-09-07 incident followed a failed NVIDIA runtime suspend. A clean reboot
restored the driver, after which Nephos re-registered `gpu1` with `cuda` and
`vram:8192MB`.

Before rebooting, confirm `nephos ps` shows no services and `nephos jobs` shows no
work on the node. For an authorized repair, obtain the sudo credential without
exposing it:

```bash
vault get GPU1_SUDO_PASSWORD@gpu1-sudo \
  | ssh gpu1 "sudo -S -p '' systemctl reboot"
```

After the machine returns, verify the driver and the scheduler view:

```bash
ssh gpu1 'nvidia-smi'
nephos nodes
```

Success means `nvidia-smi` identifies the RTX 3080 and Nephos advertises the
`cuda` capability plus 8 GiB VRAM. If the laptop is operated closed, also ensure
its lid policy will not immediately suspend it after a remote reboot.

## Primary references

- [SGLang quantization support](https://docs.sglang.ai/advanced_features/quantization.html)
- [SGLang supported models](https://docs.sglang.ai/supported_models/generative_models.html)
- [Qwen3.5 4B model card](https://huggingface.co/Qwen/Qwen3.5-4B)
- [Qwen3 8B AWQ model card](https://huggingface.co/Qwen/Qwen3-8B-AWQ)
- [Qwen3 4B Instruct 2507 FP8 model card](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507-FP8)
