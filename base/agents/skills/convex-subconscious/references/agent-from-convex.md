# Triggering Subconscious Agents from Convex

Complete guide for running Subconscious AI agents from Convex actions, with webhook callbacks and agent run tracking.

## Schema: Agent Run Tracking

Track agent runs so the frontend can show status in real-time:

```typescript
// convex/schema.ts
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  items: defineTable({
    name: v.string(),
    status: v.string(),       // "pending" | "done" | "error"
    result: v.optional(v.string()),
    createdAt: v.number(),
  }),
  agentRuns: defineTable({
    runId: v.string(),
    status: v.string(),       // "queued" | "running" | "succeeded" | "failed"
    instructions: v.string(),
    answer: v.optional(v.string()),
    createdAt: v.number(),
  }).index("by_runId", ["runId"]),
});
```

## Agent Run Mutations

Use `internalMutation` so these can only be called from Convex functions (not the client):

```typescript
// convex/agentRuns.ts
import { internalMutation, query } from "./_generated/server";
import { v } from "convex/values";

export const createRun = internalMutation({
  args: {
    runId: v.string(),
    instructions: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("agentRuns", {
      runId: args.runId,
      status: "queued",
      instructions: args.instructions,
      createdAt: Date.now(),
    });
  },
});

export const updateRun = internalMutation({
  args: {
    runId: v.string(),
    status: v.string(),
    answer: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const run = await ctx.db
      .query("agentRuns")
      .withIndex("by_runId", (q) => q.eq("runId", args.runId))
      .unique();
    if (!run) return;
    await ctx.db.patch(run._id, {
      status: args.status,
      answer: args.answer,
    });
  },
});

export const updateRunId = internalMutation({
  args: {
    tempId: v.string(),
    runId: v.string(),
  },
  handler: async (ctx, args) => {
    const run = await ctx.db
      .query("agentRuns")
      .withIndex("by_runId", (q) => q.eq("runId", args.tempId))
      .unique();
    if (!run) return;
    await ctx.db.patch(run._id, { runId: args.runId, status: "running" });
  },
});

export const list = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("agentRuns").order("desc").collect();
  },
});
```

## Convex Action: Trigger Subconscious

Actions (not mutations) call external APIs. This action creates a run record, then kicks off a Subconscious agent:

```typescript
// convex/agent.ts
import { action } from "./_generated/server";
import { v } from "convex/values";
import { Subconscious } from "subconscious";
import { internal } from "./_generated/api";

export const triggerAgent = action({
  args: { instructions: v.string() },
  handler: async (ctx, args) => {
    const client = new Subconscious({
      apiKey: process.env.SUBCONSCIOUS_API_KEY!,
    });

    const siteUrl = process.env.CONVEX_SITE_URL!;

    // Create a run record first (visible to frontend immediately)
    const runId = `pending-${Date.now()}`;
    await ctx.runMutation(internal.agentRuns.createRun, {
      runId,
      instructions: args.instructions,
    });

    const run = await client.run({
      engine: "tim-gpt",
      input: {
        instructions: args.instructions,
        tools: [
          { type: "platform", id: "web_search" },
          {
            type: "function",
            name: "create_item",
            description: "Create a new item in the database",
            url: `${siteUrl}/tools/create-item`,
            method: "POST",
            parameters: {
              type: "object",
              properties: {
                name: { type: "string", description: "The item name" },
              },
              required: ["name"],
              additionalProperties: false,
            },
          },
          {
            type: "function",
            name: "complete_item",
            description: "Mark an item as complete with a result message",
            url: `${siteUrl}/tools/complete-item`,
            method: "POST",
            parameters: {
              type: "object",
              properties: {
                id: { type: "string", description: "The item ID" },
                result: { type: "string", description: "Completion message" },
              },
              required: ["id"],
              additionalProperties: false,
            },
          },
        ],
        skills: ["api-design"],  // optional: attach reusable knowledge packages
      },
      output: {
        callbackUrl: `${siteUrl}/webhooks/subconscious`,
      },
    });

    // Update run record with real runId
    await ctx.runMutation(internal.agentRuns.updateRunId, {
      tempId: runId,
      runId: run.runId,
    });

    return run.runId;
  },
});
```

