---
name: debug-form-recording
description: >
  Analyze a browser-automation form-filling recording (Playwright .webm) to debug
  what went wrong. Extracts frames, reads them visually, and reports exactly where
  the agent misbehaved (wrong clicks, missed fields, navbar navigation, etc.).
  Use this skill whenever a form run produced unexpected behavior.
---

# Debug Form Recording

This skill analyzes a `.webm` recording produced by the browser-automation pipeline
(`runner.py --record`) to diagnose form-filling failures.

## Invocation

The user calls `/debug-form-recording` with one of:
- A path to a specific `recording.webm`: `/debug-form-recording results/20260508_151933/www_canva_com/video/recording.webm`
- A run ID: `/debug-form-recording 20260508_151933`
- Nothing — the skill finds the most recent recording automatically

## Step 1 — Locate the video

**If a full path was given:** use it directly.

**If a run ID was given:** find the video at:
```
results/<run_id>/*/video/recording.webm
```
Use Glob with pattern `results/<run_id>/*/video/recording.webm` from the project root
(`/Users/ostepan/Desktop/browser-automation-with-haiku`).

**If nothing was given:** find the most recently modified recording across all runs:
```bash
find /Users/ostepan/Desktop/browser-automation-with-haiku/results -name "recording.webm" | xargs ls -t | head -1
```

If no video is found, tell the user to run with `--record` and stop.

## Step 2 — Extract frames

Run the extractor from the project root:
```bash
cd /Users/ostepan/Desktop/browser-automation-with-haiku && \
  .venv/bin/python agent/extract_frames.py <video_path> --frames 16
```

This outputs PNGs to `<video_dir>/frames/frame_NNN_Xs.png`.
Note the output directory printed by the script.

If ffmpeg is missing, tell the user: `brew install ffmpeg` and stop.

## Step 3 — Visual analysis

Read every frame PNG using the Read tool (it renders images inline).
Work through them in timestamp order.

For each frame, note:
- **Page state**: which page/URL is shown (look at the browser address bar if visible),
  what stage of the form is visible, whether a dropdown/modal is open
- **Agent action**: what the automation appears to have just done (click, type, scroll)
- **Problem indicators**: wrong element highlighted/clicked, navbar links selected,
  text typed into the wrong field, dropdown open but no option selected,
  page navigated away from the form, CAPTCHA visible

## Step 4 — Root-cause report

After reviewing all frames, write a structured report:

```
## Recording: <video_path>
## Duration: <approx duration from frame timestamps>

### Timeline of Events
| Frame | Time  | What happened |
|-------|-------|---------------|
| 001   | 0.0s  | Landed on form page |
| ...   | ...   | ...           |

### Problems Found
1. **<Problem title>** (frame NNN, ~Xs)
   - What happened: ...
   - Root cause: ...
   - Fix: ...

### Fields Status
- Filled correctly: ...
- Missed / empty: ...
- Filled with wrong value: ...

### Recommendation
<1-3 specific code changes or config tweaks to fix the issues>
```

## Domain context

This is a 4-tier form-filling pipeline:
- **T1**: DOM extraction → Haiku text mapping
- **T2**: Haiku visual one-shot (screenshot → fill plan)
- **T3**: Haiku computer use (agentic loop, up to 20 steps)
- **T4**: Sonnet computer use (last resort, up to 10 steps)

**Common bugs to look for:**
- **Navbar clicks**: The agent clicks links in the site navigation instead of form fields.
  Usually caused by coordinate offset error in `_visual_topup` — screenshot was clipped
  from an iframe but coordinates were not offset back to full-page space.
- **Dropdown never opens / wrong option**: Custom JS dropdowns (Canva, etc.) need the
  agent to click the trigger, wait for the menu to appear, then click the option.
  T1 DOM fill doesn't handle these; T2 visual one-shot may also fail if the dropdown
  renders outside the screenshot crop.
- **Form abandoned mid-fill**: Context window exhaustion in computer use caused the
  sliding-window truncation to drop important state. Or the page navigated away.
- **CAPTCHA block**: reCAPTCHA Enterprise detected automation and showed a challenge.
- **Submit not found**: Submit button was outside the viewport and scroll-to-bottom
  didn't bring it into view, or it was hidden behind a sticky footer.
- **Fields appeared dynamically**: After filling one dropdown, new dependent fields
  appeared but weren't detected because extraction ran only once at T1.

Keep the report tight and actionable — the goal is to identify the exact code location
to fix, not to describe everything that happened.
