# API reference

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/chat/completions` | Standard OpenAI chat completions (primary endpoint) |
| `POST` | `/completions` | Legacy OpenAI text completions — works with the same model |
| `POST` | `/responses` | OpenAI Responses API — endpoint exists but is **not functional** (returns sglang `input_ids should be a list of lists` errors for every input shape) |
| `GET` | `/models` | Model spec + capability metadata |

Base URL: `https://api.subconscious.dev/v1`

Backend: **sglang** served behind a Baseten gateway (error stack traces reveal `sglang.srt.entrypoints.http_server`).

## Authentication

```
Authorization: Bearer <SUBCONSCIOUS_API_KEY>
```

| Scenario | Status | Body |
|---|---|---|
| No header | 401 | `{"error": "please check the api-key you provided"}` |
| Invalid key | 403 | `{"error": "please check the api-key you provided"}` |
| Valid key | 200 | (chat completion) |

## `GET /v1/models`

Returns the runtime model snapshot — useful as one data point, but **not the only source of truth**. When the values here disagree with the public dashboard at <https://www.subconscious.dev/platform>, default to the dashboard.

Concrete current disagreements:
- Dashboard markets "millions of tokens of context"; this endpoint reports `context_length: 8192`
- Dashboard / docs publish $0.50 / $3.50 per 1M token pricing; this endpoint's `pricing` field is all zeros

The endpoint reflects what the current deployment limits are at this moment in time; the dashboard reflects the product's documented capabilities. Use both: dashboard for what to promise, endpoint snapshot for what to defensively code against.

```bash
curl https://api.subconscious.dev/v1/models \
  -H "Authorization: Bearer $SUBCONSCIOUS_API_KEY"
```

Current response (as of 2026-05-22):

```json
{
  "data": [{
    "id": "subconscious/tim-qwen3.6-27b",
    "created": 1778513741,
    "object": "model",
    "owned_by": "subconscious",
    "name": "Subconscious Qwen 3.6",
    "description": "Subconscious fine tuned Qwen",
    "context_length": 8192,
    "max_completion_tokens": 5000,
    "quantization": "fp8",
    "pricing": {"prompt": "0", "completion": "0", "image": "0", "request": "0"},
    "supported_sampling_parameters": ["temperature", "stop"],
    "supported_features": ["tools", "json_mode", "structured_outputs", "reasoning"],
    "input_modalities": ["text"],
    "output_modalities": ["text"]
  }]
}
```

Key facts to internalize:

- **Context window**: 8192 tokens total (prompt + completion)
- **Max output**: 5000 tokens (`max_completion_tokens` cap)
- **Quantization**: fp8
- **Sampling params honored**: only `temperature` and `stop`
- **Modalities**: text in, text out
- **Features**: tools, json_mode, structured_outputs, reasoning

The `pricing` field is zeros here — that's a placeholder in the model spec, not the actual billing. Real pricing lives on the docs / dashboard.

## `POST /v1/chat/completions`

Standard OpenAI chat completions request, with a few caveats specific to this model.

### Request — fields that affect output

```ts
{
  model: string,                           // required — "subconscious/tim-qwen3.6-27b"
  messages: Message[],                     // required, min 1
  temperature?: number,                    // honored
  stop?: string | string[],                // honored
  max_tokens?: number,                     // honored, cap 5000
  max_completion_tokens?: number,          // honored (OpenAI rename), cap 5000
  stream?: boolean,                        // SSE when true
  stream_options?: { include_usage?: boolean },
  n?: number,                              // honored — returns n choices (1-128 per OpenAI)
  tools?: Tool[],                          // standard OpenAI function shape only
  tool_choice?: "auto" | "none" | "required" | { type: "function", function: { name: string } },
  response_format?: JSONSchema,            // json_mode / structured_outputs
  reasoning_effort?: "none" | "low" | "medium" | "high",  // enum-validated; effect unverified
}
```

### Request — fields accepted (return 200) but probably silently ignored

These are valid OpenAI Chat Completions parameters that Subconscious's gateway accepts (no 400) but aren't in the model's `supported_sampling_parameters` and almost certainly don't affect behavior.

**Sampling knobs:**
- `top_p`, `top_k`
- `seed` (verified NOT to make output reproducible)
- `frequency_penalty`, `presence_penalty`
- `logit_bias`
- `logprobs`, `top_logprobs`
- `parallel_tool_calls`

**Identity / caching (OpenAI platform features):**
- `user` (deprecated by OpenAI)
- `safety_identifier`
- `prompt_cache_key`
- `prompt_cache_retention`
- `service_tier` — `auto`, `default`, `flex`, `priority` all return 200