### Sync vs Async

**Async with webhook** (recommended for UI):
```typescript
const run = await client.run({
  engine: "tim-gpt",
  input: { instructions, tools },
  output: {
    callbackUrl: `${siteUrl}/webhooks/subconscious`,
  },
});
// Returns immediately. Result arrives via webhook → Convex mutation → reactive UI.
```

**Sync (wait for result)**:
```typescript
const run = await client.run({
  engine: "tim-gpt",
  input: { instructions, tools },
  options: { awaitCompletion: true },
});
// Blocks until complete. Good for short tasks, bad for UX on long ones.
const answer = run.result?.answer;
```

## Webhook Handler

Subconscious POSTs the result to your webhook when an async run completes. The payload contains `result.answer` (string) and optionally `result.reasoning` (array):

```typescript
// In convex/http.ts — add this route
http.route({
  path: "/webhooks/subconscious",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const payload = await request.json();
    const { runId, status, result } = payload;

    if (status === "succeeded") {
      await ctx.runMutation(internal.agentRuns.updateRun, {
        runId,
        status: "succeeded",
        answer: result.answer,
      });
    } else {
      await ctx.runMutation(internal.agentRuns.updateRun, { runId, status });
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }),
});
```

### Webhook Payload Shape

```json
{
  "runId": "bcccd0a3-...",
  "status": "succeeded",
  "engine": "tim-gpt",
  "result": {
    "answer": "The clean text answer",
    "reasoning": [{ "thought": "...", "conclusion": "..." }]
  },
  "tokens": { "inputTokens": 1980, "outputTokens": 406, "costCents": 0 },
  "createdAt": "2026-03-26T20:06:37.956Z",
  "completedAt": "2026-03-26T20:06:46.777Z"
}
```

Same structure as the SDK `RunResponse` — `result.answer` is a string, `result.reasoning` is the step-by-step trace. Webhook subscriptions can be configured with `responseContent: "answer_only"` to strip reasoning from the payload.

## Structured Output with Zod

Get typed, parsed responses from the agent:

```typescript
import { Subconscious, zodToJsonSchema } from "subconscious";
import { z } from "zod";

const TaskResult = z.object({
  tasks: z.array(z.object({
    name: z.string().describe("Task name"),
    priority: z.enum(["high", "medium", "low"]).describe("Task priority"),
  })),
  summary: z.string().describe("Brief summary of what was done"),
});

const run = await client.run({
  engine: "tim-gpt",
  input: {
    instructions: "Plan 3 tasks for launching a new feature",
    answerFormat: zodToJsonSchema(TaskResult, "TaskResult"),
  },
  options: { awaitCompletion: true },
});

const result = run.result?.answer as z.infer<typeof TaskResult>;
// result.tasks is typed: Array<{name: string, priority: "high"|"medium"|"low"}>
```

## Streaming (for Chat UI)

```typescript
const stream = client.stream({
  engine: "tim-gpt",
  input: {
    instructions: "Describe the steps to deploy this app",
    tools: [{ type: "platform", id: "web_search" }],
  },
});

for await (const event of stream) {
  if (event.type === "delta") {
    process.stdout.write(event.content);  // token by token
  } else if (event.type === "done") {
    console.log("\nDone:", event.runId);
  }
}
```

**WARNING**: Stream content is raw JSON, not clean text. For most chat UIs, use `run()` with `awaitCompletion: true` instead — it returns clean text in `run.result?.answer`.

## Platform Tools (No Server Needed)

Combine with your custom Convex tools:

```typescript
tools: [
  // Built-in platform tools (no URL needed)
  { type: "platform", id: "web_search" },
  { type: "platform", id: "fast_search" },
  { type: "platform", id: "fresh_search" },
  { type: "platform", id: "news_search" },
  { type: "platform", id: "page_reader" },
  { type: "platform", id: "find_similar" },
  { type: "platform", id: "people_search" },
  { type: "platform", id: "company_search" },
  { type: "platform", id: "tweet_search" },
  { type: "platform", id: "research_paper_search" },
  { type: "platform", id: "google_search" },

  // MCP tools (connect to any MCP server)
  { type: "mcp", url: "https://mcp.notion.so/v1", allowedTools: ["search"] },

  // Your custom Convex tools
  { type: "function", name: "create_item", url: `${siteUrl}/tools/create-item`, /* ... */ },
]
```

