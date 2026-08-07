; Overrides nvim-treesitter (master, archived) markdown_inline injections with
; nvim 0.12's own bundled query, for consistency with the markdown override in
; ../markdown/injections.scm (see that file for the full crash story). This one
; only ever used safe #set! directives, but we pin it to core's version too so
; the whole markdown injection path comes from one 0.12-native source.
; TODO: remove once nvim-treesitter is migrated to the `main` branch.
((html_tag) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined))

((latex_block) @injection.content
  (#set! injection.language "latex")
  (#set! injection.include-children))
