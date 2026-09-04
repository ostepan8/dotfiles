# Thinking config

The single most important behavioral knob — and the one most likely to surprise OpenAI users.

## Default state

**Thinking is ON by default.** Verified empirically 2026-05-22: a default request (no `chat_template_kwargs`) produces a response whose content begins with a meta-reasoning block.

This is inverted from OpenAI / ChatGPT, where reasoning is opt-in. The Subconscious model is reasoning-first.

## What thinking actually looks like

When thinking is on, the model's `content` opens with a **plain prose preamble** — not `<think>...</think>` tags, not a separate `reasoning_content` field, just text:

```
Here's a thinking process:

1.  **Understand the User's Request:**
    - The user wants to calculate 17 * 23.
    - They specifically asked to "Show your reasoning step-by-step."

2.  **Identify the Mathematical Operation:**
    - Multiplication of two two-digit numbers: 17 × 23.

3.  **Choose a Method for Step-by-Step Calculation:**
    - I can use the standard multiplication algorithm...

[... eventually transitions into the actual answer ...]
```

Both the preamble and the answer live in `choices[0].message.content`. The response's `reasoning_content` and `reasoning_tokens` fields exist but are **always null / 0** with this model — the OpenAI structured-reasoning shape isn't used. There's no clean programmatic split.

## Controlling it

```python
extra_body={
    "chat_template_kwargs": {"enable_thinking": False},  # opt out — clean answer
}
```

```typescript
// @ts-expect-error chat_template_kwargs is a Subconscious extension
chat_template_kwargs: { enable_thinking: false },
```

Binary toggle. There's no `reasoning_effort` like the OpenAI o-series.

## When to leave it on

- Hard multi-step reasoning
- Code generation where correctness matters
- Research synthesis, structured extraction from messy inputs
- Anywhere you can tolerate longer total latency (measured 4–13s vs <1.5s off) for noticeably more output

## When to turn it off

- Interactive chat with short replies
- Classification, sentiment, entity extraction
- Structured output (JSON Schema) — you get cleaner JSON without the preamble
- Routing / dispatch decisions
- Anything sub-second-latency-sensitive
- Batch jobs where you're paying per token

For most user-facing surfaces, **`enable_thinking: false` is the right default.** The thinking-on path is for narrow code paths where you actively want the model to chew on something.

## Cost / latency impact

Thinking tokens count as output tokens, billed per dashboard pricing. Measured latency from `~/Desktop/subconscious-testing/test_latency.py` (median of 3 runs, 2026-05-22):

| Prompt | Mode | First token | Total | Output tokens |
|---|---|---|---|---|
| "Hello" | off | ~740ms | 845ms | 8 |
| "Hello" | on | ~320ms | 5.7s | 257 |
| "What's the capital of France? One word." | off | 360ms | 380ms | 2 |
| same | on | 360ms | 4.0s | 176 |
| "Explain quantum tunneling in 2 sentences." | off | 380ms | 1.4s | 53 |
| same | on | 340ms | 12.8s | 600 (hit max) |
| "Solve 17 * 23 step by step." | off | 390ms | 12.8s | 600 (hit max) |
| same | on | 330ms | 12.8s | 600 (hit max) |

Headline takeaways:
- **First-token latency is ~300–400ms in both modes** — thinking doesn't delay the first token
- **Total latency diverges** because thinking produces more output tokens
- **Reasoning prompts can hit `max_tokens` even with thinking off** — bound `max_tokens` aggressively if you need a latency cap

Measure your workload — these vary by prompt.

## Stripping the preamble (if thinking is on)

There is no reliable programmatic delimiter — the model transitions from preamble to answer in prose. Options:

### Option 1: Just turn thinking off

The cleanest fix. If you don't need the reasoning, set `enable_thinking: false` and skip the parsing problem entirely.

### Option 2: Heuristic prefix-strip

If the preamble usually starts with one of a few markers, strip up to the first double-newline-then-content boundary:

```python
def strip_preamble(content: str) -> str:
    # Drop content up to and including the last "step" or "process" heading
    markers = ("\n\n## ", "\n\n### ", "\n\n**Answer", "\n\n---")
    for m in markers:
        idx = content.rfind(m)
        if idx > 0:
            return content[idx:].strip()
    return content.strip()
```

This is heuristic and fragile — the model's preamble format isn't a contract.

### Option 3: Two-pass (think → answer)

For high-quality structured output, do two calls:

1. Thinking-on call to a scratch model, then
2. Thinking-off structured call using the scratch output as context

Higher cost; cleaner output. Use only when you specifically need both depth and clean structure.

## Combining with structured output

`response_format` works with thinking on or off:

- **Thinking off** (recommended): you get a clean JSON response in `content`, parse with `json.loads`.
- **Thinking on**: `content` is `<prose preamble>...<final JSON>`. You can't reliably split with regex. Either:
  - Strip via Option 2 above (fragile), or
  - Just set thinking off for the structured call.

For classification / extraction / structured tasks, **default to thinking off**.

## Combining with tools

Standard OpenAI function calling works with either thinking mode:

- **Thinking on**: model reasons about whether to call a tool, then emits `tool_calls`.
- **Thinking off**: model emits `tool_calls` directly with less internal deliberation.

The right choice depends on tool selection complexity. For simple "single tool dispatch" use cases, thinking off is fine.

## Streaming + thinking

When streaming with thinking on, the preamble streams first as content deltas, then the actual answer. You can't suppress the preamble mid-stream — only by setting `enable_thinking: false` from the start.

For a chat UI that shows thinking separately ("thinking..." spinner + answer), the cleanest pattern is:

1. Fire two requests: one with `enable_thinking: true` for the reasoning (show in a collapsible / faded UI), one with `enable_thinking: false` for the answer
2. Or just turn thinking off and skip the visualization

The model's lack of `<think>` tags means there's no clean in-stream split point.

## Why no tags?

Verified empirically: the Subconscious deployment of Qwen-3.6 emits thinking as **plain prose** (starting with "Here's a thinking process:" or similar), not wrapped in `<think>...</think>` tags. The response's `reasoning_content` field is always null and `usage.reasoning_tokens` is always 0. This may change in future model versions; for now, plan around plain content.

(On the legacy `/v1/completions` endpoint, behavior differs — see `api-reference.md` § thinking notes. Default there emits an empty `<think></think>` block.)
