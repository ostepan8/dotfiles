---
name: convex-subconscious
description: Build real-time AI apps with Convex backend and Subconscious AI agents. This skill should be used when the user asks to "set up Convex", "add Convex auth", "create a Convex schema", "add real-time data", "connect Subconscious to Convex", "build AI agent tools with Convex", "set up Convex Auth with Next.js", "add email password auth with Convex", "create HTTP endpoints for AI tools", "integrate Subconscious agents", "trigger agent from Convex", "webhook callback for agent", "track agent runs", or mentions Convex, convex-dev/auth, ConvexAuthProvider, ConvexReactClient, httpRouter, Subconscious tools with Convex HTTP actions, ConvexProvider, useAction, useQuery with agents.
version: 2.1.0
---

# Convex + Subconscious: Full-Stack Real-Time AI Apps

Build production apps where AI agents modify data in real-time and every connected client sees changes instantly — no polling, no manual WebSocket management, no cache invalidation.

## Mental Model

**Subconscious** runs AI agents. Give it instructions + tools, it reasons, calls your tools, returns results. The "function tool" pattern hooks your Convex HTTP endpoints into the agent — Subconscious POSTs to your endpoint, which writes to Convex DB, which instantly pushes updates to all clients via WebSocket.

**Convex** is a reactive database + serverless backend. Queries are read-only and reactive (auto-push via WebSocket). Mutations are transactional writes. HTTP actions expose public endpoints at `https://<deployment>.convex.site`. Actions call external APIs.

## The Reactive Loop (Core Pattern)

```
1. React calls useAction(api.agent.triggerAgent) → starts Subconscious run
2. Subconscious agent reasons, calls POST /tools/create-item
3. Convex HTTP action calls ctx.runMutation(internal.items.create, ...)
4. Convex DB writes → invalidates all subscriptions to items.list
5. All clients subscribed via useQuery(api.items.list) re-render instantly
```

No polling. No manual WebSocket management. No cache invalidation.

## Architecture Overview

```
React App (Vite or Next.js)
  ├── ConvexProvider or ConvexAuthNextjsProvider
  ├── useQuery (reactive data — auto-updates)
  ├── useAction (triggers Subconscious via Convex action)
  └── useMutation (direct writes)
          ↓
Convex Backend (real-time database + functions)
  ├── Queries (reactive, cached, read-only)
  ├── Mutations / internalMutations (transactional writes)
  ├── Actions (side effects — call Subconscious SDK)
  └── HTTP Actions (tool endpoints for Subconscious agent)
          ↓
Subconscious AI Agent (tim-gpt / tim-edge / tim-gpt-heavy)
  ├── Calls Convex HTTP endpoints as tools
  ├── Uses platform tools (web_search, news_search, etc.)
  ├── Connects to MCP servers for external integrations
  ├── Loads skills for specialized knowledge
  └── Returns structured answers or calls webhook
```

## Quick Setup

### Option A: Use the Official Template (Fastest)

```bash
npx create-subconscious-app my-app --example convex_realtime
```

This scaffolds a working Convex + Subconscious app with real-time updates, tool calling, and a React frontend.

### Option B: Manual Setup

```bash
npm install subconscious convex
npx convex dev   # initializes project, writes CONVEX_DEPLOYMENT to .env.local
```

Set the Subconscious API key in your **Convex deployment** (not .env.local):

```bash
npx convex env set SUBCONSCIOUS_API_KEY your_api_key_here
npx convex env list  # verify
```

Frontend `.env.local` needs only `VITE_CONVEX_URL` or `NEXT_PUBLIC_CONVEX_URL` (auto-set by `npx convex dev`).

### Install This Skill for AI Coding Assistants

```bash
npx skills add https://github.com/subconscious-systems/skills --skill convex-subconscious
```

### 2. Required Files

| File | Purpose |
|------|---------|
| `convex/schema.ts` | DB schema with tables and indexes |
| `convex/http.ts` | HTTP router (tool endpoints + webhooks) |
| `convex/items.ts` | Queries + internal mutations for data |
| `convex/agentRuns.ts` | Agent run tracking (queries + mutations) |
| `convex/agent.ts` | Convex action that calls Subconscious SDK |
| `src/main.tsx` | ConvexProvider wrapper |
| `src/App.tsx` | useQuery / useAction hooks |

For **Next.js with auth**, also see `references/auth-nextjs.md` for the additional auth files.

