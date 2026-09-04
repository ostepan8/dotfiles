# Examples

Working snippets, verified against the live API 2026-05-22. All assume `SUBCONSCIOUS_API_KEY` is set.

## 1. Hello (Python)

```python
import os
from openai import OpenAI

client = OpenAI(
    base_url="https://api.subconscious.dev/v1",
    api_key=os.environ["SUBCONSCIOUS_API_KEY"],
)

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Hello"}],
    max_tokens=100,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

print(resp.choices[0].message.content)
print(f"used {resp.usage.prompt_tokens}in / {resp.usage.completion_tokens}out")
```

## 2. Hello (TypeScript)

```typescript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'https://api.subconscious.dev/v1',
  apiKey: process.env.SUBCONSCIOUS_API_KEY!,
});

const resp = await client.chat.completions.create({
  model: 'subconscious/tim-qwen3.6-27b',
  messages: [{ role: 'user', content: 'Hello' }],
  max_tokens: 100,
  // @ts-expect-error chat_template_kwargs is a Subconscious extension
  chat_template_kwargs: { enable_thinking: false },
});

console.log(resp.choices[0].message.content);
```

## 3. Hello (cURL)

```bash
curl https://api.subconscious.dev/v1/chat/completions \
  -H "Authorization: Bearer $SUBCONSCIOUS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "subconscious/tim-qwen3.6-27b",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100,
    "chat_template_kwargs": {"enable_thinking": false}
  }'
```

## 4. List the model — `GET /v1/models`

```bash
curl https://api.subconscious.dev/v1/models \
  -H "Authorization: Bearer $SUBCONSCIOUS_API_KEY"
```

Returns the authoritative model spec — context length, max output, sampling parameters honored, features, modalities. Treat this as the source of truth.

## 5. Thinking on vs off

```python
# Thinking off — fast chat reply, no preamble
fast = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "What's the capital of France?"}],
    max_tokens=50,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
# content: "Paris."

# Thinking on (default) — model emits a reasoning preamble before the answer
deep = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Plan a 3-day Tokyo itinerary."}],
    max_tokens=2000,
)
# content starts with: "Here's a thinking process:\n\n1. **Understand the request:**..."
```

The model does NOT use `<think>...</think>` tags — thinking is plain prose in `content`. To get a clean answer, set `enable_thinking: false`.

## 6. Streaming

```python
stream = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Write a haiku about Boston."}],
    stream=True,
    stream_options={"include_usage": True},
    max_tokens=100,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

for chunk in stream:
    delta = chunk.choices[0].delta if chunk.choices else None
    if delta and delta.content:
        print(delta.content, end="", flush=True)
    if chunk.usage:
        print(f"\n[in={chunk.usage.prompt_tokens} out={chunk.usage.completion_tokens}]")
```

## 7. Structured output (response_format with json_schema)

```python
import json
from openai import OpenAI

client = OpenAI(
    base_url="https://api.subconscious.dev/v1",
    api_key=os.environ["SUBCONSCIOUS_API_KEY"],
)

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Analyze: 'Great product, fast shipping!'"}],
    response_format={
        "type": "json_schema",
        "json_schema": {
            "name": "sentiment",
            "schema": {
                "type": "object",
                "properties": {
                    "sentiment": {"type": "string", "enum": ["positive", "neutral", "negative"]},
                    "confidence": {"type": "number"},
                },
                "required": ["sentiment", "confidence"],
            },
            "strict": True,
        },
    },
    max_tokens=200,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

result = json.loads(resp.choices[0].message.content)
print(result)
# {'sentiment': 'positive', 'confidence': 0.95}
```

## 8. Structured output (Pydantic)

```python
from pydantic import BaseModel
from openai import OpenAI

class Sentiment(BaseModel):
    label: str
    confidence: float
    keywords: list[str]

client = OpenAI(
    base_url="https://api.subconscious.dev/v1",
    api_key=os.environ["SUBCONSCIOUS_API_KEY"],
)

resp = client.beta.chat.completions.parse(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Analyze: 'works great'"}],
    response_format=Sentiment,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

result = resp.choices[0].message.parsed   # typed Sentiment instance
print(result.label, result.confidence)
```

## 9. json_mode (simpler structured output, no schema)

```python
resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[
        {"role": "system", "content": "Respond with a JSON object."},
        {"role": "user", "content": "List 3 fruits with their colors."},
    ],
    response_format={"type": "json_object"},
    max_tokens=200,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
print(resp.choices[0].message.content)
```

## 10. Function tool — full loop

