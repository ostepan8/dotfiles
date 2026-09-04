# Common Pitfalls — Convex + Subconscious + Next.js

Every bug encountered during development, documented with symptoms and solutions.

## Auth Pitfalls

### 1. `isAuthenticated` is always `false` after sign-in
**Symptom:** User signs in, `signIn()` succeeds, but `useConvexAuth().isAuthenticated` never becomes `true`. Infinite loading spinner.

**Cause:** Missing `convex/auth.config.ts` file.

**Fix:** Create the file:
```typescript
// convex/auth.config.ts
export default {
  providers: [{
    domain: process.env.CONVEX_SITE_URL,
    applicationID: "convex",
  }],
};
```

### 2. POST to `/api/auth` returns 404
**Symptom:** Sign-in form submits, network tab shows `POST /api/auth 404 (Not Found)`, error: `SyntaxError: Unexpected token '<', "<!DOCTYPE"...`

**Cause:** Middleware file in wrong location.

**Fix:** If your app uses `src/app/`, the middleware MUST be at `src/middleware.ts`, NOT at the project root `middleware.ts`. Next.js only picks up middleware at the same level as your `app` directory.

### 3. Wrong auth provider import
**Symptom:** Sign-in works on the backend (Convex logs show `createAccountFromCredentials` success) but the client never becomes authenticated.

**Cause:** Using `ConvexAuthProvider` from `@convex-dev/auth/react` instead of `ConvexAuthNextjsProvider` from `@convex-dev/auth/nextjs`.

**Fix:**
```typescript
// WRONG
import { ConvexAuthProvider } from "@convex-dev/auth/react";

// CORRECT
import { ConvexAuthNextjsProvider } from "@convex-dev/auth/nextjs";
```

### 4. Missing `isAuthenticated` export
**Symptom:** `Authenticated`/`Unauthenticated` components from `convex/react` don't work.

**Cause:** `convex/auth.ts` doesn't export `isAuthenticated`.

**Fix:**
```typescript
export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  providers: [Password],
});
```

### 5. Missing `ConvexAuthNextjsServerProvider` wrapper
**Symptom:** Auth works inconsistently. SSR doesn't have auth state. Middleware can't check authentication.

**Fix:** Wrap the `<html>` element in `layout.tsx`:
```typescript
import { ConvexAuthNextjsServerProvider } from "@convex-dev/auth/nextjs/server";

export default function RootLayout({ children }) {
  return (
    <ConvexAuthNextjsServerProvider>
      <html>
        <body><ConvexClientProvider>{children}</ConvexClientProvider></body>
      </html>
    </ConvexAuthNextjsServerProvider>
  );
}
```

### 6. `window.location.href` destroys auth state
**Symptom:** After sign-in, redirect to dashboard causes another auth loading cycle because the Convex client is re-created.

**Cause:** Using `window.location.href` (hard page navigation) instead of `router.push` (SPA client-side navigation).

**Fix:** Always use Next.js `router.replace("/dashboard")` — this preserves the in-memory Convex client with its authenticated state.

### 7. Hydration mismatch with `window.location.pathname`
**Symptom:** React hydration error mentioning mismatched text content.

**Cause:** Accessing `window.location.pathname` during SSR (server returns `—`, client returns `/sign-in`).

**Fix:** Guard browser APIs with `useEffect` + `useState`:
```typescript
const [pathname, setPathname] = useState("—");
useEffect(() => setPathname(window.location.pathname), []);
```

### 8. JWT key flag parsing error
**Symptom:** `npx convex env set JWT_PRIVATE_KEY -----BEGIN...` fails with flag parsing error.

**Fix:** Use `--` to stop flag parsing:
```bash
npx convex env set JWT_PRIVATE_KEY -- "<PEM-HEADER-LINE>
...
-----END PRIVATE KEY-----"
```

### 9. `CONVEX_SITE_URL` is read-only
**Symptom:** `npx convex env set CONVEX_SITE_URL ...` fails with "built-in and cannot be overridden".

**Explanation:** `CONVEX_SITE_URL` is automatically set by Convex to your `*.convex.site` URL. Use it directly in `auth.config.ts` — don't try to set it.

## Subconscious Pitfalls

### 10. Agent stuck in "Tinkering" loop
**Symptom:** Subconscious agent runs but never completes. Keeps generating tool calls without executing them.

**Cause:** Missing `additionalProperties: false` in tool parameter schemas.

**Fix:** Add to EVERY tool definition:
```typescript
parameters: {
  type: "object",
  properties: { /* ... */ },
  required: ["stepId"],
  additionalProperties: false,  // CRITICAL
}
```

### 11. Tool receives empty/wrong params
**Symptom:** Convex HTTP endpoint receives `undefined` for expected parameters.

**Cause:** Reading params from wrong path (e.g. `body.parameters` instead of top-level body).

**Fix:** Subconscious sends tool parameters directly in the POST body. Read them from the top level:
```typescript
const body = await request.json();
const name = body.name as string;  // Parameters are top-level fields
```

### 12. `defaults` key not in properties
**Symptom:** Subconscious API returns validation error about defaults.

**Cause:** A key in `defaults` is not defined in `parameters.properties`.

