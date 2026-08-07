; Overrides nvim-treesitter (master, archived) markdown injections, which crash
; on nvim 0.11+ / 0.12: its `set-lang-from-info-string!` directive does
; `local node = match[id]; node:range()`, but on 0.11+ a query-match capture is
; a LIST of nodes, not a single node — so `:range()` is nil and treesitter dies
; ("attempt to call method 'range' (a nil value)"), flooding render-markdown.
; ~/.config/nvim is first on runtimepath, so this file wins as the base query.
; Content is nvim 0.12's own bundled query, which captures the fence language
; directly via @injection.language (no custom directive) and is 0.12-native.
; TODO: remove once nvim-treesitter is migrated to the `main` branch.
(fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content)

((html_block) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined)
  (#set! injection.include-children))

((minus_metadata) @injection.content
  (#set! injection.language "yaml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

((plus_metadata) @injection.content
  (#set! injection.language "toml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

([
  (inline)
  (pipe_table_cell)
] @injection.content
  (#set! injection.language "markdown_inline"))