**Storage / observability (OpenAI platform features):**
- `store`
- `metadata`

**OpenAI-only feature configs:**
- `verbosity` (`low` / `medium` / `high`)
- `modalities` — but the model is text-only per `/v1/models`
- `audio` (output voice/format) — no audio output capability
- `prediction` (predicted outputs)
- `web_search_options` — no built-in web search on this model

**Deprecated OpenAI fields:**
- `function_call` (use `tool_choice`)
- `functions` (use `tools`)

Unknown / made-up keys are also accepted (no 400) and silently ignored.

If your app depends on any of these to change behavior, it won't work — measure on your workload first.

### Request — fields with strict enum validation

A few fields ARE validated against an enum (return 400 on bad values):

- `reasoning_effort` accepts: `none`, `low`, `medium`, `high`. `minimal` and `xhigh` return 400. Whether the accepted values change model behavior is unverified — this is a Qwen model, not an o-series reasoner.

### Request — fields that return 400

- Custom tool type (`{type: "custom", custom: {...}}`) — only `{type: "function", function: {...}}` works
- `developer` role messages — "Unexpected message role"
- `function` role messages (deprecated) — "Unexpected message role"

### Subconscious extension via `extra_body`

```ts
chat_template_kwargs?: { enable_thinking?: boolean }   // default: true
```

The one knob not in OpenAI's API. See `thinking.md`.

### Message shape

```ts
type Message = {
  role: "system" | "user" | "assistant" | "tool",
  content: string,                         // string only — see modalities note
  tool_call_id?: string,                   // when role === "tool"
  name?: string,                           // optional
  tool_calls?: ToolCall[],                 // on assistant messages from prior turns
}

type ToolCall = {
  id: string,
  type: "function",
  function: { name: string, arguments: string },   // arguments is JSON-encoded
}
```

**Note on multimodal content blocks**: the model's `input_modalities` is `["text"]`. The endpoint's schema accepts array `content` with `image_url` / `input_audio` / `file` blocks (sglang validates the shape), but:
- `input_audio` blocks consistently 400 (validation mismatch)
- `image_url` sometimes returns 200 with a description, but is not officially supported and 500s on many URLs
- Don't ship multimodal on this model

### Tool shape — OpenAI standard only

```ts
type Tool = {
  type: "function",
  function: {
    name: string,
    description: string,
    parameters: object,                    // JSON Schema
  },
}
```

The legacy Subconscious tool types (`{type: "platform", id: "..."}`, URL-based function tools, MCP tools) all return 400 here with a missing-`function` validation error. They're a Run-API concept, not chat-completions.

### Response — non-streaming

```ts
{
  id: string,
  object: "chat.completion",
  created: number,
  model: "subconscious/tim-qwen3.6-27b",
  choices: [{
    index: 0,
    message: {
      role: "assistant",
      content: string,                     // may be prefixed with thinking prose
      reasoning_content: null,             // always null currently
      tool_calls: ToolCall[] | null,
    },
    logprobs: null,
    finish_reason: "stop" | "length" | "tool_calls",
  }],
  usage: {
    prompt_tokens: number,
    completion_tokens: number,
    total_tokens: number,
    prompt_tokens_details: null,
    reasoning_tokens: 0,                   // always 0 currently
  }
}
```

`reasoning_content` and `reasoning_tokens` exist in the response shape but are not populated — the model emits thinking inline in `content` instead. See `thinking.md`.

### Response — streaming

`stream: true` → SSE:

```
data: {"id":"...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant"}}]}
data: {"id":"...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hi"}}]}
...
data: {"id":"...","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
data: [DONE]
```

If `stream_options.include_usage: true`, the chunk before `[DONE]` carries `usage`:

```
data: {"id":"...","object":"chat.completion.chunk","choices":[],"usage":{"prompt_tokens":13,"completion_tokens":29,"total_tokens":42}}
data: [DONE]
```

## `POST /v1/completions` (legacy text completions)

OpenAI's older text-completion endpoint works. All findings here are verified empirically (2026-05-22).

```bash
curl https://api.subconscious.dev/v1/completions \
  -H "Authorization: Bearer $SUBCONSCIOUS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "subconscious/tim-qwen3.6-27b",
    "prompt": "The capital of France is",
    "max_tokens": 20
  }'
```

### Required fields

`model`, `prompt`. (Empty string prompt returns 400 with `"Prompt cannot be empty"`.)

### `prompt` accepts

| Form | Verified |
|---|---|
| Single string | ✓ |
| Array of strings (batch) | ✓ returns one choice per prompt |
| Array of token IDs | ✓ accepted |

