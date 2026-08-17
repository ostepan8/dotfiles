#!/usr/bin/env bash
# engine.sh — reads manifest.conf and puts each file where it belongs.
#
# One engine for every machine and every entry point, replacing the three
# hand-rolled copy lists that had drifted apart. Adding a config file is a new
# manifest row, not new code in three scripts.
#
# Requires: $DOTFILES (repo root). Honours $DRY_RUN=1 (report, change nothing).

# ---------------------------------------------------------------------------
# layer resolution
# ---------------------------------------------------------------------------

# Machine type comes from ~/.dotfiles-host — the marker that already exists and
# is already documented in zsh/zshrc. No second marker file.
resolve_layers() {
  local host_file="$HOME/.dotfiles-host" host="" layers=""
  [ -f "$host_file" ] && host="$(tr -d '[:space:]' < "$host_file")"

  if [ -n "$host" ]; then
    layers="$(awk -v h="$host" '!/^[[:space:]]*#/ && $1 == h { $1=""; print; exit }' \
      "$DOTFILES/hosts/layers.conf")"
  fi

  if [ -z "${layers// /}" ]; then
    # Safe default: a machine we do not recognise gets a working shell, git,
    # tmux and Claude, and nothing GUI is ever attempted on a headless box.
    [ -n "$host" ] \
      && echo "  WARN: host type '$host' not in hosts/layers.conf — applying base only" >&2 \
      || echo "  WARN: no ~/.dotfiles-host — applying base only" >&2
    layers="base"
  fi
  echo "$layers" | tr -s ' ' | sed 's/^ *//;s/ *$//'
}

