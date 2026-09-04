# Subconscious + Convex Integration

Complete guide for connecting Subconscious AI agents to a Convex real-time backend using HTTP tool endpoints.

## Architecture

```
User triggers action → Convex action calls Subconscious SDK
  → Subconscious agent reasons, calls tools (POST to *.convex.site/tools/*)
  → Convex HTTP actions run mutations, write to database
  → Reactive queries auto-update all connected clients
  → (Optional) Webhook callback updates agent run status
```

The key insight: Subconscious agents call your Convex HTTP endpoints as tools. The Convex backend handles data, and the frontend reactively updates via `useQuery` subscriptions — no manual refresh needed.

## Tool Definition Schema

### CRITICAL: `additionalProperties: false`

ALL tool parameter schemas MUST include `additionalProperties: false` at the top level. Without it, the `tim-gpt` agent gets stuck in an infinite "Tinkering" loop and cannot call tools.

```typescript
// CORRECT
{
  type: "function",
  name: "create_item",
  description: "Create a new item in the database",
  url: `${process.env.CONVEX_SITE_URL}/tools/create-item`,
  method: "POST",
  parameters: {
    type: "object",
    properties: {
      name: { type: "string", description: "The item name" },
    },
    required: ["name"],
    additionalProperties: false,  // REQUIRED
  },
}

// WRONG — missing additionalProperties: false
{
  parameters: {
    type: "object",
    properties: { name: { type: "string" } },
    required: ["name"],
    // Agent will loop forever without additionalProperties: false
  },
}
```

### The `defaults` Field

The `defaults` object auto-injects values into every tool call at runtime. Rules:
1. Default keys MUST be defined in `parameters.properties` (Subconscious validates this)
2. Default keys should NOT be in the `required` array
3. Subconscious merges defaults into the tool call parameters before sending

```typescript
{
  parameters: {
    type: "object",
    properties: {
      reportId: { type: "string", description: "The report ID" },
      stepId: { type: "string", description: "e.g. step_1" },
    },
    required: ["stepId"],  // reportId NOT in required
    additionalProperties: false,
  },
  defaults: { reportId },  // Auto-injected by Subconscious
}
```

### Platform Tools

Include Subconscious built-in tools alongside your custom tools:

```typescript
const tools = [
  // Built-in platform tools (no URL or schema needed)
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

  // Your Convex HTTP endpoints
  { type: "function", name: "create_item", url: "...", /* ... */ },
  { type: "function", name: "complete_item", url: "...", /* ... */ },
];
```

### MCP Tools

Connect to any Model Context Protocol server:

```typescript
tools: [
  {
    type: "mcp",
    url: "https://mcp.notion.so/v1",
    allowedTools: ["search", "get_page"],  // omit for all tools
    auth: { type: "bearer", token: "your-token" },  // optional
  },
]
```

### Tool Headers

Add custom HTTP headers for authenticated tool endpoints:

```typescript
{
  type: "function",
  name: "my_api",
  description: "Call my authenticated API",
  url: "https://api.example.com/endpoint",
  method: "POST",
  parameters: { /* ... */ },
  headers: {
    "x-api-key": "your-secret-key",
  },
}
```

## Convex HTTP Tool Endpoints

### Body Format

Subconscious sends tool parameters **directly** in the POST body:
```json
{ "name": "Deploy to production" }
```

Your HTTP action receives the parameters as top-level fields in `request.json()`. No unwrapping needed:

```typescript
const body = await request.json();
const name = body.name as string;  // Parameters are top-level
```

### Complete HTTP Router with CORS

```typescript
// convex/http.ts
import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";

const http = httpRouter();

// CORS helper — required for Subconscious calls
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

// Preflight for create-item
http.route({
  path: "/tools/create-item",
  method: "OPTIONS",
  handler: httpAction(async () =>
    new Response(null, { status: 204, headers: corsHeaders })
  ),
});

// Tool: create an item in the database
http.route({
  path: "/tools/create-item",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.json();
    const name = body.name as string;

    if (!name) {
      return new Response(JSON.stringify({ error: "name required" }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    // runMutation writes to Convex DB → instantly pushes update to all
    // React clients subscribed via useQuery
    const id = await ctx.runMutation(internal.items.create, { name });

    return new Response(JSON.stringify({ success: true, id }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }),
});

// Preflight for complete-item
http.route({
  path: "/tools/complete-item",
  method: "OPTIONS",
  handler: httpAction(async () =>
    new Response(null, { status: 204, headers: corsHeaders })
  ),
});

// Tool: mark an item complete
http.route({
  path: "/tools/complete-item",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.json();

    await ctx.runMutation(internal.items.updateStatus, {
      id: body.id as string,
      status: "done",
      result: body.result as string | undefined,
    });

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }),
});

// Webhook: Subconscious calls this when an async run completes
// Payload: { runId, status, result: { answer, reasoning }, tokens, ... }
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

export default http;
```

