-- Shared helpers for pdfview. Kept deliberately tiny: everything here is used
-- by at least two of the other modules.

local M = {}

--- Report a failure to the user. Every error path in pdfview goes through here
--- so nothing is ever swallowed silently.
--- @param msg string
function M.err(msg)
  vim.notify("pdfview: " .. msg, vim.log.levels.ERROR)
end

--- Report something the user asked for that cannot be done, but is not a fault.
--- @param msg string
function M.warn(msg)
  vim.notify("pdfview: " .. msg, vim.log.levels.WARN)
end

--- Transient status line message. Deliberately NOT vim.notify: page navigation
--- fires this constantly and a notification popup per keystroke is unusable.
--- @param msg string
function M.echo(msg)
  vim.api.nvim_echo({ { msg, "Comment" } }, false, {})
end

--- Run a command to completion with a hard timeout.
---
--- Returns `nil, reason` instead of throwing for every failure mode — a missing
--- executable, a timeout, or a non-zero exit — so callers can render the reason
--- into the buffer rather than exploding inside a BufReadCmd.
---
--- @param argv string[] program and arguments, never a shell string
--- @param timeout_ms integer
--- @return string|nil stdout, string|nil reason
function M.run(argv, timeout_ms)
  local ok, proc = pcall(vim.system, argv, { text = true })
  if not ok then
    return nil, ("could not run %s (%s)"):format(argv[1], tostring(proc))
  end

  local done, result = pcall(function() return proc:wait(timeout_ms) end)
  if not done then
    pcall(function() proc:kill("sigkill") end)
    return nil, ("%s did not finish within %dms"):format(argv[1], timeout_ms)
  end

  if result.code ~= 0 then
    local detail = vim.trim(result.stderr or "")
    if detail == "" then detail = ("exit code %d"):format(result.code) end
    return nil, ("%s failed: %s"):format(argv[1], detail)
  end

  return result.stdout or "", nil
end

--- Absolute, symlink-resolved path for a buffer name.
--- @param name string
--- @return string
function M.abspath(name)
  return vim.fn.fnamemodify(name, ":p")
end

--- The platform's "open this in the GUI app for it" command.
--- @return string[]|nil argv, string|nil reason
function M.opener()
  if vim.fn.has("mac") == 1 then return { "open" } end
  if vim.fn.executable("xdg-open") == 1 then return { "xdg-open" } end
  if vim.fn.has("win32") == 1 then return { "cmd.exe", "/c", "start", "" } end
  return nil, "no system opener found (looked for open / xdg-open)"
end

return M
