# Tools

Only **standard OpenAI function tools** work on this endpoint. The legacy Subconscious tool types (`type: "platform"`, MCP, URL-based function tools) all return 400 with a missing-`function` validation error — they're a Run-API concept, not chat-completions.

Confirmed by `/v1/models`: `supported_features` includes `"tools"`.

## Standard OpenAI function tool shape

```python
tools = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get current weather for a city",
        "parameters": {
            "type": "object",
            "properties": {
                "city": {"type": "string", "description": "City name"},
                "units": {"type": "string", "enum": ["celsius", "fahrenheit"]},
            },
            "required": ["city"],
        },
    },
}]
```

**Required**: Only `function.name`. `description` and `parameters` are both **optional** in practice — verified empirically. Missing the whole `function` object (e.g., `{"type": "function"}`) returns 400.

That said: **always include `description` and `parameters`** for selection accuracy. The model uses `description` to pick between tools, and `parameters` to know what to generate.

## How tool calling works

This is a **client-side tool loop** — Subconscious does NOT execute tools server-side here. Pattern:

1. You send the messages + tools.
2. If the model decides to call a tool, the response has `choices[0].message.tool_calls` populated and `finish_reason: "tool_calls"`.
3. Your code executes the function locally.
4. You append the assistant message (with the tool_calls) and a new message with `role: "tool"` containing the result.
5. You call the API again with the updated history.

## Example — full loop

```python
import json
from openai import OpenAI

client = OpenAI(
    base_url="https://api.subconscious.dev/v1",
    api_key=os.environ["SUBCONSCIOUS_API_KEY"],
)

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

def get_weather(city: str) -> dict:
    # your actual implementation
    return {"city": city, "temp_f": 72, "condition": "sunny"}


messages = [{"role": "user", "content": "What's the weather in Boston?"}]

# 1. First call — model decides to use the tool
resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=messages,
    tools=tools,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

msg = resp.choices[0].message
if msg.tool_calls:
    # 2. Append the assistant message that requested the tool
    messages.append({
        "role": "assistant",
        "content": msg.content,
        "tool_calls": [{
            "id": tc.id,
            "type": "function",
            "function": {"name": tc.function.name, "arguments": tc.function.arguments},
        } for tc in msg.tool_calls],
    })

    # 3. Execute each tool call and append the result
    for tc in msg.tool_calls:
        args = json.loads(tc.function.arguments)
        result = get_weather(**args)
        messages.append({
            "role": "tool",
            "tool_call_id": tc.id,
            "content": json.dumps(result),
        })

    # 4. Call again with the tool results — model now produces the final answer
    resp = client.chat.completions.create(
        model="subconscious/tim-qwen3.6-27b",
        messages=messages,
        tools=tools,
        extra_body={"chat_template_kwargs": {"enable_thinking": False}},
    )

print(resp.choices[0].message.content)
```

## Tool call message shape

When the model decides to call a tool, the response message looks like:

```json
{
  "role": "assistant",
  "content": "...",          // may be empty or contain the model's reasoning
  "tool_calls": [
    {
      "id": "call_abc123",
      "type": "function",
      "function": {
        "name": "get_weather",
        "arguments": "{\"city\": \"Boston\"}"   // JSON-encoded string, not parsed object
      }
    }
  ]
}
```

`finish_reason` will be `"tool_calls"`.

## Tool result message

Echo each `tool_call_id` back when sending results:

```python
{
    "role": "tool",
    "tool_call_id": "call_abc123",
    "content": json.dumps({"city": "Boston", "temp_f": 72}),
}
```

`content` must be a string — JSON-encode structured data.

## `tool_choice` — controlling whether/which tool is called

All four standard OpenAI modes work (verified 2026-05-22):

```python
# Default — model decides
tool_choice="auto"

# Model must NOT call any tool (returns plain content)
tool_choice="none"

# Model must call SOME tool (errors out otherwise)
tool_choice="required"

# Force a specific tool
tool_choice={"type": "function", "function": {"name": "get_weather"}}
```

When to use each:

| Mode | When |
|---|---|
| `"auto"` | Default — let the model decide |
| `"none"` | Use the same prompt+tools shape but get a plain answer (no tool call) |
| `"required"` | Force tool usage when you know the answer must come from a tool |
| Specific function | Forced dispatch — useful in classification → action pipelines |

