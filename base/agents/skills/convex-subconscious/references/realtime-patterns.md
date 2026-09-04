# Convex Real-Time Patterns

## Schema Design

Define schemas with Convex validators. Every table field must be explicitly typed.

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

### With Auth Tables (Next.js + Convex Auth)

```typescript
import { authTables } from "@convex-dev/auth/server";

export default defineSchema({
  ...authTables,

  reports: defineTable({
    title: v.string(),
    userId: v.id("users"),
    createdAt: v.number(),
  }).index("by_userId", ["userId"]),

  chatMessages: defineTable({
    reportId: v.id("reports"),
    role: v.string(),
    content: v.string(),
    timestamp: v.number(),
  }).index("by_reportId", ["reportId"]),
});
```

### Validators Reference
- `v.string()`, `v.number()`, `v.boolean()`, `v.null()`
- `v.id("tableName")` — typed document ID reference
- `v.optional(v.string())` — optional field
- `v.union(v.string(), v.number())` — union types
- `v.array(v.string())` — arrays
- `v.object({ key: v.string() })` — nested objects
- `v.any()` — escape hatch (avoid when possible)

### Index Design
- Indexes enable efficient filtered queries
- First field in index = equality filter, last field = range/order
- Always add `by_userId` index on user-owned tables
- `by_reportId` index for child tables (messages, steps, etc.)

## Queries (Reactive, Cached)

Queries are the primary way to read data. They are **reactive** — the UI automatically re-renders when underlying data changes.

```typescript
// convex/items.ts
import { query } from "./_generated/server";

export const list = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("items").order("desc").collect();
  },
});
```

### With Auth (per-user data)

```typescript
import { query } from "./_generated/server";
import { v } from "convex/values";
import { getAuthUserId } from "@convex-dev/auth/server";

export const getMyReports = query({
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx);
    if (!userId) return [];
    return ctx.db
      .query("reports")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .order("desc")
      .collect();
  },
});
```

Key behaviors:
- `useQuery` returns `undefined` while loading, then the data
- Data updates in real-time — no polling needed
- Queries are cached and deduplicated across components
- Queries CANNOT have side effects (no `fetch`, no `ctx.db.patch`)

## Mutations (Transactional Writes)

Mutations modify the database. They run in a transaction — all writes succeed or all fail.

### Public Mutations (client-callable)

```typescript
import { mutation } from "./_generated/server";
import { v } from "convex/values";

export const create = mutation({
  args: { name: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db.insert("items", {
      name: args.name,
      status: "pending",
      createdAt: Date.now(),
    });
  },
});
```

### Internal Mutations (server-only)

Use `internalMutation` for mutations called by HTTP actions or other Convex functions — prevents direct client calls:

```typescript
import { internalMutation } from "./_generated/server";
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
```

Called via `internal.*` from HTTP actions or Convex actions:
```typescript
await ctx.runMutation(internal.items.create, { name: "New item" });
```

## Actions (Side Effects)

Actions can call external APIs, use `fetch`, and perform non-deterministic operations. They can also call mutations and queries internally.

```typescript
import { action } from "./_generated/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";

export const triggerAgent = action({
  args: { instructions: v.string() },
  handler: async (ctx, args) => {
    // Create a record first
    await ctx.runMutation(internal.agentRuns.createRun, {
      runId: `pending-${Date.now()}`,
      instructions: args.instructions,
    });

    // Call external API (Subconscious)
    const response = await fetch("https://api.subconscious.dev/v1/runs", {
      method: "POST",
      headers: { Authorization: `Bearer ${process.env.SUBCONSCIOUS_API_KEY}` },
      body: JSON.stringify({ /* ... */ }),
    });

    return await response.json();
  },
});
```

Actions vs Mutations:
- Actions CAN call `fetch`, use `Math.random`, access `Date.now()` non-deterministically
- Actions CANNOT directly read/write the database — must use `ctx.runQuery` / `ctx.runMutation`
- Actions are NOT transactional
- Actions can have retry/timeout behavior

## HTTP Actions (External Endpoints)

HTTP actions expose REST endpoints on your `.convex.site` domain. Used for Subconscious tool endpoints and webhooks.

