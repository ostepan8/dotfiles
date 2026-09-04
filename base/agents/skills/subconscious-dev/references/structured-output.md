# Structured output

Use OpenAI's standard `response_format` field with JSON Schema. The model's `supported_features` includes both `json_mode` and `structured_outputs`, so both pathways work.

## Basic shape

```python
resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Analyze: 'Great product, fast shipping'"}],
    response_format={
        "type": "json_schema",
        "json_schema": {
            "name": "sentiment_result",
            "schema": {
                "type": "object",
                "properties": {
                    "sentiment": {"type": "string", "enum": ["positive", "neutral", "negative"]},
                    "confidence": {"type": "number"},
                    "keywords": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["sentiment", "confidence"],
            },
        },
    },
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

import json
result = json.loads(resp.choices[0].message.content)
# {'sentiment': 'positive', 'confidence': 0.95, ...}
```

Verified working 2026-05-22. The OpenAI shape `{type: "json_schema", json_schema: {name, schema}}` is correct.

## Turn thinking OFF for structured output

When `enable_thinking: true`, the model emits a plain-prose reasoning preamble before the JSON — you can't reliably parse the result. **Set `enable_thinking: false` on structured-output calls** for clean JSON.

If you really need both thinking and structured output, do two calls: thinking-on for reasoning, thinking-off (with the reasoning embedded in context) for the structured emit. Or accept fragile prefix-stripping.

## json_mode (simpler alternative)

OpenAI's lighter "just give me valid JSON" mode also works:

```python
resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[
        {"role": "system", "content": "Respond with a JSON object."},
        {"role": "user", "content": "..."},
    ],
    response_format={"type": "json_object"},
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
```

No schema enforcement, but the output is guaranteed parseable JSON. Useful when the structure is simple or your downstream code does its own validation.

## Pydantic in Python

```python
from pydantic import BaseModel
from openai import OpenAI
import json

class Analysis(BaseModel):
    sentiment: str
    confidence: float
    keywords: list[str]

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Analyze: 'works great but slow'"}],
    response_format={
        "type": "json_schema",
        "json_schema": {"name": "analysis", "schema": Analysis.model_json_schema()},
    },
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

result = Analysis.model_validate_json(resp.choices[0].message.content)
print(result.sentiment, result.confidence)
```

The OpenAI SDK also offers `client.beta.chat.completions.parse(...)` which takes a Pydantic class directly:

```python
resp = client.beta.chat.completions.parse(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "..."}],
    response_format=Analysis,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
result = resp.choices[0].message.parsed   # typed Analysis instance
```

## Zod in TypeScript

```typescript
import { z } from 'zod';
import OpenAI from 'openai';
import { zodToJsonSchema } from 'zod-to-json-schema';

const Analysis = z.object({
  sentiment: z.enum(['positive', 'neutral', 'negative']),
  confidence: z.number(),
  keywords: z.array(z.string()),
});

const client = new OpenAI({
  baseURL: 'https://api.subconscious.dev/v1',
  apiKey: process.env.SUBCONSCIOUS_API_KEY!,
});

const resp = await client.chat.completions.create({
  model: 'subconscious/tim-qwen3.6-27b',
  messages: [{ role: 'user', content: '...' }],
  response_format: {
    type: 'json_schema',
    json_schema: { name: 'analysis', schema: zodToJsonSchema(Analysis) },
  },
  // @ts-expect-error chat_template_kwargs is a Subconscious extension
  chat_template_kwargs: { enable_thinking: false },
});

const parsed = Analysis.parse(JSON.parse(resp.choices[0].message.content));
```

The OpenAI SDK's `zodResponseFormat` helper works the same way:

```typescript
import { zodResponseFormat } from 'openai/helpers/zod';

const resp = await client.beta.chat.completions.parse({
  model: 'subconscious/tim-qwen3.6-27b',
  messages: [{ role: 'user', content: '...' }],
  response_format: zodResponseFormat(Analysis, 'analysis'),
});
const parsed = resp.choices[0].message.parsed;
```

## Streaming structured output

`stream: true` + `response_format` works at the protocol level, but you can't reliably parse partial JSON mid-stream. Options:

1. Buffer all `delta.content`, parse once on `[DONE]`
2. Show "Generating…" until complete

For interactive UX, prefer non-structured streaming + a separate non-streamed structured call, or just turn thinking off so the structured response arrives quickly enough to skip streaming.

## Schema design tips

- **Required fields**: list everything you can't tolerate as missing
- **Enums for categoricals**: cleaner target than free-text
- **`description` per field**: nudges the model toward the right values
- **Avoid deep nesting**: 1–2 levels best; 3+ degrades reliability
- **`additionalProperties: false`** to forbid extras (works with structured_outputs)
- **Keep schemas small**: every property eats context

## Best practices

- **Default `enable_thinking: false`** on structured-output calls
- **Validate every response** with your Pydantic / Zod schema — model output isn't a contract
- **Track validation-failure rate** as a metric; high failures signal a schema problem
- **Set `max_tokens`** to cap runaway generations on bad prompts
- **Use `json_mode`** when you don't need schema validation — lower overhead
- **Strip whitespace** before `json.loads` if you've had thinking on at any point
