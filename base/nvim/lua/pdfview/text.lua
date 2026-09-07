-- Text extraction and the page model.
--
-- Everything in here is a plain function over strings and tables: no buffers,
-- no windows, no terminal. That is what makes the page arithmetic testable
-- headlessly, which is where nearly every bug in a viewer like this lives.

local util = require("pdfview.util")

local M = {}

-- poppler separates pages with a form feed and terminates the last page with
-- one too. This is the only page delimiter we get, so it is the whole model.
local PAGE_BREAK = "\f"

--- Split raw pdftotext output into per-page strings.
--- @param raw string
--- @return string[] a new list; `raw` is not modified
function M.split_pages(raw)
  if type(raw) ~= "string" or raw == "" then return {} end

  local pages = vim.split(raw, PAGE_BREAK, { plain = true })
  -- Drop the phantom page created by the trailing form feed. Only ever one:
  -- an interior blank page is a real page and must survive.
  if #pages > 0 and pages[#pages]:match("^%s*$") then
    table.remove(pages, #pages)
  end
  return pages
end

--- Does this extraction contain anything a human could read?
--- False for a scan or an image-only export, where poppler happily returns a
--- string of nothing but newlines and form feeds.
--- @param raw string|nil
--- @return boolean
function M.has_content(raw)
  if type(raw) ~= "string" then return false end
  return raw:match("[^%s\f]") ~= nil
end

--- Explanation shown in place of text when a PDF has no text layer.
--- @param page_count integer
--- @return string[]
function M.no_text_lines(page_count)
  return {
    "This PDF has no text layer to extract.",
    "",
    ("It is almost certainly a scan or an image-only export (%d page%s)."):format(
      page_count, page_count == 1 and "" or "s"),
    "",
    "  gi   render the current page as an image",
    "  go   open it in the system PDF viewer",
    "  g?   list every pdfview mapping",
  }
end

--- Explanation shown when extraction itself failed.
---
--- `reason` carries poppler's stderr, which is routinely several lines long.
--- Buffer lines may not contain newlines, so it is fanned out here rather than
--- exploding inside nvim_buf_set_lines with a message about "replacement
--- string item contains newlines" that says nothing about the actual PDF.
--- @param path string
--- @param reason string
--- @return string[]
function M.failure_lines(path, reason)
  local lines = {
    "Could not read this PDF.",
    "",
    "  file:   " .. path,
    "  reason:",
  }
  for _, line in ipairs(vim.split(vim.trim(reason or "unknown"), "\n", { plain = true })) do
    lines[#lines + 1] = "    " .. line
  end
  vim.list_extend(lines, {
    "",
    "  go   try opening it in the system PDF viewer",
    "  :PdfHealth   check the tools pdfview needs",
  })
  return lines
end

--- Run pdftotext over `path`.
--- @param path string
--- @param cfg table resolved config
--- @return string|nil raw, string|nil reason
function M.extract(path, cfg)
  if type(path) ~= "string" or path == "" then
    return nil, "no file path given"
  end
  if vim.fn.filereadable(path) ~= 1 then
    return nil, "file does not exist or is not readable"
  end

  local argv = { "pdftotext" }
  if cfg.preserve_layout then table.insert(argv, "-layout") end
  -- UTF-8 explicitly: the default encoding is locale-dependent, so the same
  -- document renders differently on a machine with a C locale.
  vim.list_extend(argv, { "-enc", "UTF-8", path, "-" })

  return util.run(argv, cfg.extract_timeout_ms)
end

--- Number of pages according to pdfinfo, which knows about pages that carry no
--- text at all. Falls back to `nil` when pdfinfo is unavailable.
--- @param path string
--- @param cfg table
--- @return integer|nil
function M.page_count(path, cfg)
  if vim.fn.executable("pdfinfo") ~= 1 then return nil end
  local out = util.run({ "pdfinfo", path }, cfg.extract_timeout_ms)
  if not out then return nil end
  local count = out:match("Pages:%s+(%d+)")
  return count and tonumber(count) or nil
end

local function header_line(page, total, cfg)
  local label = (" page %d/%d "):format(page, total)
  local rule = string.rep(cfg.page_separator, 4)
  return rule .. label .. rule
end

--- Turn per-page strings into the buffer's lines plus the page index.
---
--- Returns a NEW table every call; `pages` and `cfg` are read only.
--- @param pages string[]
--- @param cfg table resolved config
--- @return table view { lines: string[], page_starts: integer[], page_count: integer }
function M.build_view(pages, cfg)
  if type(pages) ~= "table" then
    error("pdfview.build_view expects a list of page strings", 2)
  end
  if #pages == 0 then
    return { lines = M.no_text_lines(0), page_starts = {}, page_count = 0 }
  end

  local lines, page_starts = {}, {}
  for index, page in ipairs(pages) do
    if index > 1 then lines[#lines + 1] = "" end
    if cfg.show_page_headers then
      lines[#lines + 1] = header_line(index, #pages, cfg)
    end

    local body = vim.split(page, "\n", { plain = true })
    -- pdftotext pads each page out to the bottom of the sheet; those trailing
    -- blank lines are whitespace on paper, not content, and they make ]p feel
    -- like it overshoots.
    while #body > 0 and body[#body]:match("^%s*$") do
      table.remove(body, #body)
    end
    -- A genuinely blank page still needs one line so it has a start to jump to.
    if #body == 0 then body = { "" } end

    page_starts[index] = #lines + 1
    vim.list_extend(lines, body)
  end

  return { lines = lines, page_starts = page_starts, page_count = #pages }
end

--- Which page contains buffer line `lnum`.
--- Clamped at both ends so a cursor on a header or past the last line still
--- answers with a real page.
--- @param view table
--- @param lnum integer
--- @return integer
function M.page_at(view, lnum)
  local page = 1
  for index, start in ipairs(view.page_starts) do
    if lnum >= start then page = index else break end
  end
  return page
end

return M