### Accepted standard OpenAI params (all return 200)

`temperature`, `top_p`, `seed`, `stop`, `n`, `frequency_penalty`, `presence_penalty`, `logit_bias`, `logprobs` (int 0-5), `echo`, `best_of`, `suffix`, `user`, `stream`, `stream_options`, `max_tokens`.

### Verified to actually affect output

- `temperature: 0` → deterministic (identical responses)
- `n: 3` → 3 choices returned
- `max_tokens: 5` → output capped to 5 tokens
- `stop: ["5"]` → truncates at sequence, `finish_reason: "stop"`
- `echo: true` → prepends prompt to `text`
- `prompt: ["a", "b"]` → 2 choices, one per prompt

### Response shape

```json
{
  "id": "...",
  "object": "text_completion",
  "created": 1779472182,
  "model": "subconscious/tim-qwen3.6-27b",
  "choices": [{
    "index": 0,
    "text": " Paris...",
    "logprobs": null,
    "finish_reason": "length",
    "matched_stop": null
  }],
  "usage": {
    "prompt_tokens": 5,
    "completion_tokens": 20,
    "total_tokens": 25,
    "prompt_tokens_details": null,
    "reasoning_tokens": 0
  },
  "metadata": { "weight_version": "default" }
}
```

Includes a `metadata.weight_version` field not in OpenAI's spec — a Baseten/sglang detail. The `choice` also includes `matched_stop` (which stop sequence matched, when applicable).

### Streaming

`stream: true` returns SSE with `data:` lines and a final `data: [DONE]`. `stream_options.include_usage: true` adds a usage chunk before `[DONE]`. Verified.

### Thinking behavior is different here — DON'T rely on `chat_template_kwargs.enable_thinking`

On `/v1/chat/completions`, thinking is on by default and `enable_thinking: false` cleanly suppresses it.

On `/v1/completions`, behavior is **inverted and unstable** — the chat template doesn't apply naturally to raw prompts. Empirically:

- Default → emits an empty `<think>\n\n</think>` block then a clean answer (effectively thinking OFF)
- `chat_template_kwargs: {enable_thinking: false}` → opens a `<think>` block with full reasoning content (effectively thinking ON)

Don't depend on the thinking toggle here. If you need a clean response, the default behavior on legacy completions already produces clean output for most prompts.

### Errors

- Missing `model` → 400
- Missing `prompt` → 400
- Empty `prompt` (`""`) → 400 (`"Prompt cannot be empty"`)
- Unknown `model` → 404

### When to use vs `/chat/completions`

Prefer `/chat/completions` for new code — it supports tools, structured output, and predictable thinking behavior. Use `/completions` when:
- You have an existing legacy prompt-completion pipeline to port
- You want `echo` to prepend the prompt
- You want native batch behavior (`prompt: [...]`)
- You don't need messages structure

## Status codes

| Status | Meaning | Action |
|---|---|---|
| 200 | OK | Read body |
| 400 | Malformed body — missing `messages`/`model`, wrong tool shape | Fix request |
| 401 | No `Authorization` header | Add header |
| 403 | Invalid API key | Check `SUBCONSCIOUS_API_KEY` |
| 404 | Unknown model | Use `subconscious/tim-qwen3.6-27b` |
| 413 | Body too large | Reduce payload |
| 429 | Rate limited | Honor `Retry-After`, back off |
| 500 | Server / upstream error | Retry with exponential backoff |

Note: extra/unknown OpenAI parameters do **not** trigger 400.

## Error formats

Two shapes show up depending on the validator:

```json
// sglang structured validation error
{
  "error": {
    "code": 400,
    "message": "1 validation error:\n  {'type': 'missing', 'loc': (...), ...}",
    "object": "error",
    "param": null,
    "type": "Bad Request"
  }
}

// Simpler gateway error (auth, missing model field, etc.)
{ "error": "string" }
```

The OpenAI SDK raises typed exceptions for the standard cases (`AuthenticationError`, `RateLimitError`, `BadRequestError`, etc.). Prefer those over parsing.

## Rate limits

Org-scoped, per plan. 429 responses include `Retry-After` where applicable.

## Pricing

Per the public dashboard at <https://www.subconscious.dev/platform> — the `/v1/models` `pricing` field returns zeros (placeholder, not the real rate):

- Input: $0.50 per 1M tokens
- Output: $3.50 per 1M tokens

These figures are externally documented and not independently billing-verified. Thinking tokens count as output. Track via `usage.prompt_tokens` + `usage.completion_tokens` on the response, or the final chunk when streaming with `include_usage: true`.
