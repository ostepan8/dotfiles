-- Turning a .pdf buffer into something you can actually read, and the
-- page-aware navigation that goes with it.

local config = require("pdfview.config")
local render = require("pdfview.render")
local text = require("pdfview.text")
local util = require("pdfview.util")

local M = {}

-- buffer -> view table from text.build_view, plus the source path and config.
-- Kept out of `vim.b` because vim variables round-trip through vimscript types
-- and we want the exact Lua table back.
local views = {}

M.mappings = {
  { keys = "]p", desc = "next page" },
  { keys = "[p", desc = "previous page" },
  { keys = "gi", desc = "toggle the rendered image of the current page" },
  { keys = "go", desc = "open in the system PDF viewer" },
  { keys = "gr", desc = "re-extract the PDF from disk" },
  { keys = "g?", desc = "show this list" },
}

--- @param buf integer
--- @return table|nil
function M.view(buf)
  return views[buf]
end

--- The page the cursor is currently sitting in.
--- @param buf integer
--- @return integer
function M.current_page(buf)
  local state = views[buf]
  if not state or #state.view.page_starts == 0 then return 1 end
  local win = vim.fn.bufwinid(buf)
  local lnum = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or 1
  return text.page_at(state.view, lnum)
end

--- @param buf integer
--- @param page integer
function M.goto_page(buf, page)
  local state = views[buf]
  if not state then
    util.err("this buffer is not a pdfview buffer")
    return
  end
  if #state.view.page_starts == 0 then
    util.err("this PDF has no text layer to navigate — press gi to render it instead")
    return
  end
  if type(page) ~= "number" or page ~= math.floor(page) then
    util.err("page must be a whole number")
    return
  end
  if page < 1 or page > state.view.page_count then
    util.err(("page %d is out of range (this PDF has %d)"):format(page, state.view.page_count))
    return
  end

  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    util.err("this PDF is not displayed in any window")
    return
  end

  vim.api.nvim_win_set_cursor(win, { state.view.page_starts[page], 0 })
  vim.api.nvim_win_call(win, function() vim.cmd("normal! zt") end)
  util.echo(("pdfview: page %d/%d"):format(page, state.view.page_count))
  render.follow(buf, state.path, page, state.config)
end

--- @param buf integer
--- @param delta integer +1 or -1
function M.step_page(buf, delta)
  local state = views[buf]
  if not state then return end
  local target = M.current_page(buf) + delta
  -- Clamp rather than error: holding ]p to the end of a document is normal use,
  -- not a mistake worth an error bell.
  target = math.max(1, math.min(target, math.max(state.view.page_count, 1)))
  M.goto_page(buf, target)
end

--- @param buf integer
function M.open_externally(buf)
  local state = views[buf]
  if not state then return end
  local argv, reason = util.opener()
  if not argv then
    util.err(reason)
    return
  end
  local ok, err = pcall(vim.system, vim.list_extend(vim.deepcopy(argv), { state.path }))
  if not ok then
    util.err("could not open the system viewer: " .. tostring(err))
    return
  end
  util.echo("pdfview: opened " .. vim.fn.fnamemodify(state.path, ":t"))
end

--- @param buf integer
function M.toggle_image(buf)
  local state = views[buf]
  if not state then return end
  render.toggle(buf, state.path, M.current_page(buf), state.config)
end

function M.show_help()
  local chunks = { { "pdfview mappings\n", "Title" } }
  for _, item in ipairs(M.mappings) do
    chunks[#chunks + 1] = { ("  %-4s %s\n"):format(item.keys, item.desc), "Normal" }
  end
  chunks[#chunks + 1] = { "  :PdfPage N   jump to a page\n", "Normal" }
  chunks[#chunks + 1] = { "  :PdfHealth   check pdfview's dependencies\n", "Normal" }
  vim.api.nvim_echo(chunks, true, {})
end

local function define_commands(buf)
  local command = function(name, fn, opts)
    vim.api.nvim_buf_create_user_command(buf, name, fn, opts or {})
  end

  command("PdfPage", function(args)
    local page = tonumber(args.args)
    if not page then
      util.err(("%q is not a page number"):format(args.args))
      return
    end
    M.goto_page(buf, page)
  end, { nargs = 1, desc = "pdfview: jump to a page" })

  command("PdfImage", function() M.toggle_image(buf) end,
    { desc = "pdfview: toggle the rendered page image" })
  command("PdfOpen", function() M.open_externally(buf) end,
    { desc = "pdfview: open in the system viewer" })
  command("PdfReload", function() M.open(buf, views[buf].path, views[buf].config) end,
    { desc = "pdfview: re-extract from disk" })
end

local function define_mappings(buf)
  local map = function(keys, fn, desc)
    vim.keymap.set("n", keys, fn, { buffer = buf, silent = true, desc = "pdfview: " .. desc })
  end
  map("]p", function() M.step_page(buf, 1) end, "next page")
  map("[p", function() M.step_page(buf, -1) end, "previous page")
  map("gi", function() M.toggle_image(buf) end, "toggle page image")
  map("go", function() M.open_externally(buf) end, "open in system viewer")
  map("gr", function() M.open(buf, views[buf].path, views[buf].config) end, "reload")
  map("g?", M.show_help, "show mappings")
end

local function write_lines(buf, lines)
  -- Defensive flatten: a buffer line may not contain a newline, and the strings
  -- here come from external tools whose output shape we do not control.
  local flat = {}
  for _, line in ipairs(lines) do
    vim.list_extend(flat, vim.split(line, "\n", { plain = true }))
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, flat)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

--- Build the readable view of `path` into `buf`.
--- Never throws: an unreadable PDF becomes a buffer that explains why, because
--- this runs inside a BufReadCmd where an error is just a stack trace over the
--- file the user was trying to look at.
--- @param buf integer
--- @param path string
--- @param cfg table resolved config
function M.open(buf, path, cfg)
  cfg = cfg or config.defaults

  local raw, reason = text.extract(path, cfg)
  local view
  if not raw then
    view = { lines = text.failure_lines(path, reason), page_starts = {}, page_count = 0 }
  elseif not text.has_content(raw) then
    local count = text.page_count(path, cfg) or #text.split_pages(raw)
    view = { lines = text.no_text_lines(count), page_starts = {}, page_count = 0 }
  else
    view = text.build_view(text.split_pages(raw), cfg)
  end

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undolevels = -1
  write_lines(buf, view.lines)
  vim.bo[buf].undolevels = vim.o.undolevels
  vim.bo[buf].filetype = "pdf"

  views[buf] = { view = view, path = path, config = cfg }
  vim.b[buf].pdfview = { path = path, page_count = view.page_count }

  define_commands(buf)
  define_mappings(buf)

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    buffer = buf,
    once = true,
    callback = function()
      render.close(buf)
      views[buf] = nil
    end,
  })
end

return M
