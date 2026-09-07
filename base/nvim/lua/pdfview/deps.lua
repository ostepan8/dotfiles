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

--- Terminals that speak the Kitty graphics protocol, which is what image.nvim
--- uses to actually paint pixels. Ghostty and Kitty both set TERM_PROGRAM.
--- @return boolean ok, string|nil reason
function M.graphics_capable()
  local program = (vim.env.TERM_PROGRAM or ""):lower()
  if program:find("ghostty") or program:find("kitty") or program:find("wezterm") then
    return true
  end
  if vim.env.KITTY_WINDOW_ID or vim.env.GHOSTTY_RESOURCES_DIR then
    return true
  end
  return false, ("this terminal (TERM_PROGRAM=%s) may not support the Kitty graphics protocol")
    :format(vim.env.TERM_PROGRAM or "unset")
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
  local graphics, graphics_reason = M.graphics_capable()
  lines[#lines + 1] = ("  [%s] terminal graphics"):format(graphics and "ok" or "--")
  if not graphics then lines[#lines + 1] = "       " .. graphics_reason end

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
