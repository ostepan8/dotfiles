#!/usr/bin/env node
// Drive one of Owen's web apps as a signed-in user: a Chromium virtual
// authenticator holds Claude's passkey, and the page is phone-sized unless
// asked otherwise. Called by `app-login`, not by hand.
//
//   browser.mjs enroll <enroll-url>          create a passkey on the enrol page
//   browser.mjs shot <route> <out.png>       full-page screenshot of <origin>/#<route>
//   browser.mjs eval <route> <js expression> print the expression's JSON value
//   browser.mjs run <script.mjs>             default export gets { page, origin, shot }
//
// Environment (set by app-login):
//   APPLOGIN_ORIGIN   the app's origin
//   APPLOGIN_CRED     file holding the credentials JSON; rewritten after every run,
//                     because the sign counter moves and a stale one is refused
//   APPLOGIN_STATE    cookie jar file
//   APPLOGIN_WIDTH / APPLOGIN_HEIGHT   viewport (430x932 by default)
//   APPLOGIN_LABEL    passkey label for enroll (default "claude")
//   APPLOGIN_THEME    dark (default, like Owen's phone) or light
//   APPLOGIN_FULL     1 = full-page screenshots; default is the viewport, what a phone shows

import { createRequire } from "node:module";
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require(path.join(execSync("npm root -g").toString().trim(), "@playwright/test"));

const env = (k, d) => process.env[k] ?? d;
const ORIGIN = env("APPLOGIN_ORIGIN");
const CRED = env("APPLOGIN_CRED");
const STATE = env("APPLOGIN_STATE");
const WIDTH = Number(env("APPLOGIN_WIDTH", "430"));
const HEIGHT = Number(env("APPLOGIN_HEIGHT", "932"));
const PHONE = WIDTH < 900;
const THEME = env("APPLOGIN_THEME", "dark");
const FULL = env("APPLOGIN_FULL", "") === "1";
if (!ORIGIN || !CRED || !STATE) throw new Error("run this through app-login");

function save(file, data) {
  fs.writeFileSync(file, data, { mode: 0o600 });
  fs.chmodSync(file, 0o600);
}

async function open() {
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: WIDTH, height: HEIGHT }, deviceScaleFactor: 2, isMobile: PHONE, hasTouch: PHONE, colorScheme: THEME,
    storageState: fs.existsSync(STATE) ? STATE : undefined,
  });
  const page = await context.newPage();
  const errors = [];
  page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  page.on("pageerror", (e) => errors.push(String(e)));
  const cdp = await context.newCDPSession(page);
  await cdp.send("WebAuthn.enable");
  const { authenticatorId } = await cdp.send("WebAuthn.addVirtualAuthenticator", {
    options: {
      protocol: "ctap2", transport: "internal", hasResidentKey: true, hasUserVerification: true,
      isUserVerified: true, automaticPresenceSimulation: true,
    },
  });
  if (fs.existsSync(CRED) && fs.statSync(CRED).size > 0) {
    for (const credential of JSON.parse(fs.readFileSync(CRED, "utf8"))) {
      await cdp.send("WebAuthn.addCredential", { authenticatorId, credential });
    }
  }
  return { browser, context, page, cdp, authenticatorId, errors };
}

// Persist the credentials (with their new sign counts) and the cookies.
async function persist(s) {
  const { credentials } = await s.cdp.send("WebAuthn.getCredentials", { authenticatorId: s.authenticatorId });
  if (credentials.length) save(CRED, JSON.stringify(credentials));
  await s.context.storageState({ path: STATE });
  fs.chmodSync(STATE, 0o600);
}

// Land on a route signed in: if the gate shows, press the passkey button.
async function signedIn(s, route) {
  const url = `${ORIGIN}/#${route.replace(/^#?\/?/, "/")}`;
  await s.page.goto(url, { waitUntil: "networkidle" });
  const signIn = s.page.getByRole("button", { name: /Sign in with passkey/i });
  if (await signIn.isVisible().catch(() => false)) {
    await signIn.click();
    await s.page.waitForLoadState("networkidle");
    await s.page.goto(url, { waitUntil: "networkidle" });
    if (await signIn.isVisible().catch(() => false)) {
      throw new Error("still at the sign-in gate: the passkey was refused (revoked, or a fresh database — run `up` again)");
    }
  }
  await s.page.waitForTimeout(1200);
}

const [cmd, arg, extra] = process.argv.slice(2);
const s = await open();
let failed = false;
try {
  if (cmd === "enroll") {
    await s.page.goto(arg, { waitUntil: "networkidle" });
    await s.page.locator("#label").fill(env("APPLOGIN_LABEL", "claude"));
    await s.page.getByRole("button", { name: /Create passkey/i }).click();
    await s.page.waitForLoadState("networkidle");
    await s.page.waitForTimeout(2000);
    const { credentials } = await s.cdp.send("WebAuthn.getCredentials", { authenticatorId: s.authenticatorId });
    if (!credentials.length) {
      const alert = await s.page.getByRole("alert").textContent().catch(() => null);
      throw new Error(`no passkey was created${alert ? `: ${alert}` : ""}`);
    }
    console.log("enrolled");
  } else if (cmd === "shot") {
    await signedIn(s, arg ?? "");
    await s.page.screenshot({ path: extra, fullPage: FULL });
    console.log(extra);
  } else if (cmd === "eval") {
    await signedIn(s, arg ?? "");
    console.log(JSON.stringify(await s.page.evaluate(extra), null, 2));
  } else if (cmd === "run") {
    const mod = await import(pathToFileURL(path.resolve(arg)).href);
    await signedIn(s, "");
    const shot = async (out, opts = {}) => { await s.page.screenshot({ path: out, fullPage: FULL, ...opts }); console.log(out); };
    await mod.default({ page: s.page, origin: ORIGIN, shot, goto: (route) => signedIn(s, route) });
  } else {
    throw new Error("usage: browser.mjs enroll <url> | shot <route> <out> | eval <route> <js> | run <script.mjs>");
  }
  if (s.errors.length) console.error("console errors:\n" + s.errors.join("\n"));
} catch (e) {
  failed = true;
  console.error(String(e?.message ?? e));
} finally {
  await persist(s).catch((e) => console.error("could not save the credential:", e.message));
  await s.browser.close();
}
process.exit(failed ? 1 : 0);