### 3. Environment Variables

**Convex deployment** (set via `npx convex env set`):
- `SUBCONSCIOUS_API_KEY` — For AI agent calls
- `CONVEX_SITE_URL` — Built-in, auto-set (do NOT set manually)

**For Next.js auth** (additional):
- `JWT_PRIVATE_KEY`, `JWKS`, `SITE_URL` — See `references/auth-nextjs.md`

**`.env.local`** (frontend):
- `VITE_CONVEX_URL` or `NEXT_PUBLIC_CONVEX_URL` — Auto-set by `npx convex dev`

## Key Patterns

### Triggering Agents from Convex
See `references/agent-from-convex.md` for the complete pattern: Convex actions calling Subconscious SDK, async runs with webhook callbacks, agent run tracking, and structured output with Zod.

### HTTP Tool Endpoints
See `references/subconscious-integration.md` for HTTP action patterns, CORS helpers, tool schema requirements (CRITICAL: `additionalProperties: false`), webhook endpoints, MCP tools, tool headers, and the `defaults` pattern.

### Real-Time Data
See `references/realtime-patterns.md` for schema design, query/mutation patterns, reactive UI with useQuery/useAction, Vite and Next.js provider setup, and optimistic updates.

### Auth Setup (Next.js Only)
See `references/auth-nextjs.md` for Convex Auth with Password provider, JWT key generation, middleware, and all required auth files.

### Common Pitfalls
See `references/common-pitfalls.md` for every bug encountered with solutions.

## Critical Rules

1. **`additionalProperties: false`** — ALL Subconscious tool parameter schemas MUST include this. Without it, the agent gets stuck in a "Tinkering" loop.

2. **HTTP actions use `ctx.runMutation`** — They cannot use `ctx.db` directly. Use `internal.*` for mutations you don't want exposed as public API.

3. **Actions (not mutations) call external APIs.** Mutations are pure DB operations. Calling Subconscious must be inside an `action` or `internalAction`.

4. **`process.env.CONVEX_SITE_URL`** is always available in Convex functions — use it to construct tool callback URLs.

5. **HTTP tool body format** — Subconscious sends tool parameters **directly** in the POST body (e.g. `{ name: "test" }`). Read params from the top-level body in your HTTP action.

6. **Auth on AI-called mutations** — Mutations called by Subconscious via HTTP tool routes don't have user auth context. Enforce auth upstream (in the action that triggers the AI), keep the mutations themselves permissive. Use `internalMutation` to prevent direct client calls.

7. **`defaults` field** — Values in `defaults` MUST be defined in `parameters.properties` and should NOT be in the `required` array.

8. **For Next.js auth**: Middleware MUST be at `src/middleware.ts` (not project root) if using `src/` directory. Need BOTH `ConvexAuthNextjsServerProvider` (layout.tsx) AND `ConvexAuthNextjsProvider` (client provider). Requires `convex/auth.config.ts` or `isAuthenticated` is always `false`.

## Available Engines

| Engine | API Name | Type | Best For |
|--------|----------|------|----------|
| TIM | `tim` | Unified | Flagship unified agent for a wide range of tasks |
| TIM-Edge | `tim-edge` | Unified | Speed, efficiency, search-heavy tasks |
| TIMINI | `timini` | Compound (Gemini-3 Flash) | Long-context and tool use, strong reasoning |
| TIM-GPT | `tim-gpt` | Compound (GPT-4.1) | Most use cases, good balance of cost/performance |
| TIM-GPT-Heavy | `tim-gpt-heavy` | Compound (GPT-5.2) | Maximum capability, complex reasoning |

**Recommendation**: Start with `tim-gpt` for most applications.

## File Structure

```
my-app/
├── convex/
│   ├── schema.ts          # DB schema
│   ├── http.ts            # HTTP actions (tool endpoints + webhooks)
│   ├── items.ts           # queries + internal mutations for items
│   ├── agentRuns.ts       # queries + internal mutations for run tracking
│   └── agent.ts           # Convex action that calls Subconscious
├── src/
│   ├── main.tsx           # ConvexProvider wrapper
│   └── App.tsx            # useQuery / useAction hooks
├── .env.local             # VITE_CONVEX_URL (written by npx convex dev)
└── package.json
```

The `SUBCONSCIOUS_API_KEY` lives in Convex deployment env vars (set via CLI), **not** in `.env.local`. Frontend never sees it.