layer_active() {
  local want="$1" l
  for l in $ACTIVE_LAYERS; do [ "$l" = "$want" ] && return 0; done
  return 1
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

expand_home() { printf '%s' "${1/#\~/$HOME}"; }

# Renderers are keyed by a slug of the source path: '/' -> '-', extension
# stripped. clangd/config.yaml -> lib/render/clangd-config.sh
render_slug() {
  local s="${1#"$DOTFILES"/}"   # accept absolute or repo-relative
  s="${s//\//-}"
  printf '%s' "${s%.*}"
}

note()   { echo "  $*"; }
action() { CHANGES=$((CHANGES + 1)); echo "  $*"; }

# Back up a pre-existing real file once, so a first apply on a machine that was
# set up by hand never destroys what was there. Mirrors the old scripts'
# .backup behaviour, generalised to every managed path.
backup_once() {
  local dest="$1"
  [ -L "$dest" ] && return 0          # already ours
  [ -e "$dest" ] || return 0
  [ -e "$dest.backup" ] && return 0
  [ "${DRY_RUN:-0}" = "1" ] || cp -R "$dest" "$dest.backup"
  note "backed up existing $dest -> $dest.backup"
}

# ---------------------------------------------------------------------------
# modes
# ---------------------------------------------------------------------------

apply_link() {
  local src="$1" dest="$2"
  # Already correct? Do nothing — an idle apply must be silent.
  [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ] && return 0
  backup_once "$dest"
  [ "${DRY_RUN:-0}" = "1" ] && { action "link   $dest"; return 0; }
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  ln -s "$src" "$dest"
  action "link   $dest"
}

apply_exec() {
  apply_link "$1" "$2"
  [ "${DRY_RUN:-0}" = "1" ] || chmod +x "$1" 2>/dev/null || true
}

# copy, gated on the source hash having moved. Reverting a runtime-mutated file
# on every idle tick is exactly the bug this gate exists to prevent.
apply_copy() {
  local src="$1" dest="$2" tag="copy:$2"
  changed "$tag" "$src" || return 0
  [ "${DRY_RUN:-0}" = "1" ] && { action "copy   $dest"; return 0; }
  mkdir -p "$(dirname "$dest")"
  backup_once "$dest"
  cp -f "$src" "$dest"
  action "copy   $dest"
}

apply_seed() {
  local src="$1" dest="$2"
  [ -e "$dest" ] && return 0
  [ "${DRY_RUN:-0}" = "1" ] && { action "seed   $dest"; return 0; }
  mkdir -p "$(dirname "$dest")"
  cp -f "$src" "$dest"
  action "seed   $dest (machine-specific from here on)"
}

apply_tree() {
  local src="$1" dest="$2"
  [ -d "$src" ] || { note "SKIP   $src (not a directory)"; return 0; }
  [ "${DRY_RUN:-0}" = "1" ] && {
    diff -rq "$src" "$dest" >/dev/null 2>&1 || action "tree   $dest"
    return 0
  }
  mkdir -p "$dest"
  if diff -rq "$src" "$dest" >/dev/null 2>&1; then return 0; fi
  cp -R "$src/." "$dest/"
  action "tree   $dest"
}

apply_render() {
  local src="$1" dest="$2"
  local script="$DOTFILES/lib/render/$(render_slug "$src").sh"
  [ -f "$script" ] || { note "SKIP   render $src (no $script)"; return 0; }
  # $src is already absolute (apply_manifest resolves it).
  RENDER_SRC="$src" RENDER_DEST="$dest" DRY_RUN="${DRY_RUN:-0}" bash "$script"
}

# launchd agents. Skipped entirely on non-macOS.
apply_agent() {
  local src="$1" destdir="$2"
  command -v launchctl >/dev/null 2>&1 || return 0
  local base dest
  base="$(basename "$src")"
  dest="$destdir$base"

  # Unchanged? Do not touch. Reloading an unchanged agent every tick was
  # restarting the display-watcher, which re-fired set-main-display.sh,
  # restarting sketchybar and retiling aerospace for no reason.
  cmp -s "$src" "$dest" && return 0
  [ "${DRY_RUN:-0}" = "1" ] && { action "agent  $dest"; return 0; }

  mkdir -p "$destdir"
  cp -f "$src" "$dest"
  action "agent  $dest"

  # NO_RELOAD=1 keeps the hermetic verifier from registering agents with the
  # real launchd when it runs against a redirected HOME.
  [ "${NO_RELOAD:-0}" = "1" ] && return 0

  # The sync agent's own plist is never unloaded here: sync.sh runs apply as a
  # child of the process launchd is supervising FOR THAT AGENT, so unloading it
  # would SIGTERM this very script mid-apply, silently truncating every
  # scheduled sync. The copied plist takes effect on its next natural relaunch.
  [ "$base" = "com.ostepan.dotfiles-sync.plist" ] && return 0

  launchctl unload "$dest" 2>/dev/null || true
  launchctl load   "$dest" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

apply_manifest() {
  local manifest="$DOTFILES/manifest.conf"
  [ -f "$manifest" ] || { echo "no manifest at $manifest" >&2; return 1; }

  CHANGES=0
  local -a reload_tags=()
  local layer mode source dest reload

  while read -r layer mode source dest reload; do
    case "$layer" in ''|\#*) continue ;; esac
    layer_active "$layer" || continue

    dest="$(expand_home "$dest")"

    # A glob source fans out into a destination directory.
    if [[ "$source" == *"*"* ]]; then
      local f
      for f in "$DOTFILES"/$source; do
        [ -e "$f" ] || continue
        apply_"$mode" "$f" "$dest$(basename "$f")"
      done
    else
      local abs="$DOTFILES/$source"
      if [ ! -e "$abs" ]; then
        note "SKIP   $source (missing)"
        continue
      fi
      case "$mode" in
        agent) apply_agent "$abs" "$dest" ;;
        *)     apply_"$mode" "$abs" "$dest" ;;
      esac
    fi

    [ "$reload" != "-" ] && reload_tags+=("$reload:$source")
  done < "$manifest"

  fire_reloads "${reload_tags[@]:-}"
}

# Reloads fire once per tag, only when that tag's sources actually changed.
fire_reloads() {
  local entry tag tags="" srcs
  for entry in "$@"; do
    [ -z "$entry" ] && continue
    tag="${entry%%:*}"
    case " $tags " in *" $tag "*) continue ;; esac
    tags="$tags $tag"

    # Availability BEFORE `changed` — see is_reload_available in reloads.sh.
    is_reload_available "$tag" || continue

    # Sources may be globs (sketchybar/plugins/*.sh). Expand them here, or the
    # hash is taken over a literal '*' path that never exists — which makes the
    # tag look changed on every single run and reloads a service that did not
    # move.
    srcs=()
    local e pat f
    for e in "$@"; do
      [ "${e%%:*}" = "$tag" ] || continue
      pat="${e#*:}"
      for f in $DOTFILES/$pat; do
        [ -e "$f" ] && srcs+=("$f")
      done
    done
    # shellcheck disable=SC2086
    changed "$tag" ${srcs[@]+"${srcs[@]}"} || continue

    if [ "${DRY_RUN:-0}" = "1" ] || [ "${NO_RELOAD:-0}" = "1" ]; then
      echo "  would reload $tag"
      continue
    fi
    echo "  reload $tag"
    run_reload "$tag"
  done
}
