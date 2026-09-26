#!/usr/bin/env node
// Drive the production atlas PWA as a signed-in user, with Claude's own
// passkey held by a Chromium virtual authenticator.
//
//   node prod.mjs enroll '<enroll link from `contextd passkey enroll --label claude`>'
//   node prod.mjs shot <hash-route> [out.png]      e.g. money-history, money, home
//   node prod.mjs eval <hash-route> '<js expression>'
//
// The credential (a private key) lives in ~/.config/atlas/claude-passkey.json,
// mode 600, never in git or dotfiles. Revoke it with
// `contextd passkey revoke <id>` (see `contextd passkey ls`, label "claude").

import { createRequire } from "node:module";
import { execSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const require = createRequire(import.meta.url);
const { chromium } = require(path.join(execSync("npm root -g").toString().trim(), "@playwright/test"));

// The origin is private (dotfiles is public), so it comes from the env or ~/.config/atlas/env.
function readOrigin() {
  if (process.env.ATLAS_ORIGIN) return process.env.ATLAS_ORIGIN;
  const envFile = path.join(os.homedir(), ".config/atlas/env");
  const line = fs.existsSync(envFile) &&
    fs.readFileSync(envFile, "utf8").split("\n").find((l) => l.startsWith("ATLAS_ORIGIN="));
  if (!line) throw new Error(`ATLAS_ORIGIN not set and not found in ${envFile}`);
  return line.slice("ATLAS_ORIGIN=".length).trim().replace(/^["']|["']$/g, "");
}

const ORIGIN = readOrigin();
const CRED = path.join(os.homedir(), ".config/atlas/claude-passkey.json");
const STATE = path.join(os.homedir(), ".config/atlas/claude-session.json");

async function open() {
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: 430, height: 932 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    storageState: fs.existsSync(STATE) ? STATE : undefined,
  });
  const page = await context.newPage();
  const errors = [];
  page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  page.on("pageerror", (e) => errors.push(String(e)));
  const cdp = await context.newCDPSession(page);
  await cdp.send("WebAuthn.enable");
  const { authenticatorId } = await cdp.send("WebAuthn.addVirtualAuthenticator", {
    options: { protocol: "ctap2", transport: "internal", hasResidentKey: true, hasUserVerification: true, isUserVerified: true, automaticPresenceSimulation: true },
  });
  if (fs.existsSync(CRED)) {
    for (const credential of JSON.parse(fs.readFileSync(CRED, "utf8"))) {
      await cdp.send("WebAuthn.addCredential", { authenticatorId, credential });
    }
  }
  return { browser, context, page, cdp, authenticatorId, errors };
}

function save(file, data) {
  fs.writeFileSync(file, data, { mode: 0o600 });
  fs.chmodSync(file, 0o600);
}

// Land on a route signed in: if the gate shows, press the passkey button.
async function signedIn(s, route) {
  await s.page.goto(`${ORIGIN}/#${route}`, { waitUntil: "networkidle" });
  const signIn = s.page.getByRole("button", { name: /Sign in with passkey/ });
  if (await signIn.isVisible().catch(() => false)) {
    await signIn.click();
    await s.page.waitForLoadState("networkidle");
    await s.page.goto(`${ORIGIN}/#${route}`, { waitUntil: "networkidle" });
  }
  await s.page.waitForTimeout(1500);
  await s.context.storageState({ path: STATE });
  fs.chmodSync(STATE, 0o600);
}

const [cmd, arg, extra] = process.argv.slice(2);
const s = await open();
try {
  if (cmd === "enroll") {
    await s.page.goto(arg, { waitUntil: "networkidle" });
    await s.page.locator("#label").fill("claude");
    await s.page.getByRole("button", { name: "Create passkey" }).click();
    await s.page.waitForLoadState("networkidle");
    await s.page.waitForTimeout(2000);
    const alert = await s.page.getByRole("alert").textContent().catch(() => null);
    const { credentials } = await s.cdp.send("WebAuthn.getCredentials", { authenticatorId: s.authenticatorId });
    if (!credentials.length) throw new Error(`no credential was created${alert ? `: ${alert}` : ""}`);
    save(CRED, JSON.stringify(credentials));
    await s.context.storageState({ path: STATE });
    fs.chmodSync(STATE, 0o600);
    console.log(`enrolled; ${credentials.length} credential saved to ${CRED}`);
  } else if (cmd === "shot") {
    await signedIn(s, arg ?? "home");
    const out = extra ?? path.join(os.tmpdir(), `atlas-${(arg ?? "home").replace(/\W+/g, "-")}.png`);
    await s.page.screenshot({ path: out, fullPage: true });
    console.log(out);
  } else if (cmd === "eval") {
    await signedIn(s, arg ?? "home");
    console.log(JSON.stringify(await s.page.evaluate(extra), null, 2));
  } else {
    throw new Error("usage: prod.mjs enroll <link> | shot <route> [out.png] | eval <route> <js>");
  }
  if (s.errors.length) console.error("console errors:\n" + s.errors.join("\n"));
} finally {
  await s.browser.close();
}
