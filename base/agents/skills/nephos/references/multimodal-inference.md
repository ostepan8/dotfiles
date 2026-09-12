# Multimodal inference on Nephos

Use separate services or GPU-serialized jobs for each modality. SGLang is the
default for text and supported vision-language models; it is not the universal
runtime for diffusion, speech, detection, segmentation, or depth models.

This shortlist was checked against primary model cards and project documentation
on 2026-09-07. Benchmark a model on Owen's actual inputs before promoting it to a
stable tier.

## Runtime map

| Workload | Runtime | Preferred node | Scheduling shape |
|---|---|---|---|
| Text and vision-language chat | SGLang | `gpu1`, then `gpu2` | Service; one 7 GiB VRAM allocation |
| Image generation/editing | ComfyUI or Diffusers | `gpu2`; `gpu1` for quantized paths | Job by default; service only when interactive latency matters |
| Speech recognition | Qwen ASR/vLLM or faster-whisper | `gpu1` or `gpu2` | Service for streaming; job for files/batches |
| Speech synthesis | Qwen3-TTS | `gpu1` or `gpu2` | Service for streaming; job for narration batches |
| Detection, pose, segmentation, OCR, depth | PyTorch/Ultralytics/Transformers | Either 8 GiB GPU | Small services can coexist only when their measured total VRAM fits |
| Video generation | ComfyUI with quantization/offload | Dedicated GPU job | `queue: gpu`, `concurrency: 1`; expect slow runs on 8 GiB |
| Large multimodal experiments | Model-specific MLX when supported | Mac Studio | Do not assume CUDA checkpoints or ComfyUI nodes work under MLX |

For GPU jobs, declare `queue: gpu` and `concurrency: 1`. For services, declare the
measured VRAM requirement so Nephos cannot co-place incompatible workloads. Stop
or idle-unload large interactive models when unused.

## Image generation and editing

### First choice: FLUX.2 Klein 4B, quantized

`black-forest-labs/FLUX.2-klein-4B` is the strongest compact generation/editing
family to evaluate. The official full pipeline needs about 13 GiB VRAM, so it does
not fit either laptop unmodified. On 8 GiB use ComfyUI with CPU offload and a
quantized transformer such as the `unsloth/FLUX.2-klein-4B-GGUF` Q4_K_M artifact
(2.43 GiB for the transformer). Text encoders, VAE, activations, and working memory
still count; the GGUF file size is not total VRAM use.

- Use `gpu2` first because Ada is a better inference target than Ampere.
- Use `gpu1` with GGUF/AWQ-style weight reduction, not as the primary FP8 target.
- Start at 1024 px, batch size 1, four-step distilled inference, and CPU offload.
- Treat `black-forest-labs/FLUX.2-klein-4b-fp8` as a `gpu2`/`fedora` experiment;
  Ampere lacks native FP8 tensor cores.

### Fast fallback: SDXL Lightning

`ByteDance/SDXL-Lightning` is the mature low-step fallback when predictable 8 GiB
operation and broad ComfyUI support matter more than peak image quality. Use the
2-step or 4-step checkpoint with batch size 1. It is also a useful control model
when diagnosing a FLUX workflow.

Do not run image diffusion inside the SGLang service. Package the ComfyUI workflow
or Diffusers script as its own Nephos job so VRAM is released on completion.

## Vision-language understanding

Use `cyankiwi/Qwen3.5-4B-AWQ-4bit` as the default combined text-and-image model.
It fits the same general SGLang lane described in `gpu-inference.md`, supports
reasoning and tool use, and avoids maintaining a second chat model solely for
images. `cyankiwi/Qwen3-VL-4B-Instruct-AWQ-4bit` is the conservative alternative
when Qwen3.5 support in the pinned SGLang image is not ready.

Vision-language models answer questions about images; they do not replace
pixel-accurate detection, segmentation, OCR, or depth pipelines.

## Speech and audio

### Speech recognition

