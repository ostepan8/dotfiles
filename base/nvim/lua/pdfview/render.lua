-- Image view: rasterize one page with pdftoppm and paint it with image.nvim
-- over the Kitty graphics protocol (which Ghostty implements).
--
-- pdftoppm rather than ImageMagick's own PDF delegate: `magick page.pdf` shells
-- out to Ghostscript, which is a second heavyweight dependency and is not
-- installed here. poppler already has to be present for the text view, so the
-- image view adds no new dependency at all.

local deps = require("pdfview.deps")
local util = require("pdfview.util")

local M = {}

-- buffer -> { win, buf, image, page }. Runtime handles only; nothing here is
-- ever written back into the caller's tables.
local sessions = {}

--- Build the pdftoppm command line. Pure, and returns argv as a list so paths
--- with spaces or quotes never touch a shell.
--- @param path string
--- @param page integer
--- @param dpi integer
--- @param out_prefix string pdftoppm appends ".png"
--- @return string[]
function M.raster_argv(path, page, dpi, out_prefix)
  if type(page) ~= "number" or page <= 0 or page ~= math.floor(page) then
    error(("pdfview: page must be a positive integer, got %s"):format(vim.inspect(page)), 2)
  end
  if type(dpi) ~= "number" or dpi <= 0 or dpi ~= math.floor(dpi) then
    error(("pdfview: dpi must be a positive integer, got %s"):format(vim.inspect(dpi)), 2)
  end
  return {
    "pdftoppm",
    "-png",
    "-singlefile",
    "-r", tostring(dpi),
    "-f", tostring(page),
    "-l", tostring(page),
    path,
    out_prefix,
  }
end

--- Cache identity for one rendered page.
--- Includes the file's mtime and size so editing the PDF under us invalidates
--- the cached PNG instead of showing a stale page forever.
--- @param path string
--- @param page integer
--- @param dpi integer
--- @return string
function M.cache_key(path, page, dpi)
  local stamp = ("%s:%d:%d:%d:%d"):format(
    path, page, dpi, vim.fn.getftime(path), vim.fn.getfsize(path))
  return vim.fn.sha256(stamp)
end

--- Final resting place of a rendered page. pdftoppm appends ".png" to a
--- prefix, so both forms are needed.
--- @return string prefix, string png
function M.cache_target(cfg, path, page)
  local prefix = ("%s/%s"):format(cfg.cache_dir, M.cache_key(path, page, cfg.dpi))
  return prefix, prefix .. ".png"
end

--- Where pdftoppm actually writes.
---
--- Never the cache path itself: a render interrupted halfway — quit nvim, kill
--- the pane, hit the timeout — leaves a truncated PNG behind, and since the
--- cache is keyed on the PDF rather than on the image, that corpse is a cache
--- HIT for every later render of the same page. The page would then be silently
--- blank forever. Rendering to a staging name and renaming on success means a
--- partial file can never occupy the key.
--- @return string prefix, string png
function M.staging_target(cfg, path, page)
  local prefix = ("%s/.staging-%s-%d"):format(
    cfg.cache_dir, M.cache_key(path, page, cfg.dpi), vim.uv.getpid())
  return prefix, prefix .. ".png"
end

--- Move a finished render onto its cache key. Atomic: same directory, so this
--- is a rename within one filesystem.
--- @param from string
--- @param to string
--- @return boolean ok, string|nil reason
function M.promote(from, to)
  if vim.fn.filereadable(from) ~= 1 then
    return false, "the renderer produced no image"
  end
  local ok, err = vim.uv.fs_rename(from, to)
  if not ok then return false, tostring(err) end
  return true
end

local function close_session(buf)
  local session = sessions[buf]
  if not session then return end
  if session.image then pcall(function() session.image:clear() end) end
  if session.win and vim.api.nvim_win_is_valid(session.win) then
    pcall(vim.api.nvim_win_close, session.win, true)
  end
  sessions[buf] = nil
end

--- Is the image view currently open for this buffer?
--- @param buf integer
--- @return boolean
function M.is_open(buf)
  local session = sessions[buf]
  return session ~= nil and session.win ~= nil and vim.api.nvim_win_is_valid(session.win)
end

function M.close(buf)
  close_session(buf)
end

