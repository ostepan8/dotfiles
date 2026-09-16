# Learning this setup

This file is a lab, not a manual. It is meant to be opened in nvim and
**mangled** — every practice block below is throwaway text you should edit,
break, and undo. Nothing here is real config.

    u        undo whatever you just did
    <C-r>    redo it
    :e!      reload this file from disk, discarding everything

`<leader>` is **Space**. When a drill says `<leader>hp`, that is Space, then h,
then p. Press Space alone and wait half a second — which-key now shows you
what is under every prefix.

Work through one part per sitting. The parts are ordered by how much they pay
back, not by how the config file is arranged.

---

## Part 0 — the one idea

Almost everything you are about to learn is the same grammar:

    <verb><target>

You already know verbs: `d` delete, `c` change, `y` yank, `v` select.
What this setup adds is **better targets**. Instead of "3 lines down" you get
"this function", "this parameter", "this git hunk", "the thing inside these
quotes".

So `daf` is not a new command to memorise. It is `d` (delete) + `af`
(a function) — built from parts you already have.

If you learn nothing else from this file, learn that new targets compose with
verbs you already use.

---

## Part 1 — Surround

The one exception to the rule above: surround adds *verbs*, not targets.

    ys<target><char>    add a surrounding
    ds<char>            delete a surrounding
    cs<old><new>        change a surrounding

### Drill 1a — add

Put the cursor anywhere on `hello` and type `ysiw"` — "surround inner word
with a double quote".

    hello world
    hello world
    hello world

Now try `ysiw)` on the first line and `ysiw(` on the second. Notice the
difference: the **closing** bracket wraps tight, the **opening** bracket adds
inner spaces.

    tight     ->  (hello)
    spaced    ->  ( hello )

### Drill 1b — whole lines and selections

    make this line a function call
    wrap these three words
    and this whole line too

- `yss)` on line 1 — surrounds the **whole line**.
- On line 2: `vee` to select two words, then `S"`.
- On line 3: `V` then `S{` — linewise.

### Drill 1c — change and delete

    "change my quote style"
    (delete these parens)
    'nested "quotes" here'

- Line 1: `cs"'` — double to single.
- Line 2: `ds(` — parens gone, contents stay.
- Line 3: put the cursor on `quotes` and press `ds"` — it finds the *inner*
  pair, not the outer one.

### If it seems not to work

**Type `ysiw"` as one flowing motion, not as four separate decisions.**

`y` is both the yank operator and the first key of `ys`, so vim waits
`timeoutlen` to work out which you meant. Pause longer than that and it
commits to plain `y`, the surround never fires, and **nothing visible
happens at all** — no error, no message. It looks like the mapping is broken
when it is really a stopwatch.

That window used to be 0.3s, which is inside a normal thinking pause. It is
now 1s, vim's default. Measured, 3 runs each:

| timeoutlen | pause between `y` and `s` | result |
|---|---|---|
| 300 | 0.6s | nothing happens |
| 1000 | 0.6s | surrounds correctly |
| 1000 | 1.5s | nothing happens |

So: decide what you want *first*, then type the whole thing. If you need to
think mid-command, press `<Esc>` and start over rather than pausing.

The same applies to `ds`, `cs`, and every `<leader>` sequence.

### When this pays off

Renaming a string, wrapping an expression in a function call, converting
`'x'` to `"x"` across a file. It replaces a very common
find-the-end-and-type-a-bracket dance.

**Practice target:** for one week, never type a closing bracket around
existing text by hand.

---

## Part 2 — Treesitter textobjects

This is the highest-value part of the file. It gives you targets that
understand code structure, so you stop counting lines.

    af / if    a function      / inner function (body only)
    ac / ic    a class         / inner class
    aa / ia    a parameter     / inner parameter
    al / il    a loop          / inner loop
    ak / ik    a conditional   / inner conditional
    ar / ir    a return        / inner return
    a= / i=    a whole assignment statement / the assignment without
               its type and semicolon

Combine with any verb: `daf` `cif` `vac` `yia`.

### First: open the practice file

**These drills do not work in this file.** Open the real one:

    :e %:h/practice.cpp

Why: treesitter textobjects resolve against the **buffer's** parser. This
file is markdown, and the markdown grammar has no concept of a function, so
`af` and `]f` find nothing. The C++ below is an *injected* language inside a
fenced block, and the motions do not follow injections — they see markdown
and stop.