Example — forcing a specific tool when you've already decided what to call:

```python
resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{"role": "user", "content": "Boston"}],
    tools=[WEATHER_TOOL, CALC_TOOL],
    tool_choice={"type": "function", "function": {"name": "get_weather"}},
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
# resp.choices[0].message.tool_calls[0].function.name == "get_weather"
```

## Multiple tool calls in one turn

The model may call multiple tools in parallel — iterate over `message.tool_calls` and produce a `tool` message for each:

```python
for tc in msg.tool_calls:
    result = dispatch(tc.function.name, json.loads(tc.function.arguments))
    messages.append({
        "role": "tool",
        "tool_call_id": tc.id,
        "content": json.dumps(result),
    })
```

`parallel_tool_calls` is not in the model's `supported_sampling_parameters`, so whether you get parallel vs sequential is up to the model — don't force the flag.

## TypeScript example

```typescript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'https://api.subconscious.dev/v1',
  apiKey: process.env.SUBCONSCIOUS_API_KEY!,
});

const tools = [{
  type: 'function' as const,
  function: {
    name: 'get_weather',
    description: 'Get current weather for a city',
    parameters: {
      type: 'object',
      properties: { city: { type: 'string' } },
      required: ['city'],
    },
  },
}];

async function getWeather(city: string) {
  return { city, tempF: 72, condition: 'sunny' };
}

const messages: any[] = [{ role: 'user', content: "Weather in Boston?" }];

let resp = await client.chat.completions.create({
  model: 'subconscious/tim-qwen3.6-27b',
  messages,
  tools,
  // @ts-expect-error
  chat_template_kwargs: { enable_thinking: false },
});

const msg = resp.choices[0].message;
if (msg.tool_calls?.length) {
  messages.push({
    role: 'assistant',
    content: msg.content,
    tool_calls: msg.tool_calls,
  });
  for (const tc of msg.tool_calls) {
    const args = JSON.parse(tc.function.arguments);
    const result = await getWeather(args.city);
    messages.push({
      role: 'tool',
      tool_call_id: tc.id,
      content: JSON.stringify(result),
    });
  }
  resp = await client.chat.completions.create({
    model: 'subconscious/tim-qwen3.6-27b',
    messages,
    tools,
    // @ts-expect-error
    chat_template_kwargs: { enable_thinking: false },
  });
}

console.log(resp.choices[0].message.content);
```

## Best practices

- **Sharpen tool `description`** — the model picks tools by matching description against intent. Vague descriptions → poor tool selection.
- **Keep `parameters` simple** — flat object with primitive types works best. Deep nested schemas (object inside object, complex arrays) can cause the model to emit malformed/truncated arguments. Verified: a 3-level nested schema produced `"title": "project review\n</parameter"` style corruption.
- **Always set `max_tokens`** — runaway generations cost money even on tool dispatches.
- **Echo `tool_call_id` exactly** — mismatched IDs are accepted by the API (no 400) but the model may hallucinate or behave inconsistently. Always echo the ID the model gave you.
- **JSON-encode tool results** — `content` must be a string. Passing a dict returns 400 with a `string_type` validation error.
- **Don't ship non-`function` tool types** — `platform`, `mcp`, `custom`, `native`, `file_search`, `web_search`, `computer` all return 400 with a missing-`function` validation error.
- **Validate model output before calling functions** — `arguments` is a JSON-encoded string that you `json.loads`; wrap with try/except, handle malformed JSON.

## Common pitfalls

1. **Forgetting to send `tool_calls` back on the assistant turn.** The model expects you to echo the call structure before the tool result.
2. **Sending tool result as a dict instead of a string.** Both `content` fields are strings — passing a dict returns 400.
3. **Using non-`function` tool types** (`platform`, `mcp`, `custom`, `native`, `file_search`, `web_search`, `computer`). All return 400.
4. **Expecting `parallel_tool_calls` to work as a knob.** It doesn't — drop the field (but the model still does parallel calls when the prompt suggests it — verified: "Boston AND New York" produced 2 tool_calls).
5. **Mismatched `tool_call_id`.** Doesn't 400 but the model may hallucinate. Echo what it gave you.
6. **Deeply nested parameters schema.** Three+ levels of nesting can produce malformed/truncated arguments. Flatten when possible.
