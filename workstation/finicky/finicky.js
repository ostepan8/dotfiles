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
// NOTE: none of this takes effect until Finicky is actually the DEFAULT
// http/https handler -- installing the cask is not enough, and the failure is
// silent: links keep working, they just land in the last-touched profile again.
// setup.d/40-default-browser.sh registers it and re-checks on every install.
//
// __PERSONAL_PROFILE__ / __WORK_PROFILE__ are substituted at apply time by
// resolving the ACCOUNT, never a hardcoded directory: Chrome assigns profile
// directories in creation order, so ohstep23@gmail.com is "Default" on the
// Studio and "Profile 1" on the MacBook. See workstation/skhd/chrome-profile.sh,
// which learned this the hard way and is reused here rather than reimplemented.

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
    // to the browser. Resident also matters for the fn override below: a cold
    // start can take long enough that the key is released before the handler
    // asks whether it is down.
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
  // defaultBrowser. The work profile is still not routed by DOMAIN -- there is
  // one place deciding work vs personal, and it is the human at the keyboard.
  //
  //   { match: "*.subconscious.dev/*", browser: { name: "Google Chrome", profile: "Work" } }
  //   { match: /^https:\/\/meet\.google\.com/, browser: "Safari" }
  handlers: [
    {
      // Hold fn/Globe while opening a link -> work Chrome (owen@subconscious.dev,
      // the same account as skhd's Opt+W).
      //
      // Why fn and not opt, which would match Opt+W: Ghostty decides a click is
      // a link click by EXACT modifier equality (Surface.zig linkAtPin ->
      // `v.equal(mods)`), so cmd+shift+opt+click is not a link click at all --
      // the click does nothing and Finicky is never consulted. Same for ctrl
      // and for caps lock, which the macOS apprt reports as GHOSTTY_MODS_CAPS.
      // fn is the only modifier missing from Ghostty's Mods bitmask entirely,
      // so it passes the equality check while still reaching NSEvent, which is
      // where finicky.getModifierKeys() reads it from.
      //
      // Modifier state is sampled when Finicky handles the URL, a beat AFTER
      // the click, so keep fn held until the window appears.
      match: () => finicky.getModifierKeys().fn,
      browser: {
        name: "Google Chrome",
        // A profile DIRECTORY, not a display name, unlike the personal profile
        // above. Three profiles on this machine share the display name
        // "subconscious.dev" and Finicky resolves names by iterating a Go map,
        // so a name here picks one of the three at random -- including ones
        // with no account signed in. Directory lookup is its fallback path and
        // is exact. See lib/render/workstation-finicky-finicky.sh.
        profile: "__WORK_PROFILE__",
      },
    },
  ],
};
