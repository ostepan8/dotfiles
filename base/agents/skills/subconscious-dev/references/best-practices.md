# Best practices

Production patterns for `https://api.subconscious.dev/v1` + `subconscious/tim-qwen3.6-27b`. Most of this is verified against the live API.

## Config

### API key handling

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://api.subconscious.dev/v1",
    api_key=os.environ["SUBCONSCIOUS_API_KEY"],
)
```

- Never hardcode keys
- Mint per-service keys at the dashboard so you can rotate independently
- Don't expose `SUBCONSCIOUS_API_KEY` to client-side code — proxy through your backend
- Rotate via dashboard (delete + recreate) if a key leaks

If your codebase also calls OpenAI, **pass `api_key=` explicitly** rather than relying on `OPENAI_API_KEY` — a stray env var will silently override and you'll get 403 against our endpoint.

### Base URL handling

Make it config:

```python
SUBCONSCIOUS_BASE_URL = os.environ.get(
    "SUBCONSCIOUS_BASE_URL",
    "https://api.subconscious.dev/v1",
)
```

### Timeouts

The OpenAI SDK default (10 min) is fine for thinking-on calls but too generous for interactive surfaces. Pick deliberately:

```python
client = OpenAI(
    base_url="https://api.subconscious.dev/v1",
    api_key=os.environ["SUBCONSCIOUS_API_KEY"],
    timeout=30.0,           # for non-thinking interactive
    max_retries=2,
)
```

Thinking-on calls can legitimately take 30–60s; bump the timeout for those code paths.

## Thinking by default

- **Default `enable_thinking: false` for interactive surfaces.** Chat, autocomplete, classification, dispatch.
- **Default `enable_thinking: true` for hard reasoning.** Code generation, multi-step planning, research synthesis.
- **Per-route decision**, not a global. Different endpoints have different needs.
- For **structured output** (JSON Schema), almost always set thinking off — the preamble prose makes parsing unreliable.

## Cost monitoring

```python
def log_usage(resp, *, route: str):
    u = resp.usage
    # $0.50 / 1M input, $3.50 / 1M output
    cost_micros = u.prompt_tokens * 50 + u.completion_tokens * 350
    logger.info("subconscious.call", extra={
        "route": route,
        "input_tokens": u.prompt_tokens,
        "output_tokens": u.completion_tokens,
        "cost_micros": cost_micros,
    })
```

- Tag every call site for per-route attribution
- Track p50 / p99 output tokens — long tails indicate runaway generations
- Watch for `enable_thinking: true` calls that don't need it — measured at ~**2.5× more completion tokens** for the same prompt (Explain entropy: 883 tokens with thinking on vs 357 without)
- Stream with `stream_options.include_usage: true` to capture usage even on streamed calls

## Sampling parameters

Per `GET /v1/models`, `supported_sampling_parameters` is `["temperature", "stop"]`. But `n` (multiple completions) is honored too despite not being in that list — verified.

Verified empirically (2026-05-22):
- `temperature: 0` → identical outputs across calls ✓ deterministic
- `temperature: 1.5` → varied outputs ✓ honored
- `stop: ["X"]` → `finish_reason: "stop"`, output truncated ✓ honored
- `n: 3` → 3 distinct choices in one batched response ✓ honored
- `seed: 42` with same temp → different outputs across calls ✗ **seed is NOT honored**
- `top_p`, `frequency_penalty`, `presence_penalty`, `logit_bias`, `logprobs`, `top_logprobs`, `parallel_tool_calls` → return 200, no observable effect

OpenAI platform features (`store`, `metadata`, `safety_identifier`, `prompt_cache_key`, `service_tier`, etc.) all return 200 but Subconscious doesn't implement them.

If you need determinism: rely on `temperature: 0` and consistent prompts. There is **no seed mechanism** for reproducible output above temperature 0.

## Context window

Two numbers in tension — **default to the dashboard, test against your workload**:

- **Dashboard / product claim**: millions of tokens of context (TIMRUN positioning)
- **`/v1/models` snapshot**: `context_length: 8192`, `max_completion_tokens: 5000` (current deployment limits)

Practical strategies until you've stress-tested your scale:
- Bound message history (sliding window of last N turns)
- Summarize older context into a system message
- Estimate tokens before sending (`tiktoken` for Qwen tokenization is approximate but usable)
- Watch for silent truncation on long prompts

## Latency budgets

Measured medians from `~/Desktop/subconscious-testing/test_latency.py` (2026-05-22, 3 runs per scenario):

| Prompt class | Mode | First token | Total |
|---|---|---|---|
| Short ("Hello", "Capital of France one word") | off | 360–740ms | 0.4–0.8s |
| Short | on | 320–360ms | 4–6s |
| Medium ("Explain quantum tunneling in 2 sentences") | off | 380ms | 1.4s |
| Medium | on | 340ms | 12.8s (hit `max_tokens=600`) |
| Reasoning ("Solve 17 * 23 step by step") | off | 390ms | 12.8s (hit max) |
| Reasoning | on | 330ms | 12.8s (hit max) |

Headline:
- **First-token latency is ~300–400ms regardless of thinking mode** (occasionally up to ~740ms — likely cold-start variance)
- **Total latency is driven by output length**, not just thinking
- **Reasoning prompts can run long with or without thinking** — set `max_tokens` if you need a wall-clock cap

If you're not hitting these on your workload:
- Cold start can add hundreds of ms on the first call (unverified, but consistent with one outlier sample)
- Network RTT adds 100–300ms by region (unverified for this gateway)
- Large message history slows prefill — bounded history keeps prefill predictable

## Streaming

- **Use `stream=True`** for any user-facing surface where total latency > 1s.
- **Pass `stream_options.include_usage: true`** to capture cost in the final chunk.
- For SSE in Next.js / serverless, set `Content-Type: text/event-stream`, `Cache-Control: no-cache`, watch for proxy buffering.

## Retries

Retry on:
- 429 (honor `Retry-After`)
- 500, 502, 503, 504
- Network errors / timeouts

Don't retry on:
- 400 (your request is wrong; retrying won't help)
- 401 (no auth header — fix the request)
- 403 (invalid key — fix the env var)
- 404 (wrong model name)

Use exponential backoff with jitter:

```python
import time, random
from openai import OpenAI, RateLimitError, APIStatusError