```typescript
// convex/http.ts
import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";

const http = httpRouter();

http.route({
  path: "/tools/create-item",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.json();

    const id = await ctx.runMutation(internal.items.create, {
      name: body.name,
    });

    return new Response(JSON.stringify({ success: true, id }), {
      headers: { "Content-Type": "application/json" },
    });
  }),
});

export default http;
```

HTTP actions can only call `runQuery`, `runMutation`, `runAction` on `ctx` — they cannot use `ctx.db` directly.

## Frontend Setup

### Vite + React (No Auth)

```typescript
// src/main.tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { ConvexProvider, ConvexReactClient } from "convex/react";
import { App } from "./App";

const convex = new ConvexReactClient(import.meta.env.VITE_CONVEX_URL);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ConvexProvider client={convex}>
      <App />
    </ConvexProvider>
  </StrictMode>
);
```

### Next.js + Convex Auth

```typescript
// src/components/ConvexClientProvider.tsx
"use client";

import { ConvexAuthNextjsProvider } from "@convex-dev/auth/nextjs";
import { ConvexReactClient } from "convex/react";
import { ReactNode } from "react";

const convex = new ConvexReactClient(process.env.NEXT_PUBLIC_CONVEX_URL!);

export default function ConvexClientProvider({ children }: { children: ReactNode }) {
  return (
    <ConvexAuthNextjsProvider client={convex}>
      {children}
    </ConvexAuthNextjsProvider>
  );
}
```

```typescript
// src/app/layout.tsx
import { ConvexAuthNextjsServerProvider } from "@convex-dev/auth/nextjs/server";
import ConvexClientProvider from "@/components/ConvexClientProvider";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <ConvexAuthNextjsServerProvider>
      <html lang="en">
        <body>
          <ConvexClientProvider>{children}</ConvexClientProvider>
        </body>
      </html>
    </ConvexAuthNextjsServerProvider>
  );
}
```

## Reactive UI Patterns

### useQuery + useAction (Agent Pattern)

```typescript
import { useQuery, useAction } from "convex/react";
import { api } from "../convex/_generated/api";

export function App() {
  // Reactive query — re-renders automatically when DB changes
  const items = useQuery(api.items.list);
  const agentRuns = useQuery(api.agentRuns.list);

  // Call the Convex action which triggers Subconscious
  const triggerAgent = useAction(api.agent.triggerAgent);

  const handleRun = async () => {
    await triggerAgent({
      instructions: "Create 3 items for my project",
    });
  };

  return (
    <div>
      <button onClick={handleRun}>Run Agent</button>

      {/* These update in real-time as the agent calls your tools */}
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

### Optimistic Updates

```typescript
const createItem = useMutation(api.items.create)
  .withOptimisticUpdate((localStore, args) => {
    const existing = localStore.getQuery(api.items.list);
    if (existing) {
      localStore.setQuery(api.items.list, {}, [
        { _id: "temp" as any, name: args.name, status: "pending", createdAt: Date.now() },
        ...existing,
      ]);
    }
  });
```

### Conditional Queries

```typescript
// Only runs the query when reportId is defined
const messages = useQuery(
  reportId ? api.chat.getMessages : "skip",
  reportId ? { reportId } : undefined
);
```

### Real-Time Chat Pattern

```typescript
function ChatPanel({ reportId }: { reportId: Id<"reports"> }) {
  const messages = useQuery(api.chat.getMessages, { reportId });

  // Messages update in real-time — when the AI saves a response
  // via HTTP action, this component re-renders automatically
}
```

## The Reactive Loop (How It All Connects)

```
1. React: useAction(api.agent.triggerAgent) → starts Subconscious run
2. Subconscious agent reasons, calls POST /tools/create-item
3. Convex HTTP action: ctx.runMutation(internal.items.create, ...)
4. Convex DB writes → invalidates all subscriptions to items.list
5. React: useQuery(api.items.list) re-renders with new data — instantly
```

No polling. No manual WebSocket management. No cache invalidation. The AI agent modifies data, and every connected client sees changes in real-time.