## Frontend: Trigger Agent and Show Results

```typescript
import { useQuery, useAction } from "convex/react";
import { api } from "../convex/_generated/api";

export function AgentPanel() {
  // Reactive queries — re-render automatically when DB changes
  const items = useQuery(api.items.list);
  const agentRuns = useQuery(api.agentRuns.list);

  // Call the Convex action which triggers Subconscious
  const triggerAgent = useAction(api.agent.triggerAgent);

  const handleRun = async () => {
    const runId = await triggerAgent({
      instructions: "Create 3 items for my project and mark them pending",
    });
    console.log("Started run:", runId);
  };

  return (
    <div>
      <button onClick={handleRun}>Run Agent</button>

      {/* Items update in real-time as the agent calls your tools */}
      <ul>
        {items?.map((item) => (
          <li key={item._id}>
            {item.name} — {item.status}
            {item.result && <span> ({item.result})</span>}
          </li>
        ))}
      </ul>

      {/* Track agent run status */}
      {agentRuns?.map((run) => (
        <div key={run._id}>
          Run {run.runId.slice(0, 8)}: {run.status}
          {run.answer && <p>{run.answer}</p>}
        </div>
      ))}
    </div>
  );
}
```

## Skills (Reusable Knowledge Packages)

Pass skill names in `input.skills` to give the agent specialized knowledge:

```typescript
const run = await client.run({
  engine: "tim-gpt",
  input: {
    instructions: "Build a REST API with error handling",
    tools: [{ type: "platform", id: "web_search" }],
    skills: ["api-design", "error-handling"],
  },
  options: { awaitCompletion: true },
});
```

Skills use progressive disclosure — the agent sees a brief manifest, then loads full instructions on demand via `LoadSkill` and `ReadSkillReference` (auto-injected). Browse and create skills at [subconscious.dev/platform/skills](https://www.subconscious.dev/platform/skills).

## Error Handling

The SDK exports named error classes for specific failure modes:

```typescript
import { SubconsciousError, AuthenticationError, RateLimitError } from "subconscious";

try {
  const run = await client.run({ /* ... */ });
} catch (error) {
  if (error instanceof AuthenticationError) {
    console.error("Invalid API key");
  } else if (error instanceof RateLimitError) {
    console.error("Rate limited, retry later");
  } else if (error instanceof SubconsciousError) {
    console.error(`API error: ${error.code} - ${error.message}`);
  }
}
```

Always check `run.status` before accessing `run.result`:

```typescript
if (run.status === "succeeded") {
  console.log(run.result?.answer);
} else if (run.status === "failed") {
  console.error("Run failed:", run.error?.message);
}
```

## Key Architecture Rules

1. **Actions call external APIs, mutations don't.** The Subconscious SDK call must be inside an `action` or `internalAction`.

2. **`process.env.CONVEX_SITE_URL`** is always available in Convex functions — it's the base URL for HTTP actions (ends in `.convex.site`).

3. **Tool endpoints are publicly accessible.** Convex `.convex.site` URLs are public by default. No tunneling needed in prod. During dev, `npx convex dev` deploys to real Convex cloud.

4. **Use `internal.*` for mutations called by HTTP actions.** This prevents the client from calling them directly while letting your HTTP actions and Convex actions use them.

5. **The webhook pattern is preferred for UI.** Async run → webhook → Convex mutation → reactive query update. The user sees real-time status without blocking.

## SDK Methods Reference

| Method | Description |
|--------|-------------|
| `client.run(params)` | Create a run (sync or async) |
| `client.stream(params)` | Stream text deltas in real-time |
| `client.get(runId)` | Get current status of a run |
| `client.wait(runId, options?)` | Poll until completion |
| `client.cancel(runId)` | Cancel a running/queued run |
