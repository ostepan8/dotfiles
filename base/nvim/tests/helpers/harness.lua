-- Dependency-free test harness. Deliberately not plenary/busted: the nvim
-- config must be testable on a machine that has not yet installed any plugin,
-- which is exactly the machine most likely to be broken.

local M = { failures = {}, passed = 0, current = "?" }

local function fail(msg)
  M.failures[#M.failures + 1] = ("%s: %s"):format(M.current, msg)
end

function M.test(name, fn)
  M.current = name
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
    io.write(("  ok   %s\n"):format(name))
  else
    fail(tostring(err))
    io.write(("  FAIL %s\n         %s\n"):format(name, tostring(err)))
  end
end

function M.eq(actual, expected, what)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(
      what or "value", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function M.truthy(value, what)
  if not value then
    error(("%s: expected truthy, got %s"):format(what or "value", vim.inspect(value)), 2)
  end
end

function M.falsy(value, what)
  if value then
    error(("%s: expected falsy, got %s"):format(what or "value", vim.inspect(value)), 2)
  end
end

function M.contains(haystack, needle, what)
  if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
    error(("%s: %s does not contain %q"):format(
      what or "string", vim.inspect(haystack), needle), 2)
  end
end

function M.errors(fn, what)
  local ok = pcall(fn)
  if ok then
    error(("%s: expected an error, but the call succeeded"):format(what or "call"), 2)
  end
end

--- Capture everything routed through vim.notify while `fn` runs.
--- Restores the original notifier even when `fn` throws.
function M.capture_notifications(fn)
  local captured = {}
  local original = vim.notify
  vim.notify = function(msg, level) captured[#captured + 1] = { msg = msg, level = level } end
  local ok, err = pcall(fn)
  vim.notify = original
  if not ok then error(err, 0) end
  return captured
end

function M.finish()
  io.write(("\n%d passed, %d failed\n"):format(M.passed, #M.failures))
  vim.cmd(#M.failures == 0 and "cquit 0" or "cquit 1")
end

return M