This is worth knowing beyond the drill: **textobjects will not work on code
inside a markdown fence**, in these notes or anywhere else. The code block
below is here to read. `practice.cpp` is here to edit.

### Drill 2a — functions

In `practice.cpp`, put the cursor **anywhere inside** `helper` and press
`vaf`. The whole function highlights, including its signature. Now `vif` —
only the body.

For reference, `practice.cpp` contains roughly this (textobjects will not
work on this copy — it is a markdown fence):

```cpp
int helper(int a, int b, int c) {
    int sum = a + b;
    return sum + c;
}

long long fib(int n) {
    if (n <= 1) { return n; }
    ...
}

int main() {
    int x = helper(1, 2, 3);
    ...
}
```

Now try, undoing between each:

- `daf` from inside `helper` — the whole function disappears.
- `cif` from inside `helper` — body cleared, signature kept, you are in insert.
- `vak` with the cursor on `return 1;` — selects the whole `if` block.
- `val` with the cursor inside the `for` — selects the whole loop.
- `vi=` on the `int x = helper(1, 2, 3);` line — selects `x = helper(1, 2, 3)`.
  Note this is the **whole assignment**, both sides, not just the value.
  `va=` takes the statement entire, `int` and `;` included.

### Drill 2b — parameters

In `practice.cpp`, cursor on `b` in `helper`'s signature:

- `cia` — change just that parameter.
- `daa` — delete it **and its comma**. This is the one that saves real time;
  deleting a middle parameter by hand always leaves a stray comma.

### Drill 2c — lookahead

Put the cursor on a **blank line** between two functions in
`practice.cpp`, then press `vaf`. It still works — if there is no function under the cursor, it jumps
forward to the next one instead of failing. You rarely need to position
precisely first.

