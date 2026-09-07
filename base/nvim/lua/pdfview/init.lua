-- pdfview — read PDFs inside Neovim.
--
-- Opening a .pdf gives you its text, searchable and yankable like any other
-- buffer, with page-aware navigation. `gi` additionally renders the current
-- page as an actual image in the terminal, for the figures and equations that
-- text extraction cannot carry.
--
--   :PdfPage N   jump to a page          ]p / [p   next / previous page
--   :PdfImage    toggle the page image   gi        same
--   :PdfOpen     system PDF viewer       go        same
--   :PdfHealth   dependency check        g?        list mappings
--
-- Requires poppler (`brew install poppler`) for text, and additionally
-- 3rd/image.nvim plus a Kitty-graphics terminal (Ghostty, Kitty) for images.

local buffer = require("pdfview.buffer")
local config = require("pdfview.config")
local deps = require("pdfview.deps")
local util = require("pdfview.util")

local M = {}

M.config = nil

--- @param user table|nil see pdfview.config.schema
function M.setup(user)
  M.config = config.resolve(user)

  local group = vim.api.nvim_create_augroup("pdfview", { clear = true })

  -- BufReadCmd, not BufReadPost: it replaces the read entirely, so nvim never
  -- loads the PDF's binary bytes into the buffer in the first place.
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = { "*.pdf", "*.PDF" },
    callback = function(args)
      local path = util.abspath(args.match)
      local ok, err = pcall(buffer.open, args.buf, path, M.config)
      if not ok then
        util.err("failed to open " .. path .. ": " .. tostring(err))
      end
    end,
  })

  vim.api.nvim_create_user_command("PdfHealth", deps.show,
    { desc = "pdfview: check dependencies" })
end

return M
