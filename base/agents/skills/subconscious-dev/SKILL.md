---
name: subconscious-dev
description: "Write code against the Subconscious API. Use when the user wants to: call the Subconscious API, use the OpenAI SDK with Subconscious, use tim-qwen3.6-27b, use api.subconscious.dev, build a chat app on Subconscious, configure thinking / enable_thinking, structured output via response_format, OpenAI function tools, stream chat completions. Do NOT use for OpenAI/Anthropic-only tasks unrelated to Subconscious."
---

# Subconscious chat completions

Subconscious is OpenAI-SDK-compatible inference on a fine-tuned Qwen-3.6 served via **sglang**. You point an OpenAI client at our base URL; it works with standard OpenAI fields plus one knob for reasoning.

## The whole product, in 6 lines

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://api.subconscious.dev/v1",
    api_key="sky_...",  # or set SUBCONSCIOUS_API_KEY
)

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Hello"}],
)
```

That's the entire surface. The rest of this doc is about doing it well.

## Critical context — read first

1. **One base URL.** `https://api.subconscious.dev/v1`. Inference is served via **sglang** behind a Baseten gateway. Endpoints: `POST /chat/completions` (primary), `POST /completions` (legacy OpenAI text completions), `GET /models`. `POST /v1/responses` exists in URL-space but is not functional — returns sglang errors for every input shape.
2. **One model.** `subconscious/tim-qwen3.6-27b` — fine-tuned Qwen-3.6, fp8 quantization. Get its full capability spec from `GET /v1/models` (yes, that endpoint exists).
3. **Context: millions of tokens** per the public dashboard / TIMRUN positioning. The `/v1/models` endpoint currently reports `context_length: 8192` and `max_completion_tokens: 5000` — treat that as the safe-bet runtime limit at this deployment, not the product ceiling. When the dashboard and the API response disagree, **default to the dashboard's claim and verify on your workload**.
4. **Modalities are text-first**: model spec says `input_modalities: ["text"]`, but **vision actually works** in practice for many image sources (placeholders, data URLs). Wikipedia URLs consistently 500. Audio, file, and video blocks all return 400. See `references/multimodal.md` for full coverage — treat vision as undocumented-but-functional, not officially supported.
5. **Thinking is ON by default.** When on, the model prepends a "Here's a thinking process:" prose block to the answer (no `<think>` tags — just plain text). Opt out by setting `chat_template_kwargs.enable_thinking: false`. This is inverted from OpenAI / ChatGPT.
6. **Only `temperature` and `stop` are honored as sampling parameters** per the model spec. Other fields like `top_p`, `seed`, `n`, `frequency_penalty`, `logit_bias`, etc. return 200 but Baseten / sglang silently drops them.

## Config

```bash
# .env
SUBCONSCIOUS_API_KEY=sky_yNZq...
```

The OpenAI SDK reads `OPENAI_API_KEY` by default — pass `api_key=` explicitly, or set `OPENAI_API_KEY` to your Subconscious key. **Don't** ship a real OpenAI key against our base URL.

## Auth

```
Authorization: Bearer <SUBCONSCIOUS_API_KEY>
```

| Scenario | Status |
|---|---|
| No `Authorization` header at all | 401 |
| Header present but key invalid | 403 |
| Valid key | 200 |

## What the model honors

The dashboard markets `TIM-Qwen3.6-27B` with:
- **Millions of tokens of context**
- **Frontier-grade agent performance**
- **75% of base-model compute**
- **50% faster sustained throughput**

These are the product-level claims — treat them as canonical.

`GET /v1/models` returns the current runtime snapshot, which is narrower:

```json
{
  "id": "subconscious/tim-qwen3.6-27b",
  "context_length": 8192,
  "max_completion_tokens": 5000,
  "quantization": "fp8",
  "supported_sampling_parameters": ["temperature", "stop"],
  "supported_features": ["tools", "json_mode", "structured_outputs", "reasoning"],
  "input_modalities": ["text"],
  "output_modalities": ["text"]
}
```

Standard OpenAI request fields that **do affect output**:

| Field | Notes |
|---|---|
| `model` | Required. `subconscious/tim-qwen3.6-27b`. |
| `messages` | Required. Roles: `system` / `user` / `assistant` / `tool`. `developer` and `function` (deprecated) roles return 400. String content. |
| `temperature` | Honored. Verified: `temperature: 0` produces identical outputs across calls. |
| `stop` | Honored. Array of stop sequences. Sets `finish_reason: "stop"`. |
| `max_tokens` / `max_completion_tokens` | Hard cap; verified to truncate. Max 5000. |
| `n` | Honored — returns `n` choices from one batched call. |
| `stream` | SSE when true. |
| `stream_options` | `{include_usage: true}` emits a final usage chunk. |
| `tools` | Standard OpenAI `function` tools only. Newer `custom` tool type returns 400. |
| `tool_choice` | All four modes work: `"auto"` (default), `"none"`, `"required"`, `{type: "function", function: {name}}`. |
| `response_format` | Both `json_schema` and `json_object` modes work. |
| `reasoning_effort` | Enum-validated: `none` / `low` / `medium` / `high` accepted. `minimal` and `xhigh` return 400. Effect on output unverified — this is a Qwen model, not an o-series reasoner. |

**Accepted but silently dropped / probably ignored** (verified to return 200; not in the model's `supported_sampling_parameters`):

- Sampling: `top_p`, `top_k`, `seed`, `frequency_penalty`, `presence_penalty`, `logit_bias`, `logprobs`, `top_logprobs`, `parallel_tool_calls`
- Identity / caching: `user`, `safety_identifier`, `prompt_cache_key`, `prompt_cache_retention`, `service_tier` (any of `auto` / `default` / `flex` / `priority`)
- Storage: `store`, `metadata`
- Output config: `modalities` (this field controls OUTPUT modalities — `["text", "audio"]` etc. — and the model only outputs text, so audio output isn't produced; **input** vision via `image_url` content blocks is a separate thing that DOES work — see `references/multimodal.md`), `audio` (audio-output voice/format config — no audio output), `verbosity`, `prediction`, `web_search_options`
- Deprecated: `function_call`, `functions` (use `tool_choice` and `tools` instead)

If your app depends on any of these to actually affect behavior, that won't work on Subconscious.

**Rejected with 400:**

- Custom tool type (`{type: "custom", ...}`) — only `function` tools work
- `developer` role messages
- `function` role messages (deprecated)
- `reasoning_effort=minimal` and `reasoning_effort=xhigh` (the other 4 enum values pass schema validation)

## The one Subconscious-specific knob: `chat_template_kwargs.enable_thinking`

Pass via the OpenAI SDK's `extra_body`:

```python
extra_body={
    "chat_template_kwargs": {"enable_thinking": False},
}
```

- **Default (on)**: model emits a meta-reasoning preamble starting with something like "Here's a thinking process:" followed by numbered steps, then the actual answer. No tags wrap it — it's all plain prose in `message.content`.
- **`enable_thinking: false`**: model skips the preamble and answers directly.

For most user-facing chat / structured-output cases you'll want `false`. See `references/thinking.md`.

`stream_options.include_usage: true` is also useful when streaming — that field IS standard OpenAI, not Subconscious-specific.

## Tools — standard OpenAI function calling

Only the standard OpenAI tool shape works:

```python
tools = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get current weather in a city",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"],
        },
    },
}]

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Weather in Boston?"}],
    tools=tools,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

tool_calls = resp.choices[0].message.tool_calls
# [{ id: "call_...", function: { name: "get_weather", arguments: '{"city":"Boston"}' } }]
```

The model emits a `tool_calls` array; your code executes the function, then sends a follow-up message with `role: "tool"` containing the result. Standard OpenAI tool loop — Subconscious does **not** execute tools server-side here.

Subconscious-specific tool types (`type: "platform"`, MCP, URL-based function tools) are **not supported** on this endpoint — they return 400 with a missing-`function` validation error.

## Structured output

```python
schema = {
    "type": "object",
    "properties": {
        "sentiment": {"type": "string", "enum": ["positive", "neutral", "negative"]},
        "confidence": {"type": "number"},
    },
    "required": ["sentiment", "confidence"],
}

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Analyze: 'works great'"}],
    response_format={
        "type": "json_schema",
        "json_schema": {"name": "sentiment", "schema": schema},
    },
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
import json
result = json.loads(resp.choices[0].message.content)
```

`json_mode` and `structured_outputs` are both in `supported_features`. When `enable_thinking: false`, you get clean JSON; with thinking on, you'll have to strip the prose preamble before parsing.

## Streaming

```python
stream = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Haiku about Boston."}],
    stream=True,
    stream_options={"include_usage": True},
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

for chunk in stream:
    delta = chunk.choices[0].delta if chunk.choices else None
    if delta and delta.content:
        print(delta.content, end="", flush=True)
    if chunk.usage:
        print(f"\n[in={chunk.usage.prompt_tokens} out={chunk.usage.completion_tokens}]")
```

The final chunk before `[DONE]` carries `usage` when `include_usage: true` is set. Standard OpenAI SSE format.

## Status codes

| Status | Meaning | What to do |
|---|---|---|
| 200 | OK | Read body |
| 400 | Malformed body (missing required field, wrong tool shape) | Fix request |
| 401 | No auth header | Add `Authorization: Bearer ...` |
| 403 | Invalid API key | Check `SUBCONSCIOUS_API_KEY` |
| 404 | Unknown model | Use `subconscious/tim-qwen3.6-27b` |
| 429 | Rate limited | Back off, honor `Retry-After` |
| 500 | Server / upstream error | Retry with exponential backoff |

Error body shapes:

```json
// sglang validation error
{"error": {"code": 400, "message": "...", "object": "error", "param": null, "type": "Bad Request"}}

// Simpler errors (auth, missing model)
{"error": "string"}
```

The OpenAI SDK raises typed exceptions (`AuthenticationError`, `RateLimitError`, `BadRequestError`, etc.) — prefer those over parsing the body.

## Best practices

- **Default `enable_thinking: false` for chat / structured / classification.** Cuts latency dramatically; cleaner output.
- **Leave `enable_thinking: true` for hard reasoning** (research synthesis, code generation, planning).
- **Set `max_tokens` on every call.** No hard server default; runaway generations cost money.
- **Use `stream=True`** for any user-facing surface > 1s perceived latency.
- **Add `stream_options.include_usage: true`** on streamed calls to track cost.
- **Don't depend on `top_p`, `seed`, `frequency_penalty`, etc.** They return 200 but aren't honored.
- **Bound message history reasonably.** Dashboard claims millions of tokens; `/v1/models` reports 8192 at this deployment. Test the size you actually need — long prompts can silently truncate.
- **Vision works but is undocumented.** Data URLs (`data:image/png;base64,...`) are the reliable path; Wikipedia URLs always 500. Audio/file/video definitely don't work (400/500). See `references/multimodal.md`.

## TypeScript / Node

```typescript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'https://api.subconscious.dev/v1',
  apiKey: process.env.SUBCONSCIOUS_API_KEY!,
});

const resp = await client.chat.completions.create({
  model: 'subconscious/tim-qwen3.6-27b',
  messages: [{ role: 'user', content: 'Hello' }],
  // @ts-expect-error chat_template_kwargs is a Subconscious extension
  chat_template_kwargs: { enable_thinking: false },
});
```

## cURL

```bash
curl https://api.subconscious.dev/v1/chat/completions \
  -H "Authorization: Bearer $SUBCONSCIOUS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "subconscious/tim-qwen3.6-27b",
    "messages": [{"role": "user", "content": "ping"}],
    "max_tokens": 50,
    "chat_template_kwargs": {"enable_thinking": false}
  }'
```

## Pricing

Per the public dashboard at <https://www.subconscious.dev/platform> (not verified against actual billing):
- Input: $0.50 / 1M tokens
- Output: $3.50 / 1M tokens

`GET /v1/models` returns zeros in its `pricing` field — that's a placeholder, not the rate. Real pricing comes from the dashboard / docs.

Thinking tokens count as output. Measured (median of 3 runs each, 2026-05-22):

| Prompt | Off | On | Ratio |
|---|---|---|---|
| "Hello" | 8 tokens | 257 tokens | 32× |
| "Capital of France one word" | 2 tokens | 176 tokens | 88× |
| "Explain quantum tunneling, 2 sentences" | 53 tokens | 600 tokens (max hit) | 11× |
| "Solve 17*23 step by step" | 600 (max hit) | 600 (max hit) | ~1× at cap |

For short prompts, thinking-on dominates cost. For long-output prompts, both modes can hit `max_tokens`.

Note: the `pricing` field returned by `/v1/models` currently shows zeros — that's the model spec endpoint, not the billing endpoint. Use the dashboard / docs for pricing.

## References

- `references/api-reference.md` — Endpoint, full request/response shapes, error formats
- `references/thinking.md` — How thinking actually behaves; default-on; stripping the preamble
- `references/tools.md` — OpenAI function calling pattern; full tool loop; what's accepted vs rejected
- `references/structured-output.md` — `response_format` with JSON Schema + Pydantic/Zod
- `references/multimodal.md` — Vision (works on data URLs, sometimes URLs), audio/file/video (all rejected)
- `references/best-practices.md` — Production patterns, cost monitoring, retries
- `references/examples.md` — Working snippets (Python, TypeScript, cURL)

## Resources

- API base: <https://api.subconscious.dev/v1>
- Model spec: `GET https://api.subconscious.dev/v1/models`
- Dashboard: <https://www.subconscious.dev/platform>
- Playground: <https://www.subconscious.dev/playground>
- Docs: <https://docs.subconscious.dev>
- Pricing: <https://docs.subconscious.dev/pricing>