```python
import json
from openai import OpenAI

client = OpenAI(
    base_url="https://api.subconscious.dev/v1",
    api_key=os.environ["SUBCONSCIOUS_API_KEY"],
)

def get_weather(city: str) -> dict:
    return {"city": city, "temp_f": 72, "condition": "sunny"}


tools = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get current weather for a city",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"],
        },
    },
}]

messages = [{"role": "user", "content": "What's the weather in Boston?"}]

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=messages,
    tools=tools,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

msg = resp.choices[0].message
if msg.tool_calls:
    messages.append({
        "role": "assistant",
        "content": msg.content,
        "tool_calls": [{
            "id": tc.id,
            "type": "function",
            "function": {"name": tc.function.name, "arguments": tc.function.arguments},
        } for tc in msg.tool_calls],
    })
    for tc in msg.tool_calls:
        result = get_weather(**json.loads(tc.function.arguments))
        messages.append({
            "role": "tool",
            "tool_call_id": tc.id,
            "content": json.dumps(result),
        })
    resp = client.chat.completions.create(
        model="subconscious/tim-qwen3.6-27b",
        messages=messages,
        tools=tools,
        extra_body={"chat_template_kwargs": {"enable_thinking": False}},
    )

print(resp.choices[0].message.content)
```

## 11. `tool_choice` — control whether/which tool runs

```python
# Force the model to use a specific tool
resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Boston"}],
    tools=[
        {"type": "function", "function": {"name": "get_weather", "description": "...",
                                          "parameters": {"type": "object",
                                                         "properties": {"city": {"type": "string"}},
                                                         "required": ["city"]}}},
    ],
    tool_choice={"type": "function", "function": {"name": "get_weather"}},
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
print(resp.choices[0].message.tool_calls[0].function.arguments)
# {"city": "Boston"}

# Force model to NOT call any tool — get a plain reply even with tools defined
resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "What's the weather in Boston?"}],
    tools=[WEATHER_TOOL],
    tool_choice="none",
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
print(resp.choices[0].message.content)
# "I don't have real-time weather data..."

# Force model to call SOME tool (errors if it can't)
resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Hello"}],
    tools=[WEATHER_TOOL],
    tool_choice="required",
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
```

## 12. Legacy text completions (`/v1/completions`)

For prompt-completion patterns without messages structure. Verified to accept all standard OpenAI completion fields.

```python
import httpx, os

r = httpx.post(
    "https://api.subconscious.dev/v1/completions",
    headers={"Authorization": f"Bearer {os.environ['SUBCONSCIOUS_API_KEY']}",
             "Content-Type": "application/json"},
    json={
        "model": "subconscious/tim-qwen3.6-27b",
        "prompt": "The capital of France is",
        "max_tokens": 20,
        "stop": ["."],
        "temperature": 0,
    },
    timeout=30.0,
)
print(r.json()["choices"][0]["text"])
```

### Batch via prompt array

```python
r = httpx.post(
    "https://api.subconscious.dev/v1/completions",
    headers={"Authorization": f"Bearer {os.environ['SUBCONSCIOUS_API_KEY']}",
             "Content-Type": "application/json"},
    json={
        "model": "subconscious/tim-qwen3.6-27b",
        "prompt": ["Hello", "Goodbye"],
        "max_tokens": 20,
    },
    timeout=30.0,
)
# Returns one choice per prompt
for i, choice in enumerate(r.json()["choices"]):
    print(f"[{i}] {choice['text']}")
```

### Echo + suffix

```python
# echo=True prepends the prompt to the response text
r = httpx.post(
    "https://api.subconscious.dev/v1/completions",
    headers={"Authorization": f"Bearer {os.environ['SUBCONSCIOUS_API_KEY']}",
             "Content-Type": "application/json"},
    json={
        "model": "subconscious/tim-qwen3.6-27b",
        "prompt": "Once upon a time",
        "max_tokens": 30,
        "echo": True,
    },
)
# text starts with "Once upon a time..." then continues
```

**Important**: Thinking behavior on `/v1/completions` is **different from `/v1/chat/completions`** and unstable — don't pass `chat_template_kwargs.enable_thinking`. The default produces clean output for most prompts. See `api-reference.md` for details.

Prefer `/chat/completions` for new code; use this only when porting existing prompt-completion pipelines or when you specifically need `echo` / batch.

## 13. Conversation history (multi-turn)

```python
messages = [
    {"role": "system", "content": "Reply with one short word only."},
    {"role": "user", "content": "What's the capital of France?"},
]

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=messages,
    max_tokens=20,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
a1 = resp.choices[0].message.content    # "Paris"

messages.append({"role": "assistant", "content": a1})
messages.append({"role": "user", "content": "And its country?"})

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=messages,
    max_tokens=20,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
print(resp.choices[0].message.content)   # "France"
```

