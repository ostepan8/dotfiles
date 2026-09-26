# atlas recipe for app-login. Sourced by app-login, which provides INST, PG_PORT,
# fresh_db, dsn, psql_admin, free_port, start_bg, wait_http, say, die.
#
# A local atlas is contextd (API + the PWA it embeds) and, when the tree has it,
# workqd (the Work screen's queue). Both start with `env -i` and only the variables
# below: nothing from the caller's shell leaks in, so a local copy never reaches
# a real lamp, TV, Kalshi account or the fleet. Panels for those say "not configured".

app_prod_origin() {
  local f="$HOME/.config/atlas/env" line
  line=$(grep -E '^ATLAS_ORIGIN=' "$f" 2>/dev/null | head -1) || die "ATLAS_ORIGIN not in $f"
  echo "${line#ATLAS_ORIGIN=}" | tr -d "\"'"
}
app_prod_secret() { echo ATLAS_CLAUDE_PASSKEY; }

_atlas_key() { basename "$INST" | tr -c 'A-Za-z0-9\n' '_' | tr 'A-Z' 'a-z'; }

# The only environment the local services see.
_atlas_env() { ENVI=(env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="$INST/home" TZ="${TZ:-America/New_York}"); }

app_up() {
  local src="$1" k; k=$(_atlas_key)
  [ -d "$src/services/contextd" ] && [ -d "$src/apps/pwa" ] || die "$src is not an atlas checkout"
  mkdir -p "$INST/bin" "$INST/home" "$INST/blobs"

  say "building the app from $src"
  (cd "$src/apps/pwa" && { [ -d node_modules ] || npm ci --silent --no-audit --no-fund; } && npm run build --silent) \
    > "$INST/build.log" 2>&1 || die "PWA build failed; see $INST/build.log"
  (cd "$src" && CGO_ENABLED=0 go build -o "$INST/bin/contextd" ./services/contextd/cmd/contextd) \
    >> "$INST/build.log" 2>&1 || die "contextd build failed; see $INST/build.log"
  local has_workq=0
  if [ -d "$src/services/workq/cmd/workq" ]; then
    has_workq=1
    (cd "$src" && CGO_ENABLED=0 go build -o "$INST/bin/workq" ./services/workq/cmd/workq) \
      >> "$INST/build.log" 2>&1 || die "workq build failed; see $INST/build.log"
  fi

  _atlas_env
  local cport wport app_tok run_tok
  cport=$(free_port); wport=$(free_port)
  app_tok=$(openssl rand -hex 24); run_tok=$(openssl rand -hex 24)
  fresh_db "atlas_$k"

  local workq_env=()
  if [ $has_workq = 1 ]; then
    fresh_db "workq_$k"
    start_bg workq "${ENVI[@]}" WORKQ_DSN="$(dsn "workq_$k")" WORKQ_APP_TOKEN="$app_tok" \
      WORKQ_RUNNER_TOKEN="$run_tok" WORKQ_BLOB_DIR="$INST/blobs" WORKQ_LISTEN="127.0.0.1:$wport" \
      "$INST/bin/workq"
    wait_http "http://127.0.0.1:$wport/readyz" workq
    _atlas_seed_projects "http://127.0.0.1:$wport" "$run_tok"
    workq_env=(ATLAS_WORKQ_URL="http://127.0.0.1:$wport" ATLAS_WORKQ_TOKEN="$app_tok")
  fi

  local cenv=(ATLAS_DSN="$(dsn "atlas_$k")" ATLAS_EMBED_URL=http://127.0.0.1:1 ATLAS_EMBED_MODEL=none
    ATLAS_GATEWAY_KEY=local ATLAS_EMBED_DIMS=768 ATLAS_RP_ID=localhost
    ATLAS_ORIGIN="http://localhost:$cport" ATLAS_LISTEN="127.0.0.1:$cport" "${workq_env[@]+"${workq_env[@]}"}")
  start_bg contextd "${ENVI[@]}" "${cenv[@]}" "$INST/bin/contextd" serve
  wait_http "http://127.0.0.1:$cport/" contextd

  # The enrol link carries a one-time code: straight to a 600 file, never printed.
  (umask 077; "${ENVI[@]}" "${cenv[@]}" "$INST/bin/contextd" passkey enroll --label claude 2>&1 \
    | grep -oE 'https?://[^ ]+#[^ ]+' | head -1 > "$INST/enroll.url")
  [ -s "$INST/enroll.url" ] || die "contextd passkey enroll printed no link"

  {
    echo "ORIGIN=http://localhost:$cport"
    echo "ATLAS_DSN='$(dsn "atlas_$k")'"
    if [ $has_workq = 1 ]; then
      echo "WORKQ_URL=http://127.0.0.1:$wport"
      echo "WORKQ_APP_TOKEN=$app_tok"
      echo "WORKQ_RUNNER_TOKEN=$run_tok"
      echo "WORKQ_DSN='$(dsn "workq_$k")'"
    fi
  } > "$INST/env"
  chmod 600 "$INST/env"
}

# The Work screen's project picker lists what the Studio runner reports; report the
# same git repos under ~/projects, so a local copy looks like the phone.
_atlas_seed_projects() { # workq url, runner token
  WORKQ_PROJECTS_DIR="${WORKQ_PROJECTS_DIR:-$HOME/projects}" python3 - <<'PYSEED' |
import json, os, subprocess
root = os.environ["WORKQ_PROJECTS_DIR"]
out = []
for name in sorted(os.listdir(root)):
    path = os.path.join(root, name)
    if not os.path.isdir(os.path.join(path, ".git")):
        continue
    def git(*a):
        r = subprocess.run(["git", "-C", path, *a], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else ""
    url = git("remote", "get-url", "origin")
    repo = ""
    if "github.com" in url:
        repo = url.split("github.com", 1)[1].lstrip(":/").removesuffix(".git")
    branch = git("symbolic-ref", "--short", "refs/remotes/origin/HEAD").removeprefix("origin/") or "main"
    out.append({"name": name, "path": path, "repo": repo, "default_branch": branch})
print(json.dumps({"projects": out}))
PYSEED
    curl -fs -m 10 -X PUT -H "Authorization: Bearer $2" -H 'Content-Type: application/json' \
      --data-binary @- "$1/v1/runner/projects" >/dev/null || say "could not seed the project list (the Work screen will show none)"
}

app_down() {
  local k; k=$(_atlas_key)
  psql_admin -c "DROP DATABASE IF EXISTS \"atlas_$k\" WITH (FORCE);" -c "DROP DATABASE IF EXISTS \"workq_$k\" WITH (FORCE);"
}
