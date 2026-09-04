# Convex Auth with Next.js App Router — Complete Setup

This is the complete, battle-tested auth setup for Convex Auth with the Password provider in a Next.js App Router project using the `src/` directory convention.

## Step 1: Generate JWT Keys

Run this script ONCE to generate RS256 keys, then set them as Convex environment variables:

```bash
# Generate keys
node -e "
const { generateKeyPairSync } = require('crypto');
const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  publicKeyEncoding: { type: 'spki', format: 'pem' },
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
});
const jwk = require('crypto').createPublicKey(publicKey).export({ format: 'jwk' });
jwk.use = 'sig';
jwk.alg = 'RS256';
console.log('PRIVATE KEY:');
console.log(privateKey);
console.log('JWKS:');
console.log(JSON.stringify({ keys: [jwk] }));
"
```

Set the environment variables (use `--` before the value to prevent flag parsing):

```bash
npx convex env set JWT_PRIVATE_KEY -- "<PEM-HEADER-LINE>
...paste key here...
-----END PRIVATE KEY-----"

npx convex env set JWKS '{"keys":[{"use":"sig","kty":"RSA","n":"...","e":"AQAB","alg":"RS256"}]}'

npx convex env set SITE_URL http://localhost:3000
```

Note: `CONVEX_SITE_URL` is a built-in env var — do NOT try to set it manually.

## Step 2: Backend Files

### `convex/auth.ts`
```typescript
import { convexAuth } from "@convex-dev/auth/server";
import { Password } from "@convex-dev/auth/providers/Password";

export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  providers: [Password],
});
```

CRITICAL: Export `isAuthenticated` — without it, the `Authenticated`/`Unauthenticated` components from `convex/react` won't work.

### `convex/auth.config.ts`
```typescript
export default {
  providers: [
    {
      domain: process.env.CONVEX_SITE_URL,
      applicationID: "convex",
    },
  ],
};
```

This file tells the Convex backend how to validate JWT tokens. Without it, tokens are issued but `isAuthenticated` is always `false`.

### `convex/schema.ts` (auth portion)
```typescript
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { authTables } from "@convex-dev/auth/server";

export default defineSchema({
  ...authTables,  // Adds users, authSessions, authAccounts, etc.

  // Your tables with userId for per-user data
  reports: defineTable({
    title: v.string(),
    userId: v.id("users"),
    createdAt: v.number(),
  }).index("by_userId", ["userId"]),
});
```

### `convex/http.ts`
```typescript
import { httpRouter } from "convex/server";
import { auth } from "./auth";

const http = httpRouter();
auth.addHttpRoutes(http);  // Registers auth endpoints on .convex.site

// ... your other HTTP routes
export default http;
```

## Step 3: Frontend Files

### `src/middleware.ts` (MUST be in `src/` if using `src/` directory)

```typescript
import {
  convexAuthNextjsMiddleware,
  createRouteMatcher,
  nextjsMiddlewareRedirect,
} from "@convex-dev/auth/nextjs/server";

const isSignInPage = createRouteMatcher(["/sign-in"]);
const isProtectedRoute = createRouteMatcher(["/dashboard(.*)", "/report(.*)"]);

export default convexAuthNextjsMiddleware(
  async (request, { convexAuth }) => {
    if (isSignInPage(request) && (await convexAuth.isAuthenticated())) {
      return nextjsMiddlewareRedirect(request, "/dashboard");
    }
    if (isProtectedRoute(request) && !(await convexAuth.isAuthenticated())) {
      return nextjsMiddlewareRedirect(request, "/sign-in");
    }
  },
);

export const config = {
  matcher: ["/((?!.*\\..*|_next).*)", "/", "/(api|trpc)(.*)"],
};
```

CRITICAL: If your app directory is `src/app/`, the middleware MUST be at `src/middleware.ts`, NOT at the project root. A middleware at the project root will NOT intercept requests — the POST to `/api/auth` will 404.

### `src/app/layout.tsx`
```typescript
import { ConvexAuthNextjsServerProvider } from "@convex-dev/auth/nextjs/server";
import ConvexClientProvider from "@/components/ConvexClientProvider";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <ConvexAuthNextjsServerProvider>
      <html lang="en">
        <body>
          <ConvexClientProvider>
            {children}
          </ConvexClientProvider>
        </body>
      </html>
    </ConvexAuthNextjsServerProvider>
  );
}
```

