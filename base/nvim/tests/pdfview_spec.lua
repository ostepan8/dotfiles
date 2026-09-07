-- Test suite for the pdfview module (nvim reading PDFs in Ghostty/tmux).
-- Run with: base/nvim/tests/run.sh

local h = require("harness")
local fixture = require("pdf_fixture")

local config = require("pdfview.config")
local text = require("pdfview.text")
local render = require("pdfview.render")

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

local THREE_PAGE = fixture.write(tmp .. "/three.pdf", {
  "ALPHA page one marker",
  "BRAVO page two marker",
  "CHARLIE page three marker",
})
-- Pages that exist but carry no text: the shape of a scanned document.
local SCANNED = fixture.write(tmp .. "/scanned.pdf", { "", "" })
local NOT_A_PDF = tmp .. "/decoy.pdf"
vim.fn.writefile({ "this is plainly not a PDF" }, NOT_A_PDF)

io.write("\nconfig\n")

h.test("resolve returns a new table and never mutates the defaults", function()
  local before = vim.deepcopy(config.defaults)
  local resolved = h.capture_notifications(function() end) and config.resolve({ dpi = 300 })
  h.eq(resolved.dpi, 300, "override applied")
  h.truthy(resolved ~= config.defaults, "resolved is a distinct table")
  h.eq(vim.inspect(config.defaults), vim.inspect(before), "defaults untouched")
end)

h.test("resolve fills unspecified keys from the defaults", function()
  local resolved = config.resolve({ dpi = 300 })
  h.eq(resolved.page_separator, config.defaults.page_separator, "untouched key inherited")
end)

h.test("resolve rejects an unknown key instead of silently ignoring it", function()
  h.errors(function() config.resolve({ dpy = 300 }) end, "unknown key")
end)

h.test("resolve rejects a value of the wrong type", function()
  h.errors(function() config.resolve({ dpi = "300" }) end, "wrong type")
end)

h.test("resolve rejects a non-positive dpi", function()
  h.errors(function() config.resolve({ dpi = 0 }) end, "zero dpi")
end)

io.write("\ntext: page splitting\n")

