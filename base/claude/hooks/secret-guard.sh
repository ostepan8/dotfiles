#!/usr/bin/env bash
# secret-guard.sh — a UserPromptSubmit hook: a secret typed into chat never
# reaches the model or the transcript.
#
# Transcripts are plain JSONL on disk and are read back by later sessions. A
# sudo password (2026-09-09) and a Resend key (2026-09-03) both landed there
# because the vault was one step further away than the prompt box.
#
# Blocks (exit 2, prompt erased) when the prompt carries a key-shaped token or a
# "password is ..." phrase, and says how to store it instead. Fails OPEN on
# anything unexpected. To send anyway, put SECRET_GUARD=off in the prompt.
set -uo pipefail

input=$(cat 2>/dev/null || true)
command -v python3 >/dev/null 2>&1 || exit 0

hit=$(printf '%s' "$input" | python3 -c '
import json, re, sys
try:
    prompt = json.load(sys.stdin).get("prompt", "")
except Exception:
    sys.exit()
if "SECRET_GUARD=off" in prompt:
    sys.exit()
PATTERNS = [
    ("Anthropic key",    r"\bsk-ant-[A-Za-z0-9_-]{20,}"),
    ("OpenRouter key",   r"\bsk-or-[A-Za-z0-9_-]{20,}"),
    ("OpenAI-style key", r"\bsk-(?:proj-)?[A-Za-z0-9_-]{32,}"),
    ("GitHub token",     r"\b(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{30,}|\bgithub_pat_[A-Za-z0-9_]{40,}"),
    ("AWS access key",   r"\bAKIA[0-9A-Z]{16}\b"),
    ("Google API key",   r"\bAIza[0-9A-Za-z_-]{35}\b"),
    ("Slack token",      r"\bxox[abpr]-[A-Za-z0-9-]{10,}"),
    ("Resend key",       r"\bre_[A-Za-z0-9]{8,}_[A-Za-z0-9]{16,}"),
    ("Stripe key",       r"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{20,}"),
    ("ElevenLabs key",   r"\bsk_[a-f0-9]{40,}\b"),
    ("private key",      r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    ("password",         r"(?i)\b(?:pass(?:word)?|passwd|pw)\s*(?:is|=|:)\s*\S*[0-9!@#$%^&*]\S*"),
]
for name, pat in PATTERNS:
    if re.search(pat, prompt):
        print(name)
        break
' 2>/dev/null)

[ -n "$hit" ] || exit 0

cat >&2 <<MSG
Prompt not sent: it looks like it contains a ${hit}. Transcripts are stored on
disk in plain text, so secrets go in the vault, not the chat.

Store it with a hidden popup (works on any machine):
  vault-add NAME            # e.g. vault-add RESEND_API_KEY -p avastepan
Then tell Claude the NAME and it will pull it with \`vault get NAME\`.

False positive? Resend with SECRET_GUARD=off anywhere in the prompt.
MSG
exit 2