`ConvexAuthNextjsServerProvider` is an async Server Component. It reads cookies and passes initial auth state to the client provider. It wraps `<html>` — NOT inside `<body>`.

### `src/components/ConvexClientProvider.tsx`
```typescript
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

CRITICAL: Use `ConvexAuthNextjsProvider` from `@convex-dev/auth/nextjs` — NOT `ConvexAuthProvider` from `@convex-dev/auth/react`. The generic React provider doesn't integrate with Next.js cookies/middleware. The `signIn` function will POST to `/api/auth` (handled by middleware) instead of calling Convex directly.

## Step 4: Sign-In Page

```typescript
"use client";

import { useState, useEffect } from "react";
import { useAuthActions } from "@convex-dev/auth/react";
import { useConvexAuth } from "convex/react";
import { useRouter } from "next/navigation";

export default function SignInPage() {
  const { signIn } = useAuthActions();
  const { isAuthenticated, isLoading } = useConvexAuth();
  const router = useRouter();
  const [flow, setFlow] = useState<"signIn" | "signUp">("signIn");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Redirect when authenticated
  useEffect(() => {
    if (!isLoading && isAuthenticated) {
      router.replace("/dashboard");
    }
  }, [isLoading, isAuthenticated, router]);

  if (isLoading || isAuthenticated) {
    return <div>Loading...</div>;
  }

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);

    const formData = new FormData(e.currentTarget);
    formData.set("flow", flow);  // "signIn" or "signUp"

    try {
      const result = await signIn("password", formData);
      if (result.signingIn) {
        // Success — useEffect will handle redirect when isAuthenticated changes
        return;
      }
      setError("Authentication failed.");
      setIsSubmitting(false);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Something went wrong.");
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit}>
      <input name="email" type="email" required />
      <input name="password" type="password" required minLength={8} />
      <button type="submit" disabled={isSubmitting}>
        {flow === "signIn" ? "Sign In" : "Create Account"}
      </button>
    </form>
  );
}
```

Key points:
- `signIn("password", formData)` returns `{ signingIn: boolean }` — does NOT throw on auth failure
- Use `router.replace` (client-side navigation) — NOT `window.location.href` (destroys SPA state)
- The `flow` field in FormData must be `"signIn"` or `"signUp"` — this tells the Password provider which operation to perform
- Let the `useEffect` handle redirects after `isAuthenticated` changes — don't redirect in the handler

## Step 5: Auth Guard Component

```typescript
"use client";

import { useConvexAuth } from "convex/react";

export default function AuthGuard({ children }: { children: React.ReactNode }) {
  const { isAuthenticated, isLoading } = useConvexAuth();

  if (isLoading) return <div>Loading...</div>;
  if (!isAuthenticated) return <div>Redirecting...</div>;
  return <>{children}</>;
}
```

Use `useConvexAuth()` hook directly — NOT `Authenticated`/`Unauthenticated`/`AuthLoading` wrapper components from `convex/react`. The hook is more reliable with `ConvexAuthNextjsProvider`. The middleware handles the actual redirect; the guard is just a UI fallback.

## Step 6: Per-User Data Queries

```typescript
import { query } from "./_generated/server";
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

## Auth with AI Tool Routes

Mutations called by Subconscious AI via HTTP tool routes do NOT have user auth context (the HTTP request comes from Subconscious, not the user's browser). Auth is enforced upstream — the Next.js API route or Convex action verifies report ownership before triggering the AI agent. The mutations themselves stay permissive.

```typescript
// This mutation is called by BOTH authenticated users AND Subconscious AI
export const updateStep = mutation({
  args: { reportId: v.id("reports"), stepId: v.string(), content: v.string() },
  handler: async (ctx, args) => {
    // NO auth check here — Subconscious calls this via HTTP
    // Auth enforced upstream in the sendChatMessage action
    const step = await ctx.db.query("deSteps")
      .withIndex("by_report_stepId", (q) =>
        q.eq("reportId", args.reportId).eq("stepId", args.stepId))
      .unique();
    if (!step) throw new Error("Step not found");
    await ctx.db.patch(step._id, { content: JSON.parse(args.content) });
  },
});
```