### Internal Mutations (Secure)

Use `internalMutation` for mutations called by HTTP actions — they can't be called directly from the client:

```typescript
// convex/items.ts
import { internalMutation, query } from "./_generated/server";
import { v } from "convex/values";

export const create = internalMutation({
  args: { name: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db.insert("items", {
      name: args.name,
      status: "pending",
      createdAt: Date.now(),
    });
  },
});

export const updateStatus = internalMutation({
  args: {
    id: v.id("items"),
    status: v.string(),
    result: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.id, {
      status: args.status,
      result: args.result,
    });
  },
});

export const list = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("items").order("desc").collect();
  },
});
```

## Streaming with SSE (Next.js API Route)

For Next.js apps that want to stream Subconscious events to the client:

```typescript
// src/app/api/chat/stream/route.ts
import { NextRequest } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { api } from "../../../../convex/_generated/api";
import { Subconscious } from "subconscious";

export async function POST(req: NextRequest) {
  const { reportId, message } = await req.json();
  const convex = new ConvexHttpClient(process.env.NEXT_PUBLIC_CONVEX_URL!);
  const client = new Subconscious({ apiKey: process.env.SUBCONSCIOUS_API_KEY! });

  // Save user message
  await convex.mutation(api.chat.saveMessage, {
    reportId, role: "user", content: message,
  });

  // Fetch context for the agent
  const messages = await convex.query(api.chat.getMessages, { reportId });
  const history = messages.slice(-30).map(m =>
    `${m.role === "user" ? "User" : "Assistant"}: ${m.content}`
  ).join("\n\n");

  // Build tools pointing to Convex HTTP endpoints
  const convexSiteUrl = process.env.NEXT_PUBLIC_CONVEX_SITE_URL!;
  const tools = buildTools(convexSiteUrl, reportId);

  const encoder = new TextEncoder();
  const readable = new ReadableStream({
    async start(controller) {
      const stream = client.stream({
        engine: "tim-gpt",
        input: {
          instructions: `${SYSTEM_PROMPT}\n\n${history}\n\nUser: ${message}`,
          tools,
        },
      });

      let fullContent = "";
      for await (const event of stream) {
        if (event.type === "delta") {
          fullContent += event.content;
          controller.enqueue(encoder.encode(
            `data: ${JSON.stringify({ type: "thought", thought: "Thinking..." })}\n\n`
          ));
        } else if (event.type === "done") {
          let answer: string;
          try {
            const parsed = JSON.parse(fullContent);
            answer = parsed.answer ?? fullContent;
          } catch {
            answer = fullContent;
          }

          await convex.mutation(api.chat.saveMessage, {
            reportId, role: "assistant", content: answer,
          });

          controller.enqueue(encoder.encode(
            `data: ${JSON.stringify({ type: "answer", answer })}\n\n`
          ));
          controller.enqueue(encoder.encode("data: [DONE]\n\n"));
          controller.close();
        }
      }
    },
  });

  return new Response(readable, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}
```

## Real-Time Data Flow

When the Subconscious agent calls a tool (e.g., `create_item`):
1. Agent POSTs to `*.convex.site/tools/create-item`
2. Convex HTTP action runs `ctx.runMutation(internal.items.create, { ... })`
3. Mutation writes to database
4. ALL active `useQuery(api.items.list)` subscriptions fire
5. React components re-render with new data — **automatically, in real-time**

This is the power of combining Convex + Subconscious: the AI agent modifies data, and the user sees changes instantly without any manual refresh or polling.

## Subconscious Engines

| Engine | Type | Best For |
|--------|------|----------|
| `tim` | Unified | Flagship unified agent for a wide range of tasks |
| `tim-edge` | Unified | Speed, efficiency, search-heavy tasks |
| `timini` | Compound (Gemini-3 Flash) | Long-context and tool use, strong reasoning |
| `tim-gpt` | Compound (GPT-4.1) | Most use cases, good cost/performance balance |
| `tim-gpt-heavy` | Compound (GPT-5.2) | Maximum capability, complex reasoning |

## Debugging Tool Endpoints

Test HTTP endpoints directly with `curl` — parameters go directly in the body:

```bash
curl -X POST https://your-deployment.convex.site/tools/create-item \
  -H "Content-Type: application/json" \
  -d '{"name": "Test item"}'
```

Check Convex function logs:
```bash
npx convex logs --follow
```