h.test("split_pages splits on the form feed poppler emits", function()
  local pages = text.split_pages("one\n\fttwo\n\f")
  h.eq(#pages, 2, "page count")
  h.contains(pages[1], "one", "first page")
end)

h.test("split_pages drops the trailing empty page from the final form feed", function()
  local pages = text.split_pages("only\n\f")
  h.eq(#pages, 1, "page count")
end)

h.test("split_pages returns an empty list for empty input", function()
  h.eq(#text.split_pages(""), 0, "page count")
end)

h.test("split_pages keeps interior blank pages", function()
  local pages = text.split_pages("one\n\f\f three\n\f")
  h.eq(#pages, 3, "page count")
end)

io.write("\ntext: view construction\n")

local function three_page_view()
  return text.build_view({ "a1\na2", "b1", "c1\nc2\nc3" }, config.defaults)
end

h.test("build_view reports the page count", function()
  h.eq(three_page_view().page_count, 3, "page_count")
end)

h.test("build_view records a start line for every page", function()
  local view = three_page_view()
  h.eq(#view.page_starts, 3, "page_starts length")
  for i = 1, 3 do
    h.truthy(view.page_starts[i] >= 1, "page " .. i .. " start is a real line")
  end
end)

h.test("build_view page_starts point at that page's first content line", function()
  local view = three_page_view()
  h.contains(view.lines[view.page_starts[1]], "a1", "page 1 start")
  h.contains(view.lines[view.page_starts[2]], "b1", "page 2 start")
  h.contains(view.lines[view.page_starts[3]], "c1", "page 3 start")
end)

h.test("build_view does not mutate the pages it is given", function()
  local pages = { "a1\na2", "b1" }
  local before = vim.inspect(pages)
  text.build_view(pages, config.defaults)
  h.eq(vim.inspect(pages), before, "input pages")
end)

h.test("build_view renders a page header when headers are enabled", function()
  local view = text.build_view({ "a" }, config.resolve({ show_page_headers = true }))
  h.contains(table.concat(view.lines, "\n"), "page 1", "header text")
end)

h.test("build_view omits headers when they are disabled", function()
  local view = text.build_view({ "a" }, config.resolve({ show_page_headers = false }))
  h.eq(#view.lines, 1, "line count with no header")
end)

h.test("build_view of zero pages yields a non-empty explanatory buffer", function()
  local view = text.build_view({}, config.defaults)
  h.eq(view.page_count, 0, "page_count")
  h.truthy(#view.lines > 0, "still says something to the reader")
end)

io.write("\ntext: page lookup\n")

h.test("page_at maps a line inside each page back to that page", function()
  local view = three_page_view()
  for i = 1, 3 do
    h.eq(text.page_at(view, view.page_starts[i]), i, "page " .. i)
  end
end)

h.test("page_at maps a line after a page start to the same page", function()
  local view = three_page_view()
  h.eq(text.page_at(view, view.page_starts[3] + 2), 3, "deep inside page 3")
end)

h.test("page_at clamps a line above the last page start", function()
  local view = three_page_view()
  h.eq(text.page_at(view, 10000), 3, "past the end")
end)

h.test("page_at clamps a line before the first page", function()
  local view = three_page_view()
  h.eq(text.page_at(view, 1), 1, "line 1")
end)

io.write("\ntext: extraction\n")

h.test("extract pulls the text layer out of a real PDF", function()
  local raw, err = text.extract(THREE_PAGE, config.defaults)
  h.falsy(err, "no error")
  h.contains(raw, "ALPHA", "page 1 marker")
  h.contains(raw, "BRAVO", "page 2 marker")
  h.contains(raw, "CHARLIE", "page 3 marker")
end)

h.test("extract reports an error for a missing file rather than returning empty", function()
  local raw, err = text.extract(tmp .. "/nope.pdf", config.defaults)
  h.falsy(raw, "no text")
  h.truthy(err and #err > 0, "error message present")
end)

h.test("failure_lines never emits a line containing a newline", function()
  -- poppler's stderr is routinely multi-line, and a buffer line may not
  -- contain a newline. Getting this wrong replaces the real error with an
  -- nvim_buf_set_lines stack trace.
  local lines = text.failure_lines("/tmp/x.pdf", "Syntax Error: couldn't find trailer\nError: Failed")
  for _, line in ipairs(lines) do
    h.falsy(line:find("\n", 1, true), "line without a newline: " .. vim.inspect(line))
  end
  h.contains(table.concat(lines, "\n"), "couldn't find trailer", "reason preserved")
end)

h.test("extract reports an error for a file that is not a PDF", function()
  local raw, err = text.extract(NOT_A_PDF, config.defaults)
  h.falsy(raw, "no text")
  h.truthy(err and #err > 0, "error message present")
end)

h.test("extract of a text-free PDF succeeds but yields no pages with content", function()
  local raw, err = text.extract(SCANNED, config.defaults)
  h.falsy(err, "no error - the file is valid, it just has no text layer")
  h.falsy(text.has_content(raw), "has_content is false")
end)

h.test("has_content is true for a PDF that does have a text layer", function()
  local raw = text.extract(THREE_PAGE, config.defaults)
  h.truthy(text.has_content(raw), "has_content")
end)

io.write("\nrender: rasterization plumbing\n")

h.test("raster_argv passes the page range and dpi as separate argv entries", function()
  local argv = render.raster_argv(THREE_PAGE, 2, 150, "/tmp/out")
  h.eq(argv[1], "pdftoppm", "program")
  local joined = table.concat(argv, " ")
  h.contains(joined, "-f 2", "first page")
  h.contains(joined, "-l 2", "last page")
  h.contains(joined, "-r 150", "resolution")
  h.contains(joined, "-singlefile", "single output file")
  h.eq(argv[#argv - 1], THREE_PAGE, "source pdf is its own argv entry")
  h.eq(argv[#argv], "/tmp/out", "output prefix is its own argv entry")
end)

h.test("raster_argv keeps a path with spaces in one unquoted argv entry", function()
  local argv = render.raster_argv("/tmp/a b/c d.pdf", 1, 96, "/tmp/o")
  h.eq(argv[#argv - 1], "/tmp/a b/c d.pdf", "no shell quoting applied")
end)

h.test("raster_argv rejects a page number that is not a positive integer", function()
  h.errors(function() render.raster_argv(THREE_PAGE, 0, 150, "/tmp/o") end, "page 0")
  h.errors(function() render.raster_argv(THREE_PAGE, 1.5, 150, "/tmp/o") end, "fractional page")
end)

h.test("cache_key distinguishes pages and dpi", function()
  local a = render.cache_key(THREE_PAGE, 1, 150)
  h.truthy(a ~= render.cache_key(THREE_PAGE, 2, 150), "page differs")
  h.truthy(a ~= render.cache_key(THREE_PAGE, 1, 300), "dpi differs")
  h.eq(a, render.cache_key(THREE_PAGE, 1, 150), "stable for identical inputs")
end)

h.test("cache_key changes when the PDF itself changes", function()
  local churn = fixture.write(tmp .. "/churn.pdf", { "first" })
  local before = render.cache_key(churn, 1, 150)
  vim.fn.system({ "touch", "-t", "203001010000", churn })
  h.truthy(before ~= render.cache_key(churn, 1, 150), "mtime is part of the key")
end)

h.test("staging_target never collides with the cache target", function()
  local cfg = config.resolve({ cache_dir = tmp .. "/cache" })
  local _, cached = render.cache_target(cfg, THREE_PAGE, 1)
  local _, staged = render.staging_target(cfg, THREE_PAGE, 1)
  h.truthy(cached ~= staged, "distinct paths")
  h.contains(staged, "staging", "staging path is recognisable")
end)

h.test("promote moves a finished render onto its cache key", function()
  local from, to = tmp .. "/from.png", tmp .. "/to.png"
  vim.fn.writefile({ "png bytes" }, from)
  local ok, reason = render.promote(from, to)
  h.truthy(ok, "promoted: " .. tostring(reason))
  h.eq(vim.fn.filereadable(to), 1, "destination exists")
  h.eq(vim.fn.filereadable(from), 0, "staging file consumed")
end)

h.test("promote refuses when the renderer produced nothing", function()
  -- The failure this guards: a render killed halfway leaves a truncated PNG
  -- that is then a cache HIT forever, so the page renders blank every time.
  local ok, reason = render.promote(tmp .. "/never-written.png", tmp .. "/dest.png")
  h.falsy(ok, "not promoted")
  h.truthy(reason and #reason > 0, "reason given")
  h.eq(vim.fn.filereadable(tmp .. "/dest.png"), 0, "nothing landed on the cache key")
end)

io.write("\nintegration: opening a PDF\n")

require("pdfview").setup()

local function open(path)
  vim.cmd("silent! %bwipeout!")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

h.test("editing a .pdf yields a readonly scratch buffer, not raw bytes", function()
  local buf = open(THREE_PAGE)
  h.eq(vim.bo[buf].buftype, "nofile", "buftype")
  h.falsy(vim.bo[buf].modifiable, "modifiable")
  h.eq(vim.bo[buf].filetype, "pdf", "filetype")
end)

h.test("the buffer keeps the PDF's own name so :ls and % still make sense", function()
  local buf = open(THREE_PAGE)
  -- Compared through resolve(): on macOS the temp dir is itself a symlink
  -- (/var -> /private/var) and nvim stores the resolved form.
  h.eq(vim.fn.resolve(vim.api.nvim_buf_get_name(buf)), vim.fn.resolve(THREE_PAGE), "buffer name")
end)

h.test("the buffer holds the extracted text of every page", function()
  local buf = open(THREE_PAGE)
  local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  h.contains(body, "ALPHA", "page 1")
  h.contains(body, "BRAVO", "page 2")
  h.contains(body, "CHARLIE", "page 3")
end)

h.test("the view is attached to the buffer for page-aware commands", function()
  local buf = open(THREE_PAGE)
  h.eq(vim.b[buf].pdfview.page_count, 3, "page_count")
end)

h.test(":PdfPage jumps the cursor to that page", function()
  open(THREE_PAGE)
  vim.cmd("PdfPage 3")
  h.contains(vim.api.nvim_get_current_line(), "CHARLIE", "line under cursor")
end)

h.test(":PdfPage past the end reports an error and leaves the cursor put", function()
  open(THREE_PAGE)
  vim.cmd("PdfPage 2")
  local before = vim.api.nvim_win_get_cursor(0)
  local notes = h.capture_notifications(function() vim.cmd("PdfPage 99") end)
  h.truthy(#notes > 0, "user was told")
  h.eq(notes[1].level, vim.log.levels.ERROR, "severity")
  h.eq(vim.api.nvim_win_get_cursor(0)[1], before[1], "cursor unchanged")
end)

h.test(":PdfPage with a non-numeric argument is rejected", function()
  open(THREE_PAGE)
  local notes = h.capture_notifications(function() vim.cmd("PdfPage banana") end)
  h.truthy(#notes > 0, "user was told")
end)

h.test("]p and [p walk forward and back through pages", function()
  open(THREE_PAGE)
  vim.cmd("PdfPage 1")
  vim.cmd("normal ]p")
  h.contains(vim.api.nvim_get_current_line(), "BRAVO", "after ]p")
  vim.cmd("normal [p")
  h.contains(vim.api.nvim_get_current_line(), "ALPHA", "after [p")
end)

h.test("]p on the last page stays on the last page", function()
  open(THREE_PAGE)
  vim.cmd("PdfPage 3")
  vim.cmd("normal ]p")
  h.contains(vim.api.nvim_get_current_line(), "CHARLIE", "still page 3")
end)

h.test("a PDF with no text layer opens with a readable explanation", function()
  local buf = open(SCANNED)
  local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  h.truthy(#body > 0, "buffer is not silently empty")
  h.contains(body:lower(), "no text", "explains the situation")
end)

h.test("a corrupt PDF opens with the extraction error visible in the buffer", function()
  local buf = open(NOT_A_PDF)
  local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  h.truthy(#body > 0, "buffer is not silently empty")
  h.contains(body:lower(), "could not", "explains the failure")
end)

h.test("pdfview commands are not defined in an ordinary buffer", function()
  vim.cmd("silent! %bwipeout!")
  vim.cmd("enew")
  h.errors(function() vim.cmd("PdfPage 1") end, "PdfPage outside a pdf buffer")
end)

io.write("\nterminal graphics detection\n")

local classify = require("pdfview.deps").classify_terminal

h.test("a bare Ghostty session is recognised", function()
  local status = classify({ term = "xterm-ghostty", term_program = "ghostty", ghostty = true })
  h.eq(status, "yes", "status")
end)

h.test("Ghostty is recognised THROUGH tmux, via the attached client", function()
  -- The bug this exists for: inside tmux, TERM is tmux-256color and
  -- TERM_PROGRAM is "tmux", so sniffing them disables the image view on the
  -- exact setup it was written for. tmux's own global environment is worse
  -- still — it keeps whatever launched the server, which for a session
  -- restored at boot is a completely different terminal.
  local status, detail = classify({
    term = "tmux-256color",
    term_program = "tmux",
    tmux = true,
    tmux_client_term = "xterm-ghostty",
  })
  h.eq(status, "yes", "status")
  h.contains(detail, "ghostty", "detail names the real terminal")
end)

h.test("kitty through tmux is recognised", function()
  h.eq(classify({ term = "tmux-256color", tmux = true, tmux_client_term = "xterm-kitty" }),
    "yes", "status")
end)

h.test("an unrecognised tmux client is unknown, never a flat no", function()
  h.eq(classify({ term = "tmux-256color", tmux = true, tmux_client_term = "xterm-256color" }),
    "unknown", "status")
end)

h.test("tmux that will not answer is unknown, not a flat no", function()
  h.eq(classify({ term = "tmux-256color", tmux = true, tmux_client_term = nil }),
    "unknown", "status")
end)

h.test("a headless run with no TERM is a definite no", function()
  h.eq(classify({ term = nil }), "no", "unset")
  h.eq(classify({ term = "" }), "no", "empty")
  h.eq(classify({ term = "dumb" }), "no", "dumb")
end)

h.test("a plain xterm outside tmux is unknown, not a flat no", function()
  h.eq(classify({ term = "xterm-256color", term_program = "Apple_Terminal" }),
    "unknown", "status")
end)

h.test("the marker variable alone is enough outside tmux", function()
  h.eq(classify({ term = "xterm-256color", kitty = true }), "yes", "KITTY_WINDOW_ID")
  h.eq(classify({ term = "xterm-256color", ghostty = true }), "yes", "GHOSTTY_RESOURCES_DIR")
end)

h.test("classify always returns a detail string a human can act on", function()
  for _, env in ipairs({
    { term = "xterm-ghostty", ghostty = true },
    { term = "tmux-256color", tmux = true, tmux_client_term = "xterm-256color" },
    { term = "dumb" },
  }) do
    local _, detail = classify(env)
    h.truthy(type(detail) == "string" and #detail > 0, "detail for " .. vim.inspect(env))
  end
end)

h.test("the image plugin loads for anything but a definite no", function()
  local deps = require("pdfview.deps")
  h.truthy(deps.graphics_possible ~= nil, "graphics_possible exists")
  h.eq(type(deps.graphics_possible()), "boolean", "returns a boolean")
end)

io.write("\nhealth\n")

h.test("health reports on every external tool the feature needs", function()
  local report = require("pdfview.deps").health()
  local names = {}
  for _, item in ipairs(report) do names[item.name] = item end
  h.truthy(names["pdftotext"], "pdftotext checked")
  h.truthy(names["pdftoppm"], "pdftoppm checked")
  h.truthy(names["image.nvim"], "image.nvim checked")
end)

h.test("health marks the text path as available on a machine with poppler", function()
  local report = require("pdfview.deps").health()
  for _, item in ipairs(report) do
    if item.name == "pdftotext" then h.truthy(item.ok, "pdftotext found") end
  end
end)

h.finish()