### Drill 2d — moving

    ]f   jump to the next function      [f   previous function
    ]F   end of the next function       [F   end of the previous
    ]a   next parameter                 [a   previous parameter

In `practice.cpp` there are four functions — `helper`, `fib`, `evens` and
`main`. Hold `]f` and watch the cursor hop between them; `[f` walks back.
This replaces scrolling to find things.

If `]f` and `[f` appear to do nothing, check the bottom-right of your
statusline: you are almost certainly in a markdown or text buffer, where
there are no functions to jump to.

### Drill 2e — reordering parameters

Cursor on any parameter in `helper(int a, int b, int c)`:

    <leader>a    swap this parameter with the next one
    <leader>A    swap it with the previous one

Commas are handled. Try `<leader>a` twice on `a` and watch it walk to the end.

### When this pays off

Constantly, in the C++ contest files especially — `daf` to clear a wrong
approach, `]f` to navigate, `cia` to fix a signature. It is the difference
between editing text and editing code.

**Practice target:** stop using `dd` in a loop to delete a function. Use `daf`.

---

## Part 3 — Git hunks, without leaving the buffer

A "hunk" is one contiguous block of changes versus the index. Previously you
could only see these as `+`/`~` marks in the gutter.

    ]c  [c          jump to next / previous hunk
    <leader>hp      preview the hunk in a floating window
    <leader>hs      stage it   (press again on a staged hunk to UNstage)
    <leader>hr      reset it — discards the change
    <leader>hb      full blame for this line: author, commit, message
    <leader>hd      diff this file against the index
    <leader>hq      every hunk in the repo -> quickfix list
    dih / vih       delete / select the hunk as a textobject

### Drill 3

This file is committed to a git repo, so the drill works right here. (Worth
knowing: gitsigns only attaches to files git already **tracks**. On a
brand-new untracked file there are no hunks, no `]c`, and no `<leader>h`
mappings at all — that is expected, not a broken config.)

1. Change a few words in three different places in this file.
2. Press `]c` a few times — you hop between exactly those three spots.
3. On one of them, `<leader>hp` to see the before/after.
4. `<leader>hs` to stage it. The gutter sign changes.
5. `<leader>hs` again on the same hunk — it unstages. It is a toggle.
6. `<leader>hr` on another one to throw the change away.
7. `:e!` to reset this file entirely.

### Partial staging

Select a few lines in visual mode, then `<leader>hs`. Only the selected lines
get staged, not the whole hunk. This is the thing people open `lazygit` for,
and you can now do it without leaving the buffer.

(`prefix + g` still opens lazygit in a popup when you want the full view.)

### Inline blame

The greyed-out author/date at the end of the line you are on appears after a
400ms pause. `<leader>hB` toggles it off if it gets distracting.

---

## Part 4 — Finding things

Your four originals are unchanged and still single-key:

    <leader>f    find files          <leader>p    recent files
    <leader>g    live grep           <leader>b    open buffers

Everything added lives under `<leader>s`:

    <leader>sr   RESUME the last picker, results intact
    <leader>s/   fuzzy-find inside the current buffer
    <leader>ss   symbols in this file
    <leader>sS   symbols across the project
    <leader>sd   all diagnostics
    <leader>sg   git status        <leader>sc   git commits
    <leader>sk   every keymap you have
    <leader>sh   help tags

### The one to actually internalise: `<leader>sr`

The old painful loop was: grep for something, follow a result into a file,
then need the other results back — and retype the whole search.

`<leader>sr` reopens the previous picker with its query *and* its result list
exactly as they were. Grep, jump, read, `<leader>sr`, jump to the next one.

### `<leader>sk` is how you explore

Forgot a binding? `<leader>sk` and fuzzy-search your own keymaps. This file
will go stale eventually; that picker will not.

---

## Part 5 — Sessions and tmux

### nvim sessions

    <leader>qs   restore the session for this directory
    <leader>ql   restore the last session, wherever it was
    <leader>qS   pick from a list
    <leader>qd   stop saving the current session

Buffers, window layout, folds and cwd all come back. Nothing is written into
your repos — sessions live in `~/.local/state/nvim/sessions`.

Deliberately **not** automatic: `nvim file.py` opens `file.py`, not nine other
buffers. You ask for the session when you want it.

### tmux — the new keys

    prefix + F          hint mode: a letter is painted on every SHA, path, IP
                        and hex string on screen — type it to copy
    prefix + u          fuzzy-pick a URL from the pane (Ctrl+Y copies instead
                        of opening; Tab multi-selects)
    prefix + b          break this pane out into its own window
    prefix + j          pull another pane INTO this window
    prefix + Shift-Left/Right    move the current window along the bar
    prefix + e          edit ~/.tmux.conf in a popup, reloads on close

In copy mode, `o` opens whatever is selected, `C-o` opens it in nvim.

`prefix + F` is the one you will use most — copying a commit SHA or a
stack-trace path out of an agent pane without reaching for the mouse.

### Behaviour that changed

- Killing a session now moves you to the **next** session instead of throwing
  you out of tmux entirely.
- Scrollback is 50,000 lines — but only in panes created **after** the change.
  Old panes keep their 10k until you recreate them.
- Layout autosaves every 5 minutes, and restores on boot.

---

## Part 6 — Things you already had and probably never used

None of these are new. They have been in your config for a while.

### nvim

    <leader>xx    Trouble: every diagnostic in the workspace
    <leader>xs    Trouble: symbol outline of this file
    <leader>ih    toggle inlay hints (inferred types, parameter names)
                  — only exists in buffers whose LSP supports them
    <leader>F     format this buffer on demand
                  (cpp and shell are excluded from format-on-save on purpose)
    gd gr gi K    definition, references, implementation, hover docs
    [d ]d         previous / next diagnostic
    <leader>e     file tree

### PDFs, which most people do not know nvim can do

    nvim paper.pdf    opens the TEXT — searchable, yankable, like any buffer
    ]p  [p            next / previous page
    gi                render the current page as an actual image
    go                hand it to Preview.app
    :PdfHealth        check what is available on this machine

### C++ contests

    <F5>          debug build: ASan + UBSan + _GLIBCXX_DEBUG
    <F6>          fast build: -O2 only, for realistic TLE timing
    <leader>tc    pull sample testcases from the browser
                  (needs the Competitive Companion extension)
    <leader>tr    run against all stored testcases, with a diff
    <leader>ta    add a testcase by hand

Both `<F5>` and `<F6>` feed `./input.txt` to stdin automatically when that
file exists. New `.cpp` files start from your template with the cursor already
in the body.

### tmux built-ins this config never documented

    prefix + z        zoom the current pane to fullscreen (toggle)
    prefix + <        window menu — swap, rename, kill, respawn
    prefix + >        pane menu — split, swap, zoom, copy the word under mouse
    prefix + f        find a window by name
    prefix + Space    cycle pane layouts
    prefix + S        synchronise panes — type once, every pane receives it
    Opt+P             session picker (running sessions + zoxide history)
    Opt+G             persistent scratch popup — same shell every time

---

## A two-week plan

Trying to adopt all of this at once fails. Pick one thing per few days and
force it.

**Days 1-3 — surround.** Rule: never hand-type a bracket around existing
text. `ysiw`, `cs`, `ds` only.

**Days 4-7 — `af` and `if`.** Rule: never delete a function with `dd`. Every
function-level edit goes through `daf` / `cif` / `vaf`. Add `]f` for
navigation once the objects feel automatic.

**Days 8-10 — git hunks.** Rule: stage from inside nvim, not lazygit. `]c` to
walk, `<leader>hp` to check, `<leader>hs` to stage. Keep lazygit for rebases
and history.

**Days 11-14 — `<leader>sr` and `prefix + F`.** These are small but they
remove two daily annoyances: retyping searches, and mouse-selecting SHAs.

After that, skim Part 6. Most of what is there you are already paying for.

---

## Reference: everything added, in one place

### nvim — surround
| Key | Does |
|---|---|
| `ys<target><char>` | add surrounding |
| `yss<char>` | surround the whole line |
| `S<char>` (visual) | surround the selection |
| `ds<char>` | delete surrounding |
| `cs<old><new>` | change surrounding |

### nvim — textobjects
| Key | Target |
|---|---|
| `af` `if` | function / its body |
| `ac` `ic` | class / its body |
| `aa` `ia` | parameter (with comma) / parameter |
| `al` `il` | loop / its body |
| `ak` `ik` | conditional / its body |
| `ar` `ir` | return statement / its value |
| `a=` `i=` | whole assignment statement / assignment without type and `;` |
| `]f` `[f` `]F` `[F` | move by function (start / end) |
| `]a` `[a` | move by parameter |
| `<leader>a` `<leader>A` | swap parameter next / previous |

### nvim — git
| Key | Does |
|---|---|
| `]c` `[c` | next / previous hunk |
| `<leader>hs` `<leader>hr` | stage (toggle) / reset hunk |
| `<leader>hS` `<leader>hR` | stage / reset whole buffer |
| `<leader>hp` | preview hunk |
| `<leader>hb` `<leader>hB` | blame line / toggle inline blame |
| `<leader>hd` `<leader>hD` | diff vs index / vs last commit |
| `<leader>hq` | all hunks to quickfix |
| `ih` | hunk as a textobject |

### nvim — search and sessions
| Key | Does |
|---|---|
| `<leader>sr` | resume last picker |
| `<leader>s/` | fuzzy-find in this buffer |
| `<leader>ss` `<leader>sS` | document / workspace symbols |
| `<leader>sd` `<leader>sg` `<leader>sc` | diagnostics / git status / commits |
| `<leader>sk` `<leader>sh` | keymaps / help tags |
| `<leader>qs` `<leader>ql` `<leader>qS` `<leader>qd` | session: cwd / last / pick / stop |

### nvim — clipboard safety
| Key | Does |
|---|---|
| `<leader>d` `<leader>D` | delete without touching the clipboard |
| `<leader>p` (visual) | paste over a selection, keep the clipboard |
| `x` | now always black-hole |

Your config sets `clipboard=unnamedplus`, so an ordinary `d` overwrites what
you yanked. These are the escape hatch.

### tmux
| Key | Does |
|---|---|
| `prefix + F` | hint-copy SHAs, paths, IPs |
| `prefix + u` | fuzzy-pick a URL |
| `prefix + b` `prefix + j` | break pane out / join pane in |
| `prefix + Shift-Left/Right` | move window along the bar |
| `prefix + e` | edit tmux.conf in a popup |
| `o` / `C-o` (copy mode) | open selection / open in nvim |

---

Keys you can trust over this file: `<leader>sk` lists every nvim mapping that
actually exists right now, and `prefix + ?` does the same for tmux. When this
file and those disagree, they are right.