local function open_window(cfg)
  local origin = vim.api.nvim_get_current_win()
  if cfg.image_split == "horizontal" then
    vim.cmd(("belowright %dsplit"):format(
      math.floor(vim.o.lines * cfg.image_size_percent / 100)))
  else
    vim.cmd(("vertical rightbelow %dsplit"):format(
      math.floor(vim.o.columns * cfg.image_size_percent / 100)))
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "pdfimage"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false
  vim.wo[win].winfixwidth = true
  vim.api.nvim_set_current_win(origin)
  return win, buf
end

local function place(source_buf, png, page)
  local ok, image_api = pcall(require, "image")
  if not ok then
    util.err("image.nvim is not installed — :PdfHealth explains how to add it")
    return
  end

  local session = sessions[source_buf]
  if not session or not vim.api.nvim_win_is_valid(session.win) then return end

  if session.image then pcall(function() session.image:clear() end) end

  local placed, image = pcall(image_api.from_file, png, {
    id = ("pdfview:%d"):format(source_buf),
    window = session.win,
    buffer = session.buf,
    x = 0,
    y = 0,
    width = vim.api.nvim_win_get_width(session.win),
    height = vim.api.nvim_win_get_height(session.win),
  })
  if not placed then
    util.err("image.nvim could not load the rendered page: " .. tostring(image))
    return
  end

  local rendered = pcall(function() image:render() end)
  if not rendered then
    util.err("image.nvim could not display the page — check :PdfHealth")
    return
  end

  sessions[source_buf] = vim.tbl_extend("force", session, { image = image, page = page })
end

--- Show `page` of `path` in the image window for `buf`, opening that window if
--- it is not already up. Rasterization runs asynchronously: a 300-dpi page of a
--- dense document takes long enough that doing it inline stutters the editor.
--- @param buf integer the text buffer the image belongs to
--- @param path string
--- @param page integer
--- @param cfg table
function M.show(buf, path, page, cfg)
  if not deps.have("pdftoppm") then
    util.err("pdftoppm not found — install poppler (brew install poppler)")
    return
  end

  local graphics_ok, graphics_reason = deps.graphics_capable()
  if not graphics_ok then util.warn(graphics_reason) end
  local tmux_ok, tmux_reason = deps.tmux_ready()
  if not tmux_ok then util.warn(tmux_reason) end

  if not M.is_open(buf) then
    local win, image_buf = open_window(cfg)
    sessions[buf] = { win = win, buf = image_buf }
  end

  if vim.fn.isdirectory(cfg.cache_dir) ~= 1 then
    vim.fn.mkdir(cfg.cache_dir, "p")
  end

  local _, png = M.cache_target(cfg, path, page)
  if vim.fn.filereadable(png) == 1 then
    place(buf, png, page)
    return
  end

  local staging_prefix, staging_png = M.staging_target(cfg, path, page)
  util.echo(("pdfview: rendering page %d…"):format(page))
  local started, proc = pcall(vim.system,
    M.raster_argv(path, page, cfg.dpi, staging_prefix), { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        os.remove(staging_png)
        util.err(("pdftoppm failed on page %d: %s"):format(
          page, vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or
          ("exit code " .. result.code)))
        return
      end

      local promoted, reason = M.promote(staging_png, png)
      if not promoted then
        os.remove(staging_png)
        util.err(("could not cache page %d: %s"):format(page, reason))
        return
      end
      place(buf, png, page)
    end))

  if not started then
    util.err("could not start pdftoppm: " .. tostring(proc))
    return
  end

  -- A wedged rasterizer must not leak a process for the rest of the session.
  vim.defer_fn(function()
    if proc.pid and not proc:is_closing() then pcall(function() proc:kill("sigkill") end) end
  end, cfg.raster_timeout_ms)
end

--- Toggle the image view for `buf`.
--- @param buf integer
--- @param path string
--- @param page integer
--- @param cfg table
function M.toggle(buf, path, page, cfg)
  if M.is_open(buf) then
    close_session(buf)
    util.echo("pdfview: image view closed")
  else
    M.show(buf, path, page, cfg)
  end
end

--- Re-render the open image window at a new page. No-op when it is closed, so
--- page navigation can call it unconditionally.
--- @param buf integer
--- @param path string
--- @param page integer
--- @param cfg table
function M.follow(buf, path, page, cfg)
  local session = sessions[buf]
  if not M.is_open(buf) or session.page == page then return end
  M.show(buf, path, page, cfg)
end

return M
