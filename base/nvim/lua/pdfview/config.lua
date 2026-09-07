-- Configuration schema and validation for pdfview.
--
-- Every knob is declared here with its type and constraint, and `resolve`
-- rejects anything that does not match. A typo in a config key is the classic
-- way to spend an hour wondering why a setting "does nothing"; failing loudly
-- at setup() costs one line and saves that hour.

local M = {}

local function positive_integer(value)
  if value <= 0 or value ~= math.floor(value) then
    return "must be a positive integer"
  end
end

local function percent(value)
  if value <= 0 or value > 100 then return "must be between 1 and 100" end
end

local function one_of(choices)
  return function(value)
    if not vim.tbl_contains(choices, value) then
      return "must be one of: " .. table.concat(choices, ", ")
    end
  end
end

--- key -> { type, validate }
M.schema = {
  -- Rasterization resolution for the image view. 150 is a readable page on a
  -- laptop screen without making every render a half-second wait.
  dpi = { type = "number", validate = positive_integer },
  -- pdftotext -layout preserves columns and tables. Without it a two-column
  -- paper interleaves its columns line by line and is unreadable.
  preserve_layout = { type = "boolean" },
  show_page_headers = { type = "boolean" },
  page_separator = { type = "string" },
  extract_timeout_ms = { type = "number", validate = positive_integer },
  raster_timeout_ms = { type = "number", validate = positive_integer },
  image_split = { type = "string", validate = one_of({ "vertical", "horizontal" }) },
  image_size_percent = { type = "number", validate = percent },
  cache_dir = { type = "string" },
}

M.defaults = {
  dpi = 150,
  preserve_layout = true,
  show_page_headers = true,
  page_separator = "─",
  extract_timeout_ms = 15000,
  raster_timeout_ms = 20000,
  image_split = "vertical",
  image_size_percent = 50,
  cache_dir = vim.fn.stdpath("cache") .. "/pdfview",
}

--- Merge user options over the defaults, returning a NEW table.
--- Neither `M.defaults` nor `user` is modified.
--- @param user table|nil
--- @return table
function M.resolve(user)
  user = user or {}
  if type(user) ~= "table" then
    error("pdfview.setup expects a table of options, got " .. type(user), 2)
  end

  local resolved = vim.deepcopy(M.defaults)
  for key, value in pairs(user) do
    local rule = M.schema[key]
    if not rule then
      error(("pdfview: unknown option %q (valid: %s)"):format(
        key, table.concat(vim.tbl_keys(M.schema), ", ")), 2)
    end
    if type(value) ~= rule.type then
      error(("pdfview: option %q must be a %s, got %s"):format(
        key, rule.type, type(value)), 2)
    end
    local problem = rule.validate and rule.validate(value)
    if problem then
      error(("pdfview: option %q %s (got %s)"):format(key, problem, vim.inspect(value)), 2)
    end
    resolved[key] = value
  end
  return resolved
end

return M