- **Best quality:** `Qwen/Qwen3-ASR-1.7B`. It supports streaming and offline ASR,
  language identification, long audio, 30 languages, and 22 Chinese dialects.
  Use its supported vLLM/Qwen ASR server rather than SGLang.
- **Fast, proven fallback:** `dropbox-dash/faster-whisper-large-v3-turbo` through
  faster-whisper/CTranslate2. The repository is about 1.5 GiB and is the safer
  choice for high-throughput transcription, subtitles, and Whisper-compatible
  timestamp workflows.
- **Tiny/high-concurrency:** `Qwen/Qwen3-ASR-0.6B` when throughput matters more
  than the 1.7B model's accuracy.

### Speech synthesis

Qwen3-TTS is the default family:

| Need | Model |
|---|---|
| Voice cloning from a short reference | `Qwen/Qwen3-TTS-12Hz-1.7B-Base` |
| Built-in voices with instruction/style control | `Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice` |
| Design a voice from a description | `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign` |
| Lower latency/memory | corresponding 0.6B model |

The 1.7B CustomVoice repository is about 4.2 GiB and fits an 8 GiB card when run
alone. Qwen reports streaming first-packet latency as low as 97 ms, but verify
end-to-end latency through the Nephos service. Use the Base model only with audio
the user is authorized to clone.

For general audio understanding, build a pipeline of ASR → language model → TTS.
The available Qwen3-Omni 30B-A3B quantizations are too large for a single 8 GiB
card, so an all-in-one speech model is not the practical default here.

## Computer vision

These models are small enough that compute and input resolution usually matter
more than weight storage:

| Task | Default | Notes |
|---|---|---|
| Object detection | Ultralytics YOLO26 | Choose n/s/m/l/x by measured latency and accuracy; export TensorRT for a stable NVIDIA service |
| Pose estimation | YOLO26 Pose | Same serving path as detection; useful for real-time feeds |
| Prompted image/video segmentation | `facebook/sam2.1-hiera-large` | About 1.7 GiB repository; keep per-video state bounded |
| Captioning, OCR, grounding, region tasks | `microsoft/Florence-2-large` | About 2.9 GiB repository; strong general CV utility model |
| Monocular depth | `depth-anything/Depth-Anything-V2-Large` | About 1.25 GiB repository; use metric variants when absolute indoor/outdoor depth matters |

Prefer a small focused model over a VLM when the output must be coordinates,
masks, keypoints, or depth. Validate external images at the API boundary, cap
resolution and batch size, and return structured results rather than model-native
objects.

## Video generation

Video is possible but not a good always-on 8 GiB service. Start with a quantized
`Wan2.2-TI2V-5B` GGUF workflow in ComfyUI, CPU offload, short clips, low resolution,
and a single durable Nephos job. Expect generation to be slow and RAM-heavy.

Do not promise interactive video generation on these laptops. Prefer the Mac
Studio only when the selected workflow has a verified MLX or Apple-compatible
runtime; unified memory capacity alone does not make CUDA workflows portable.

## Evaluation order

1. Confirm the runtime starts with the exact pinned container image.
2. Record model download size, cold-start time, idle VRAM/RAM/CPU, and peak VRAM.
3. Test representative quality cases, including malformed and oversized inputs.
4. Measure throughput and latency at the intended concurrency.
5. Add the measured resource request to the manifest.
6. Promote to a long-running service only if interactive use justifies resident
   memory; otherwise keep it as a run-to-completion job.

## Primary references

- [FLUX.2 Klein 4B](https://huggingface.co/black-forest-labs/FLUX.2-klein-4B)
- [SDXL Lightning](https://huggingface.co/ByteDance/SDXL-Lightning)
- [Qwen3 ASR](https://huggingface.co/Qwen/Qwen3-ASR-1.7B)
- [Qwen3 TTS](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice)
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- [SAM 2](https://github.com/facebookresearch/sam2)
- [Florence 2](https://huggingface.co/microsoft/Florence-2-large)
- [Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2)
- [Ultralytics models](https://docs.ultralytics.com/models/)
- [Wan 2.2](https://github.com/Wan-Video/Wan2.2)
