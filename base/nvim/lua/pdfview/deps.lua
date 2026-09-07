-- External dependency checks.
--
-- pdfview degrades in layers rather than failing whole: with poppler you get
-- text, and with poppler + image.nvim + a graphics-capable terminal you also
-- get rendered pages. `health()` says exactly which layer this machine is on,
-- because "why is nothing happening" is otherwise unanswerable from inside the
-- editor.

local M = {}

local BREW = "brew install poppler"

M.requirements = {
  {
    name = "pdftotext",
    kind = "executable",
    why = "extracts the text layer (the default view)",
    hint = BREW,
  },
  {
    name = "pdfinfo",
    kind = "executable",
    why = "counts pages, including pages with no text",
    hint = BREW,
  },
  {
    name = "pdftoppm",
    kind = "executable",
    why = "rasterizes a page for the image view (gi)",
    hint = BREW,
  },
  {
    name = "image.nvim",
    kind = "module",
    module = "image",
    why = "displays the rasterized page in the terminal (gi)",
    hint = "add 3rd/image.nvim to your lazy.nvim spec",
  },
}

local function available(item)
  if item.kind == "module" then
    return (pcall(require, item.module))
  end
  return vim.fn.executable(item.name) == 1
end

--- @return table[] one entry per requirement: { name, ok, why, hint }
function M.health()
  local report = {}
  for _, item in ipairs(M.requirements) do
    report[#report + 1] = {
      name = item.name,
      ok = available(item),
      why = item.why,
      hint = item.hint,
    }
  end
  return report
end

--- @param name string
--- @return boolean
function M.have(name)
  for _, item in ipairs(M.requirements) do
    if item.name == name then return available(item) end
  end
  return false
end

-- Terminals that implement the Kitty graphics protocol, which is what
-- image.nvim uses to actually paint pixels.
local GRAPHICS_TERMINALS = { "ghostty", "kitty", "wezterm" }

local function names_a_graphics_terminal(value)
  value = (value or ""):lower()
  for _, name in ipairs(GRAPHICS_TERMINALS) do
    if value:find(name, 1, true) then return true end
  end
  return false
end

--- Classify a terminal from the identifying values available to us.
---
--- Three-valued on purpose. "unknown" is not a polite "no": most of the
--- evidence here is circumstantial, and treating "I could not tell" as "no"
--- is what silently disables the image view on a perfectly capable terminal.
---
--- @param env table { term, term_program, kitty, ghostty, tmux, tmux_client_term }
--- @return string status "yes" | "no" | "unknown"
--- @return string detail human-readable justification
function M.classify_terminal(env)
  if not env.term or env.term == "" or env.term == "dumb" then
    return "no", "TERM is unset or dumb — this is not an interactive terminal"
  end

  -- Inside tmux the inner values describe TMUX, not the terminal you are
  -- looking at: TERM becomes tmux-256color and TERM_PROGRAM becomes "tmux".
  -- Worse, tmux's global environment keeps whatever started the SERVER, which
  -- for a session restored at boot is some other terminal entirely. The
  -- attached client's own termname is the only honest answer.
  if env.tmux then
    if names_a_graphics_terminal(env.tmux_client_term) then
      return "yes", ("tmux client is %s"):format(env.tmux_client_term)
    end
    if env.tmux_client_term and env.tmux_client_term ~= "" then
      return "unknown", ("tmux client reports TERM=%s, which does not name a known "
        .. "graphics terminal"):format(env.tmux_client_term)
    end
    return "unknown", "could not ask tmux which terminal is attached"
  end

  if env.ghostty or env.kitty then
    return "yes", "the terminal exported its own marker variable"
  end
  if names_a_graphics_terminal(env.term_program) then
    return "yes", ("TERM_PROGRAM=%s"):format(env.term_program)
  end
  if names_a_graphics_terminal(env.term) then
    return "yes", ("TERM=%s"):format(env.term)
  end

  return "unknown", ("TERM=%s TERM_PROGRAM=%s names no known graphics terminal"):format(
    env.term, env.term_program or "unset")
end

--- Ask tmux which terminal is attached to this client.
--- @return string|nil
local function tmux_client_term()
  if vim.fn.executable("tmux") ~= 1 then return nil end
  local out = vim.fn.system({ "tmux", "display-message", "-p", "#{client_termname}" })
  if vim.v.shell_error ~= 0 then return nil end
  local term = vim.trim(out)
  return term ~= "" and term or nil
end

--- Can this terminal paint images?
--- @return string status "yes" | "no" | "unknown"
--- @return string detail
function M.graphics()
  return M.classify_terminal({
    term = vim.env.TERM,
    term_program = vim.env.TERM_PROGRAM,
    kitty = vim.env.KITTY_WINDOW_ID ~= nil,
    ghostty = vim.env.GHOSTTY_RESOURCES_DIR ~= nil,
    tmux = vim.env.TMUX ~= nil,
    tmux_client_term = vim.env.TMUX and tmux_client_term() or nil,
  })
end

--- Should the image plugin be loaded at all? Only "no" — a positively
--- identified non-terminal — is worth skipping it for. Refusing to load on
--- "unknown" is how a working setup ends up silently without images.
--- @return boolean
function M.graphics_possible()
  return M.graphics() ~= "no"
end

--- Inside tmux, image passthrough is off unless it has been switched on.
--- @return boolean ok, string|nil reason
function M.tmux_ready()
  if not vim.env.TMUX then return true end
  local out = vim.fn.system({ "tmux", "show", "-gv", "allow-passthrough" })
  if vim.v.shell_error ~= 0 then return true end
  if vim.trim(out) == "on" then return true end
  return false, "tmux allow-passthrough is off — add `set -gq allow-passthrough on` to ~/.tmux.conf"
end

--- Render the health report into a scratch buffer.
function M.show()
  local lines = { "pdfview health", "" }
  for _, item in ipairs(M.health()) do
    lines[#lines + 1] = ("  [%s] %-12s %s"):format(item.ok and "ok" or "--", item.name, item.why)
    if not item.ok then
      lines[#lines + 1] = ("       install: %s"):format(item.hint)
    end
  end

  lines[#lines + 1] = ""
  local graphics, graphics_detail = M.graphics()
  local marks = { yes = "ok", unknown = "??", no = "--" }
  lines[#lines + 1] = ("  [%s] terminal graphics"):format(marks[graphics])
  lines[#lines + 1] = "       " .. graphics_detail

  local tmux, tmux_reason = M.tmux_ready()
  lines[#lines + 1] = ("  [%s] tmux passthrough"):format(tmux and "ok" or "--")
  if not tmux then lines[#lines + 1] = "       " .. tmux_reason end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.cmd("botright " .. math.min(#lines + 2, 20) .. "split")
  vim.api.nvim_win_set_buf(0, buf)
end

return M
