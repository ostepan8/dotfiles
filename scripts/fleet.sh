#!/usr/bin/env bash
# fleet.sh — bring every machine to the current commit, non-interactively.
#
#   ./scripts/fleet.sh                 update every reachable host (config only)
#   ./scripts/fleet.sh --dry-run       report what each host would change
#   ./scripts/fleet.sh --full          also install packages (slow, needs sudo)
#   ./scripts/fleet.sh gpu1 gpu2       only these hosts
#
# Non-interactive by construction:
#   - ssh BatchMode, so a host needing a password is reported, never hung on
#   - the host type is seeded from hosts/fleet.conf, so nothing has to be asked
#   - setup.d scripts skip themselves without a tty and report what they deferred
#
# One host failing never stops the rest — a fleet update that aborts halfway
# leaves machines in mixed states, which is worse than finishing and reporting.
set -uo pipefail

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DOTFILES" || exit 1

REPO_URL="https://github.com/ostepan8/dotfiles.git"
SSH_OPTS=(-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; YELLOW=""; DIM=""; OFF=""; }

DRY_RUN=0; FULL=0; ONLY=()
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --full)       FULL=1 ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    -*)           echo "unknown option: $arg" >&2; exit 2 ;;
    *)            ONLY+=("$arg") ;;
  esac
done

# The commit every host should end up on.
TARGET="$(git rev-parse HEAD)"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "${YELLOW}warning:${OFF} working tree is dirty — hosts will get the last commit,"
  echo "         not what is on disk here."
fi
if [ -n "$(git log origin/main..HEAD --oneline 2>/dev/null)" ]; then
  echo "${RED}error:${OFF} local commits are not pushed. Hosts pull from origin, so"
  echo "       they cannot reach $(git rev-parse --short HEAD). Push first."
  exit 1
fi

wanted_hosts() {
  awk '!/^[[:space:]]*#/ && NF == 2 { print $1, $2 }' "$DOTFILES/hosts/fleet.conf"
}

ok_hosts=(); failed_hosts=(); skipped_hosts=(); changed_hosts=(); bootstrap_hosts=()

update_host() {
  local alias="$1" type="$2" out rc

  # Remote script. Kept as one heredoc so the whole update is a single ssh
  # round trip — a per-step connection would multiply the failure surface.
  # NOTE ON THE HEREDOC: the closing ")" of the command substitution must come
  # AFTER the REMOTE terminator, not on the ssh line. With it on the ssh line the
  # substitution closes immediately and the heredoc body is parsed as part of
  # THIS script — it then runs locally, which is exactly as bad as it sounds.
  #
  # Values are passed as environment variables rather than positional args:
  # ssh flattens its command to a string that the remote shell re-splits, so
  # positional args are one quoting mistake away from silent misalignment.
  # Output goes to a temp file rather than $( ), because a heredoc inside a
  # command substitution forces bash to scan the body for the closing paren —
  # and `case` patterns like `dnf|zypper)` inside it break that scan with a
  # syntax error pointing at an unrelated line.
  local tmp; tmp="$(mktemp)"
  ssh "${SSH_OPTS[@]}" "$alias" \
    "TYPE='$type' TARGET='$TARGET' REPO_URL='$REPO_URL' DRY='$DRY_RUN' FULL='$FULL' bash -s" >"$tmp" 2>&1 <<'REMOTE'
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# Seed the machine type so no interview is needed. Never overwrite an existing
# marker — a machine that has been deliberately retyped keeps its own answer.
if [ ! -f "$HOME/.dotfiles-host" ]; then
  if [ "$DRY" = "1" ]; then echo "would set ~/.dotfiles-host=$TYPE"
  else printf '%s\n' "$TYPE" > "$HOME/.dotfiles-host"; echo "set ~/.dotfiles-host=$TYPE"; fi
elif [ "$(tr -d '[:space:]' < "$HOME/.dotfiles-host")" != "$TYPE" ]; then
  echo "NOTE: marker is '$(tr -d '[:space:]' < "$HOME/.dotfiles-host")', fleet.conf says '$TYPE' — leaving it alone"
fi

# Bare machine: no git means nothing below works. Try to install it without a
# password; if sudo wants one, say exactly what to run rather than hanging on a
# prompt that BatchMode ssh will never show.
if ! command -v git >/dev/null 2>&1; then
  if [ "$DRY" = "1" ]; then echo "would install git, then clone"; exit 0; fi
  PKG=""
  for p in dnf apt-get pacman zypper; do command -v $p >/dev/null 2>&1 && { PKG=$p; break; }; done
  if [ -z "$PKG" ]; then echo "NEEDS-BOOTSTRAP: no git and no known package manager"; exit 3; fi
  if sudo -n true 2>/dev/null; then
    case "$PKG" in
      dnf|zypper) sudo -n "$PKG" install -y git >/dev/null 2>&1 ;;
      apt-get)    sudo -n apt-get update -qq >/dev/null 2>&1 && sudo -n apt-get install -y -qq git >/dev/null 2>&1 ;;
      pacman)     sudo -n pacman -S --noconfirm git >/dev/null 2>&1 ;;
    esac
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "NEEDS-BOOTSTRAP: git is not installed and sudo requires a password."
    echo "  Run this once on this host, then re-run the fleet update:"
    echo "    sudo $PKG install -y git"
    exit 3
  fi
  echo "installed git"
