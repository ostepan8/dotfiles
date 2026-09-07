-- Builds a minimal, valid, uncompressed PDF on disk so the pdfview tests have a
-- deterministic input with a known text layer and known page count.
--
-- Hand-rolled on purpose: the test suite must run on a bare machine (CI, a
-- fresh laptop, a headless server) where LaTeX / reportlab / ghostscript may not
-- exist. Everything below is plain PDF 1.4 with a Type1 base-14 font, which
-- poppler's pdftotext reads without any external dependency.

local M = {}

local PAGE_WIDTH, PAGE_HEIGHT = 612, 792
local FONT_SIZE = 24
local TEXT_X, TEXT_Y = 72, 700

-- xref entries are fixed-width by spec: 10-digit offset, 5-digit generation,
-- type char, and a 2-byte terminator. Off-by-one here corrupts the whole table.
local function xref_entry(offset, kind)
  return string.format("%010d %05d %s \n", offset, kind == "f" and 65535 or 0, kind)
end

local function content_stream(text)
  return string.format(
    "BT /F1 %d Tf %d %d Td (%s) Tj ET\n",
    FONT_SIZE, TEXT_X, TEXT_Y, text
  )
end

--- Build the PDF byte string for the given page texts.
--- @param page_texts string[] one line of text per page
--- @return string
function M.build(page_texts)
  assert(type(page_texts) == "table" and #page_texts > 0, "need at least one page")

  local count = #page_texts
  -- Object numbering: 1 = catalog, 2 = page tree, then (page, contents) pairs.
  local page_obj = function(i) return 2 + (i * 2) - 1 end
  local contents_obj = function(i) return 2 + (i * 2) end

  local objects = {}
  local kids = {}
  for i = 1, count do
    kids[#kids + 1] = string.format("%d 0 R", page_obj(i))
  end

  objects[1] = "<< /Type /Catalog /Pages 2 0 R >>"
  objects[2] = string.format(
    "<< /Type /Pages /Kids [%s] /Count %d >>",
    table.concat(kids, " "), count
  )

  for i = 1, count do
    objects[page_obj(i)] = string.format(
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] "
        .. "/Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> "
        .. "/Contents %d 0 R >>",
      PAGE_WIDTH, PAGE_HEIGHT, contents_obj(i)
    )
    local stream = content_stream(page_texts[i])
    objects[contents_obj(i)] = string.format(
      "<< /Length %d >>\nstream\n%s\nendstream",
      #stream, stream
    )
  end

  -- Serialize, recording each object's byte offset for the xref table.
  local parts = { "%PDF-1.4\n" }
  local size = #parts[1]
  local offsets = {}
  for num = 1, #objects do
    offsets[num] = size
    local chunk = string.format("%d 0 obj\n%s\nendobj\n", num, objects[num])
    parts[#parts + 1] = chunk
    size = size + #chunk
  end

  local xref_offset = size
  local xref = { string.format("xref\n0 %d\n", #objects + 1), xref_entry(0, "f") }
  for num = 1, #objects do
    xref[#xref + 1] = xref_entry(offsets[num], "n")
  end
  parts[#parts + 1] = table.concat(xref)
  parts[#parts + 1] = string.format(
    "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n",
    #objects + 1, xref_offset
  )

  return table.concat(parts)
end

--- Write a fixture PDF to `path`. Returns the path for chaining.
--- @param path string
--- @param page_texts string[]
--- @return string
function M.write(path, page_texts)
  local fh, err = io.open(path, "wb")
  if not fh then
    error(("could not write PDF fixture to %s: %s"):format(path, err or "unknown error"))
  end
  fh:write(M.build(page_texts))
  fh:close()
  return path
end

return M
