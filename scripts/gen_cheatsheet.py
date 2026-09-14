#!/usr/bin/env python3
"""Render cheatsheet keybinding grids from docs/keys.tsv."""
import html, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = ROOT / "docs" / "cheatsheet.html"
TSV = ROOT / "docs" / "keys.tsv"

MODS = {"Ctrl", "Alt", "Opt", "Cmd", "Shift"}
# Multi-character keys the stylesheet widens so they do not look cramped.
WIDE = {"Space", "Tab", "Enter", "Return", "Esc"}
BEGIN = "<!-- GENERATED from docs/keys.tsv — edit that, then `make cheatsheet` -->"
END = "<!-- /GENERATED -->"


def kbd(tok: str) -> str:
    """One key token -> its <kbd>. The class carries layout intent: mods and
    symbols are sized differently, and word-keys get extra width."""
    if tok.startswith("`") and tok.endswith("`"):
        return f"<code>{html.escape(tok[1:-1])}</code>"
    if tok in MODS:
        return f'<kbd class="mod">{tok}</kbd>'
    if tok in WIDE:
        return f'<kbd class="wide">{tok}</kbd>'
    if len(tok) == 1 and not tok.isalnum():
        return f'<kbd class="sym">{html.escape(tok)}</kbd>'
    return f"<kbd>{html.escape(tok)}</kbd>"


def render_part(part: str) -> str:
    """One element of a chord. Whitespace around a separator is meaningful:
    "H/J" is a tight alternation (a sep span), while "- / =" and "1 … 9" are
    read as prose and keep their literal spacing."""
    for literal in (" / ", " … "):
        if literal in part:
            return literal.join(kbd(t) for t in part.split(literal))
    if "/" in part and part != "/":
        return '<span class="sep">/</span>'.join(kbd(t) for t in part.split("/") if t)
    return kbd(part)


def render_segment(seg: str) -> str:
    """A chord: parts joined by +."""
    return '<span class="sep">+</span>'.join(render_part(p.strip()) for p in seg.split("+"))


def render(spec: str) -> str:
    """Full spec -> markup. `then` separates sequential presses (tmux prefix)."""
    return '<span class="then">then</span>'.join(
        render_segment(s) for s in spec.split(" then ")
    )


def load_rows():
    rows = {}
    for line in TSV.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        section, spec, desc = line.split("\t", 2)
        rows.setdefault(section, []).append((spec, desc))
    return rows


def build(doc: str, rows) -> str:
    for section, entries in rows.items():
        body = "\n".join(
            f'    <div class="keys">{render(spec)}</div>\n'
            f'    <div class="desc-cell">{desc}</div>\n'
            for spec, desc in entries
        )
        block = f"    {BEGIN}\n{body}    {END}\n"
        # The grid immediately following this section's <h3>.
        pat = re.compile(
            r'(<h3>' + re.escape(section) + r'</h3>\s*\n\s*<div class="grid">\n)(.*?)(  </div>)',
            re.S,
        )
        if not pat.search(doc):
            sys.exit(f"gen-cheatsheet: no grid found for section {section!r}")
        doc = pat.sub(lambda m: m.group(1) + block + m.group(3), doc, count=1)
    return doc


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "write"
    doc = HTML.read_text()
    out = build(doc, load_rows())
    if mode == "--check":
        if out != doc:
            print("cheatsheet is STALE — run `make cheatsheet`", file=sys.stderr)
            sys.exit(1)
        print("cheatsheet current")
        return
    HTML.write_text(out)
    n = sum(len(v) for v in load_rows().values())
    print(f"cheatsheet: regenerated {n} keybindings across {len(load_rows())} sections")


main()
