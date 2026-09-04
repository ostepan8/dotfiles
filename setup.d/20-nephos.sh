#!/usr/bin/env bash
# layers: nephos-keeper nephos-operator nephos-node
#
# Write ~/.config/nephos/env — this machine's endpoints and control-plane host.
# Never committed: the repo is public, and these values describe the fleet.
#
# Nothing secret is asked for or stored here. Credentials are fetched on demand
# into the environment (see base/zsh/nephos.zsh), never written to disk.

_env="$HOME/.config/nephos/env"
[ -f "$_env" ] && { unset _env; return 0; }

_tier="node"
layer_active nephos-operator && _tier="operator"
layer_active nephos-keeper   && _tier="keeper"

echo
echo "  nephos is not configured on this machine (no $_env)."
echo "  Declared tier: $_tier"
case "$_tier" in
  keeper)   echo "    holds the master vault; mints and revokes credentials" ;;
  operator) echo "    can provision and deploy; holds no long-lived secrets" ;;
  node)     echo "    runs workloads; control-plane access is force-command pinned" ;;
esac
echo "  Requires Tailscale to be up and the control plane reachable."
echo

_ctl=""; _domain=""
if ask _ctl "control-plane ssh alias" && ask _domain "personal domain (e.g. example.com)"; then
  mkdir -p "$(dirname "$_env")"
  cat > "$_env" <<EOF
# Written by setup.d/20-nephos.sh. NEVER commit this file.
NEPHOS_TIER=$_tier
NEPHOS_CONTROL_ADDR=http://127.0.0.1:7930
NEPHOS_CONTROL_HOST=$_ctl
NEPHOS_BIN=~/bin/nephos
NEPHOS_DOMAIN=$_domain
NEPHOS_API=https://api.$_domain
NEPHOS_LLM=https://llm.$_domain/v1
NEPHOS_S3=https://s3.$_domain
EOF
  chmod 600 "$_env"
  echo "    wrote $_env (chmod 600, untracked)"

  if command -v tailscale >/dev/null 2>&1 && ! tailscale status >/dev/null 2>&1; then
    echo "    NOTE: tailscale is installed but not up — run 'sudo tailscale up'"
  fi
else
  echo "    skipped — copy base/agents/skills/nephos/env.template to $_env by hand"
fi
unset _env _tier _ctl _domain
