---
name: screenshot
description: Find and look at a screenshot Owen took, on EITHER Mac. Use whenever Owen pastes a screenshot path, says "look at my screenshot", "see the screenshot", "check the screen grab", "I just took a screenshot", or a path under ~/Screenshots, /Users/ostepan/ or /Users/owenstepan/ does not exist on this machine. Owen takes screenshots on the MacBook and the Mac Studio, and a path from one machine does not exist on the other — never tell Owen the file is missing until both machines are checked.
---

# screenshot

Owen has two Macs. A screenshot path they paste can come from either one:

| Machine | Home | ssh alias (from the other Mac) |
|---|---|---|
| Mac Studio | `/Users/owenstepan` | `studio` |
| MacBook | `/Users/ostepan` | `macbook` |

Screenshots go to `~/Screenshots`, and sometimes to `~/Desktop` or `~/Downloads`.

## Do this

Run the helper. It searches both machines, copies a remote match here, and prints a
local path:

```bash
~/.agents/skills/screenshot/find-shot <pasted-path-or-name>   # a named shot
~/.agents/skills/screenshot/find-shot                         # newest shot on either Mac
```

Then open the printed path with the Read tool to see the image.

## Rules

- If the file is not on this machine, check the other machine before you reply. Do not
  ask Owen to drag the image in or copy it over.
- If they say "my screenshot" or "the screenshot I just took" with no path, run
  `find-shot` with no argument. That gives the newest screenshot on either machine.
- If `find-shot` cannot reach the other Mac, check the tailnet with the `tailnet` skill.
  Then try `macbook-lan`. Only after both fail, tell Owen which machine you could not reach.
- Copies land in `$TMPDIR/shots`. Do not copy screenshots into a project repo.