fi

if [ ! -d "$HOME/dotfiles/.git" ]; then
  if [ "$DRY" = "1" ]; then echo "would clone $REPO_URL"; exit 0; fi
  git clone -q "$REPO_URL" "$HOME/dotfiles" || { echo "CLONE FAILED"; exit 1; }
  echo "cloned"
fi

cd "$HOME/dotfiles" || { echo "no repo dir"; exit 1; }

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "DIRTY working tree — refusing to touch it. Resolve by hand:"
  git status --short | head -5
  exit 1
fi

git fetch -q origin main 2>/dev/null || { echo "FETCH FAILED (network? auth?)"; exit 1; }

BEFORE="$(git rev-parse --short HEAD)"
if ! git merge --ff-only "$TARGET" -q 2>/dev/null; then
  # A host on an unrelated commit is a real situation (fedora was on an old
  # branch point). Reset to the target rather than leaving it stranded, since
  # the tree is known clean at this point.
  git checkout -q main 2>/dev/null || git checkout -qB main
  git reset -q --hard "$TARGET" || { echo "COULD NOT REACH TARGET"; exit 1; }
fi
AFTER="$(git rev-parse --short HEAD)"
[ "$BEFORE" != "$AFTER" ] && echo "repo $BEFORE -> $AFTER" || echo "repo already at $AFTER"

if [ "$DRY" = "1" ]; then
  ./apply.sh --dry-run 2>&1 | tail -25
  exit 0
fi

if [ "$FULL" = "1" ]; then
  ./install.sh 2>&1 | tail -20
else
  ./apply.sh 2>&1 | tail -20
fi
REMOTE
  rc=$?
  out="$(cat "$tmp")"; rm -f "$tmp"

  if [ "$rc" -ne 0 ] && grep -qiE 'permission denied|connection|timed out|could not resolve|host key' <<<"$out"; then
    printf '  %sUNREACHABLE%s %s\n' "$YELLOW" "$OFF" "$alias"
    sed 's/^/      /' <<<"$out" | head -3
    skipped_hosts+=("$alias")
    return 0
  fi

  if [ "$rc" -eq 3 ]; then
    printf '  %sNEEDS SETUP%s %s\n' "$YELLOW" "$OFF" "$alias"
    sed 's/^/      /' <<<"$out" | grep -A3 'NEEDS-BOOTSTRAP'
    bootstrap_hosts+=("$alias")
    return 0
  fi

  if [ "$rc" -ne 0 ]; then
    printf '  %sFAILED%s      %s\n' "$RED" "$OFF" "$alias"
    sed 's/^/      /' <<<"$out" | head -12
    failed_hosts+=("$alias")
    return 0
  fi

  printf '  %sok%s          %s\n' "$GREEN" "$OFF" "$alias"
  sed 's/^/      /' <<<"$out" | grep -vE '^\s*$' | tail -6
  ok_hosts+=("$alias")
  grep -qE 'change\(s\)|cloned' <<<"$out" && changed_hosts+=("$alias")
  return 0
}

echo "target: $(git rev-parse --short "$TARGET")$([ "$DRY_RUN" = 1 ] && echo '  (dry run)')"
echo

while read -r alias type; do
  [ -z "$alias" ] && continue
  if [ "${#ONLY[@]}" -gt 0 ]; then
    match=0
    for o in "${ONLY[@]}"; do [ "$o" = "$alias" ] && match=1; done
    [ "$match" = "1" ] || continue
  fi
  echo "${DIM}--- $alias ($type) ---${OFF}"
  update_host "$alias" "$type"
  echo
done < <(wanted_hosts)

echo "================================================================"
printf 'ok: %d   failed: %d   unreachable: %d\n' \
  "${#ok_hosts[@]}" "${#failed_hosts[@]}" "${#skipped_hosts[@]}"
[ "${#changed_hosts[@]}" -gt 0 ] && echo "changed: ${changed_hosts[*]}"
[ "${#failed_hosts[@]}" -gt 0 ] && echo "${RED}failed:${OFF} ${failed_hosts[*]}"
[ "${#skipped_hosts[@]}" -gt 0 ] && echo "${YELLOW}unreachable:${OFF} ${skipped_hosts[*]}"
if [ "${#bootstrap_hosts[@]}" -gt 0 ]; then
  echo "${YELLOW}needs one-time setup:${OFF} ${bootstrap_hosts[*]}"
  echo "  These hosts lack git and their sudo needs a password, which a"
  echo "  non-interactive run cannot supply. Run the printed command on each,"
  echo "  then re-run this script."
fi

[ "${#failed_hosts[@]}" -eq 0 ]