def call_with_retry(fn, *, max_attempts=5, base=1.0):
    for attempt in range(max_attempts):
        try:
            return fn()
        except RateLimitError:
            time.sleep(base * (2 ** attempt) + random.random())
        except APIStatusError as e:
            if e.status_code >= 500:
                time.sleep(base * (2 ** attempt) + random.random())
            else:
                raise
    raise RuntimeError("max retries exceeded")
```

## Prompts

The model is OpenAI-compatible but tuned differently:

- **System prompts work** — use a `system` role message at the top
- **Few-shot examples work** — alternate `user` / `assistant` turns
- **Long contexts work up to 8192** — bound by total token budget
- **Code generation works** — Qwen base is strong on code
- **With thinking on, terser prompts may work fine** — the model recovers via reasoning. Don't balloon the system prompt to compensate for missing thinking (untested in this skill — verify on your prompts).

## Modalities

Model spec says text-only (`input_modalities: ["text"]`), but **vision actually works** in practice:

- `image_url` with **data URLs** (`data:image/png;base64,...`) — most reliable path, model describes content correctly
- `image_url` with placeholder / hosted URLs — works for many sources (placehold.co, etc.)
- `image_url` with Wikipedia / wikimedia URLs — consistently **500 errors** (gateway URL-fetch failure)
- `input_audio` — **400** for all formats (wav, mp3, ogg, flac)
- `file` blocks — **400** (file_data, file_id, any MIME)
- `video` / `video_url` — **400 / 500**

Verified empirically 2026-05-22. See `references/multimodal.md` for details.

**Recommendation:** if you need single-image input, use the data-URL pattern. Treat it as undocumented-but-functional — could change. If you need real vision support, use a different provider.

## Eval before production

- Build a golden set of prompts → expected outputs
- Run on every prompt change
- Test both `enable_thinking: true` and `false` per route — pick the cheaper option if quality is acceptable
- Re-run evals when changing prompts or schemas

## Security

- **API key in env or secret manager, never in source.** Rotate on leak.
- **Proxy through your backend.** Don't ship the key to the browser.
- **Rate-limit your own routes.** Cap per-user usage to prevent abuse / runaway cost.
- **Validate inputs** before sending — cap message length, sanitize uploads.
- **Sanitize outputs** before rendering as HTML — the model produces arbitrary content.
- **Validate structured outputs** — don't trust schema-enforcement blindly; parse + re-validate.

## Don't bypass the OpenAI SDK

The SDK gives you:
- Typed exceptions (`AuthenticationError`, `RateLimitError`, `BadRequestError`, etc.)
- Automatic retry + backoff (`max_retries`)
- Streaming iterators
- `client.beta.chat.completions.parse` for Pydantic / Zod

Hand-rolling against the endpoint means reimplementing all of this. Don't, unless you specifically need to proxy through a custom gateway.

## Common pitfalls

1. **Assuming `temperature`/`seed`/`top_p` are honored.** Only `temperature` and `stop` actually affect output. The rest are accepted but silently dropped.
2. **Leaving thinking on for short chat replies.** Measured: a "Hello" reply went from 845ms (off) to 5.7s (on). For short interactive prompts, off is dramatically faster.
3. **Not setting `max_tokens`.** The model can generate 5000 tokens on a vague prompt. Cap it.
4. **Polling instead of streaming for chat UIs.** Use `stream=True`.
5. **Shipping vision or audio.** Officially text-only. Some image URLs return 200, but it's not supported.
6. **Using legacy Subconscious tool types.** `{type: "platform"}`, URL-based function tools, MCP tools all 400 here. Use standard OpenAI function tools.
7. **Not logging usage.** You won't notice cost runaway until the bill arrives.
8. **Retrying on 4xx.** 400-class errors are not retriable except 429.
9. **Sharing one key everywhere.** Per-service keys make rotation cheap.
10. **Trusting `<think>` regex parsing.** This model emits thinking as plain prose, no tags. To suppress the preamble, turn thinking off.
