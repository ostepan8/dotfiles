// Finicky — the URL router that sits in front of every link this machine opens.
//
// GENERATED from workstation/finicky/finicky.js by lib/render/. Edit the repo
// source, not ~/.finicky.js.
//
// Why this layer exists at all: Chrome cannot be told which profile an incoming
// link should use. It reuses whichever profile window you touched last, so a
// link from tmux lands in the work account about half the time. Finicky is
// registered as the https/http handler instead, so `open <url>` from anywhere
// -- tmux prefix+u, Ghostty's cmd+shift+click, Slack, Mail -- is dispatched
// here and pinned to one profile. Ghostty has no opener setting of its own
// (its `link` config is documented "can't currently be set"), so the OS-level
// handler is the only place this decision can be made.
//
// __PERSONAL_PROFILE__ is substituted at apply time by resolving the ACCOUNT,
// never a hardcoded directory: Chrome assigns profile directories in creation
// order, so ohstep23@gmail.com is "Default" on the Studio and "Profile 1" on
// the MacBook. See workstation/skhd/chrome-profile.sh, which learned this the
// hard way and is reused here rather than reimplemented.

export default {
  // Same account as skhd's Opt+B (ohstep23@gmail.com).
  defaultBrowser: {
    name: "Google Chrome",
    profile: "__PERSONAL_PROFILE__",
  },

  options: {
    // No auto-update nagging from a background URL router.
    checkForUpdates: false,
    // Stay resident. Without this Finicky exits as soon as its window closes,
    // so every single link pays a cold start and flashes a window on the way
    // to the browser.
    keepRunning: true,
    // No Dock icon for something that is only ever a dispatcher.
    hideIcon: true,
    // Flip to true, re-apply, then read ~/Library/Logs/Finicky/ to see what a
    // link actually matched when a rule below is not firing. Worth knowing:
    // with NO usable config Finicky silently falls back to Safari, so "my
    // links started opening in Safari" means this file failed to parse.
    logRequests: false,
  },

  // Per-URL overrides, first match wins; anything unmatched falls through to
  // defaultBrowser. The work profile is deliberately NOT routed by rule -- use
  // skhd's Opt+W for that, so there is one place deciding work vs personal.
  //
  //   { match: "*.subconscious.dev/*", browser: { name: "Google Chrome", profile: "Work" } }
  //   { match: /^https:\/\/meet\.google\.com/, browser: "Safari" }
  handlers: [],
};