## 14. Next.js — proxy from your backend

```typescript
// app/api/chat/route.ts
import { NextRequest } from 'next/server';
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'https://api.subconscious.dev/v1',
  apiKey: process.env.SUBCONSCIOUS_API_KEY!,
});

export async function POST(req: NextRequest) {
  const { messages } = await req.json();

  const stream = await client.chat.completions.create({
    model: 'subconscious/tim-qwen3.6-27b',
    messages,
    stream: true,
    stream_options: { include_usage: true },
    // @ts-expect-error
    chat_template_kwargs: { enable_thinking: false },
  });

  const encoder = new TextEncoder();
  const readable = new ReadableStream({
    async start(controller) {
      try {
        for await (const chunk of stream) {
          const text = chunk.choices[0]?.delta?.content;
          if (text) controller.enqueue(encoder.encode(`data: ${JSON.stringify({ content: text })}\n\n`));
        }
        controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      } finally {
        controller.close();
      }
    },
  });

  return new Response(readable, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    },
  });
}
```

## 15. Retry helper

```python
import time, random
from openai import OpenAI, RateLimitError, APIStatusError

def call(messages, *, retries=5):
    for attempt in range(retries):
        try:
            return client.chat.completions.create(
                model="subconscious/tim-qwen3.6-27b",
                messages=messages,
                extra_body={"chat_template_kwargs": {"enable_thinking": False}},
            )
        except RateLimitError:
            time.sleep(1.0 * (2 ** attempt) + random.random())
        except APIStatusError as e:
            if 500 <= e.status_code < 600:
                time.sleep(1.0 * (2 ** attempt) + random.random())
            else:
                raise
    raise RuntimeError("retries exhausted")
```

## 16. Usage tracking wrapper

```python
import logging
log = logging.getLogger(__name__)

def chat(messages, *, route: str, thinking: bool = False, **kw):
    resp = client.chat.completions.create(
        model="subconscious/tim-qwen3.6-27b",
        messages=messages,
        extra_body={"chat_template_kwargs": {"enable_thinking": thinking}, **kw},
    )
    u = resp.usage
    cost_micros = u.prompt_tokens * 50 + u.completion_tokens * 350
    log.info("subconscious.call", extra={
        "route": route,
        "thinking": thinking,
        "input_tokens": u.prompt_tokens,
        "output_tokens": u.completion_tokens,
        "cost_micros": cost_micros,
    })
    return resp
```

## 17. Multiple completions (`n>1`)

Returns N choices from one batched call. Cheaper than N separate requests because the prompt is processed once.

```python
resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Suggest a random English word."}],
    n=3,
    max_tokens=20,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

for i, choice in enumerate(resp.choices):
    print(f"[{i}] {choice.message.content}")

# Usage shows total tokens across all completions
print(f"usage: prompt={resp.usage.prompt_tokens} completion={resp.usage.completion_tokens}")
```

Useful for: sampling diversity, generating multiple suggestions to rank client-side, ensemble approaches.

## 18. Vision via data URL (most reliable image path)

The model's spec says text-only, but vision works for many image sources. **Data URLs are the most reliable path** — they don't depend on the gateway being able to fetch a remote URL.

```python
import base64
from openai import OpenAI

client = OpenAI(
    base_url="https://api.subconscious.dev/v1",
    api_key=os.environ["SUBCONSCIOUS_API_KEY"],
)

with open("photo.png", "rb") as f:
    data = base64.b64encode(f.read()).decode()

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{
        "role": "user",
        "content": [
            {"type": "text", "text": "What is in this image?"},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{data}"}},
        ],
    }],
    max_tokens=200,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
print(resp.choices[0].message.content)
```

Audio (`input_audio`), file (`file`), and video blocks all return 400 — vision-only.

## 19. Check the model's capabilities programmatically

```python
import httpx
import os

r = httpx.get(
    "https://api.subconscious.dev/v1/models",
    headers={"Authorization": f"Bearer {os.environ['SUBCONSCIOUS_API_KEY']}"},
    timeout=30.0,
)
spec = r.json()["data"][0]
print(f"context: {spec['context_length']}")
print(f"max output: {spec['max_completion_tokens']}")
print(f"sampling params: {spec['supported_sampling_parameters']}")
print(f"features: {spec['supported_features']}")
print(f"modalities: in={spec['input_modalities']} out={spec['output_modalities']}")
```

Use this as a self-check in your app's startup or test suite so you notice when capabilities change.
