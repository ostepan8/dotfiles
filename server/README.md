# server layer

Overrides for headless machines: `fedora`, `gpu1`, `gpu2`, `onephus`.

**This is deliberately almost empty.** The restructure brief expected servers to
need their own trimmed-down configs, but they mostly don't — what a headless box
needs is the `base` layer, which it now actually gets. Before this change the
four Linux nodes received no Claude config at all (`linux/setup.sh` had zero
references to it), so the nephos skill, whose entire premise is that every
machine knows the personal cloud, existed on exactly one machine.

What does *not* belong here:

- **A second, minimal nvim config.** `base/nvim/init.lua` ships everywhere. What
  is expensive on a headless box is the plugin *bootstrap* — treesitter
  compiles, LSP servers — not the config file. Gate the heavy set on the layer
  inside `init.lua`; a parallel "lite" config only rots.
- **Anything GUI.** If a row would install a window manager, status bar, or
  hotkey daemon, it belongs in `workstation/`. `scripts/verify-apply.sh` asserts
  none of it reaches a headless host.

What would legitimately go here: a systemd user unit for the sync loop (the
Linux equivalent of `lib/agents/com.ostepan.dotfiles-sync.plist`, which is
launchd-only), or a shell tweak that only makes sense over SSH.