**Fix:** Every default key must appear in properties:
```typescript
parameters: {
  properties: {
    reportId: { type: "string", description: "Report ID" },  // Must exist
  },
  required: [],  // reportId NOT in required
  additionalProperties: false,
},
defaults: { reportId: "abc123" },  // OK because reportId is in properties
```

## Convex Pitfalls

### 13. Schema push fails with existing data
**Symptom:** `npx convex dev` fails when adding a required field to an existing table.

**Fix:** For dev: clear the table data first using the Convex dashboard or:
```bash
printf '' > /tmp/empty.jsonl
npx convex import --table reports --replace --yes /tmp/empty.jsonl
```

### 14. Queries in actions
**Symptom:** Trying to use `ctx.db.query(...)` inside an `action` fails.

**Cause:** Actions cannot directly access the database.

**Fix:** Use `ctx.runQuery` and `ctx.runMutation`:
```typescript
export const myAction = action({
  handler: async (ctx) => {
    const data = await ctx.runQuery(api.myModule.myQuery, { arg: "value" });
    await ctx.runMutation(api.myModule.myMutation, { arg: "value" });
  },
});
```

### 15. Real-time updates not working for AI-written data
**Symptom:** When the Subconscious agent writes data via HTTP tool endpoints, the frontend doesn't update.

**Cause:** Not using Convex mutations. HTTP actions that write directly bypass the reactive system.

**Fix:** HTTP actions should use `ctx.runMutation` to write data, not direct DB access. This ensures subscriptions fire:
```typescript
// In httpAction:
await ctx.runMutation(api.deSteps.updateStep, { reportId, stepId, content });
// This triggers useQuery subscriptions on the frontend
```

### 16. Using `ctx.db` in HTTP actions
**Symptom:** TypeScript error or runtime error when trying to query/insert in an HTTP action.

**Cause:** HTTP actions cannot use `ctx.db` directly.

**Fix:** Use `ctx.runQuery`, `ctx.runMutation`, or `ctx.runAction`:
```typescript
// WRONG: ctx.db.insert(...) inside httpAction
// CORRECT:
await ctx.runMutation(internal.items.create, { name: "test" });
```

### 17. Calling Subconscious from a mutation
**Symptom:** Error when trying to `fetch` or use the Subconscious SDK inside a mutation.

**Cause:** Mutations are pure DB operations — no side effects allowed.

**Fix:** Use an `action` or `internalAction` for external API calls:
```typescript
// WRONG: mutation with fetch
export const bad = mutation({ handler: async (ctx) => {
  await fetch("https://..."); // Error!
}});

// CORRECT: action with fetch
export const good = action({ handler: async (ctx) => {
  await fetch("https://...");
  await ctx.runMutation(internal.items.create, { name: "test" });
}});
```

### 18. `SUBCONSCIOUS_API_KEY` not available in Convex
**Symptom:** `process.env.SUBCONSCIOUS_API_KEY` is `undefined` in Convex actions.

**Cause:** Key set in `.env.local` instead of the Convex deployment.

**Fix:** Set it via CLI:
```bash
npx convex env set SUBCONSCIOUS_API_KEY your_api_key_here
npx convex env list  # verify
```

### 19. `process.env.CONVEX_SITE_URL` not working
**Symptom:** Tool URLs are wrong or undefined when building tool definitions in Convex actions.

**Cause:** Using the wrong env var name, or trying to set it manually.

**Fix:** `process.env.CONVEX_SITE_URL` is built-in and always available in Convex functions. Don't try to set it — just use it:
```typescript
const siteUrl = process.env.CONVEX_SITE_URL!; // https://your-deployment.convex.site
```

### 20. Webhook not receiving callbacks
**Symptom:** Async Subconscious run completes but webhook endpoint never fires.

**Cause:** Missing webhook route in `http.ts`, or wrong `callbackUrl`.

**Fix:** Ensure the route is registered AND the URL matches:
```typescript
// In convex/http.ts
http.route({
  path: "/webhooks/subconscious",
  method: "POST",
  handler: httpAction(async (ctx, request) => { /* ... */ }),
});

// In agent action
output: {
  callbackUrl: `${process.env.CONVEX_SITE_URL}/webhooks/subconscious`,
}
```

## Debugging Checklist

When auth isn't working:
1. Check Convex logs: `npx convex logs --follow` — are auth functions executing?
2. Check browser Network tab: is POST to `/api/auth` returning 200?
3. Check browser console: what do `isLoading` and `isAuthenticated` say?
4. Verify all 7 required files exist (see SKILL.md checklist)
5. Verify env vars: `npx convex env list` — are JWT_PRIVATE_KEY, JWKS, SITE_URL set?
6. Clear browser state: `localStorage.clear()` + clear cookies + hard refresh

When Subconscious tools aren't working:
1. Test HTTP endpoint directly with `curl` (params go directly in body):
   ```bash
   curl -X POST https://your-deployment.convex.site/tools/list-steps \
     -H "Content-Type: application/json" \
     -d '{"reportId": "abc123"}'
   ```
2. Check Convex function logs for errors: `npx convex logs --follow`
3. Verify `additionalProperties: false` on ALL tool schemas
4. Check `defaults` keys match `properties` keys
5. Verify the Convex site URL is correct in tool URLs
