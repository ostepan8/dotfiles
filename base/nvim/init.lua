

-- ============================
-- CORE SETTINGS
-- ============================
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.number = true
vim.opt.relativenumber = true
-- 24-bit color: gives treesitter + gruvbox their full rich palette (without
-- this, nvim is capped at 256 colors and even active treesitter looks flat).
-- Requires truecolor through the terminal — Ghostty sets COLORTERM=truecolor
-- and tmux advertises it via `terminal-features ",*:RGB"`.
vim.opt.termguicolors = true
vim.opt.background = "dark"    -- or "light" if you prefer

-- Use the macOS system clipboard for ALL yanks/deletes/pastes, so a plain
-- `yy` copies the line straight to the clipboard (Cmd+V works in any app) and
-- `p` pastes whatever you last copied elsewhere. No more "+ prefix needed.
vim.opt.clipboard = "unnamedplus"

-- Set leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Load lazy.nvim
vim.opt.rtp:prepend("~/.local/share/nvim/lazy/lazy.nvim")

require("lazy").setup({
        -- COLORSCHEME

        {
                "morhetz/gruvbox",
                lazy = false,
                priority = 1000,
                config = function()
                        vim.cmd([[colorscheme gruvbox]])
                end,
        },

        -- Alternative colorschemes (uncomment one if you don't like gruvbox)
        -- { "folke/tokyonight.nvim", priority = 1000, config = function() vim.cmd("colorscheme tokyonight-night") end },
        -- { "rebelot/kanagawa.nvim", priority = 1000, config = function() vim.cmd("colorscheme kanagawa") end },
        -- { "EdenEast/nightfox.nvim", priority = 1000, config = function() vim.cmd("colorscheme carbonfox") end },
        -- { "navarasu/onedark.nvim", priority = 1000, config = function() vim.cmd("colorscheme onedark") end },

        -- FILE TREE
        {
                "nvim-tree/nvim-tree.lua",
                dependencies = { "nvim-tree/nvim-web-devicons" },
                cmd = { "NvimTreeToggle", "NvimTreeFocus", "NvimTreeFindFile" },
                keys = { { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "File tree" } },
                config = function()
                        require("nvim-tree").setup({
                                view = { width = 30 },
                                filters = {
                                        dotfiles = false,
                                        git_ignored = false,
                                },
                                renderer = {
                                        group_empty = true,
                                        icons = {
                                                glyphs = {
                                                        default = "",
                                                        symlink = "",
                                                        git = {
                                                                unstaged = "✗",
                                                                staged = "✓",
                                                                unmerged = "",
                                                                renamed = "➜",
                                                                untracked = "★",
                                                                deleted = "",
                                                                ignored = "◌",
                                                        },
                                                },
                                        },
                                },
                        })
                        vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { noremap = true, silent = true })
                end
        },

        -- FUZZY FINDER
        {
                "nvim-telescope/telescope.nvim",
                cmd = "Telescope",
                dependencies = {
                        "nvim-lua/plenary.nvim",
                        -- Compiled C sorter. Telescope's pure-Lua fallback is the
                        -- bottleneck once a picker holds a few thousand entries,
                        -- which live_grep over ~/dotfiles hits immediately.
                        { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
                },
                keys = {
                        { "<leader>f", "<cmd>Telescope find_files<cr>", desc = "Find files" },
                        { "<leader>g", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
                        { "<leader>p", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
                        { "<leader>b", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
                },
                config = function()
                        require("telescope").setup({
                                defaults = {
                                        prompt_prefix = " ",
                                        selection_caret = " ",
                                        path_display = { "smart" },
                                },
                                pickers = {
                                        find_files = {
                                                hidden = true,
                                                no_ignore = true,
                                                find_command = {
                                                        "rg",
                                                        "--files",
                                                        "--hidden",
                                                        "--no-ignore",
                                                        "--glob", "!**/.git/*",
                                                        "--glob", "!**/node_modules/*",
                                                        "--glob", "!**/.next/*",
                                                        "--glob", "!**/dist/*",
                                                        "--glob", "!**/build/*",
                                                        "--glob", "!**/.turbo/*",
                                                        "--glob", "!**/.cache/*",
                                                        "--glob", "!**/coverage/*",
                                                        "--glob", "!**/.venv/*",
                                                        "--glob", "!**/__pycache__/*",
                                                        "--glob", "!**/.pytest_cache/*",
                                                        "--glob", "!**/target/*",
                                                        "--glob", "!**/.terraform/*",
                                                        "--glob", "!**/.idea/*",
                                                        "--glob", "!**/*.lock",
                                                        "--glob", "!**/.DS_Store",
                                                },
                                        },
                                },
                        })
                        pcall(require("telescope").load_extension, "fzf")
                end
        },

        -- SYNTAX HIGHLIGHTING (nvim-treesitter `main` branch — supports nvim
        -- 0.11+. The old `master` branch was archived and crashed on 0.12
        -- because its query directives call node:range() on match captures
        -- that are now lists of nodes.)
        --
        -- The `main` branch has a different API: no configs.setup()/ensure_installed;
        -- you install() parsers explicitly and start highlighting yourself per
        -- buffer. Highlight + (experimental) treesitter indent are enabled in a
        -- FileType autocmd for any buffer whose language has an installed parser.
        {
                "nvim-treesitter/nvim-treesitter",
                branch = "main",
                lazy = false,
                build = ":TSUpdate",
                config = function()
                        require("nvim-treesitter").setup()

                        require("nvim-treesitter").install({
                                "python", "cpp", "lua", "luau", "vim", "vimdoc", "bash",
                                "markdown", "markdown_inline", "json", "yaml", "javascript",
                                "typescript", "tsx", "html", "css", "query",
                                -- config formats + git buffers. gitcommit gives the
                                -- subject/body split real highlighting (and marks the
                                -- 50-col overflow) in every `git commit` buffer.
                                "toml", "gitcommit", "gitignore", "git_rebase",
                                "diff", "regex", "sql", "dockerfile",
                        })

                        -- Filetypes whose name differs from the parser (language) name.
                        vim.treesitter.language.register("tsx", "typescriptreact")
                        vim.treesitter.language.register("javascript", "javascriptreact")
                        vim.treesitter.language.register("bash", "sh")
                        -- jsonc was dropped as its own parser upstream (nvim-treesitter
                        -- warns "skipping unsupported language" if you ask for it);
                        -- the json grammar handles comments fine.
                        vim.treesitter.language.register("json", "jsonc")

                        vim.api.nvim_create_autocmd("FileType", {
                                callback = function(args)
                                        local buf = args.buf
                                        local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
                                                or vim.bo[buf].filetype
                                        -- start() loads the parser; pcall so filetypes without one
                                        -- (help without vimdoc, plain text, terminals) are skipped.
                                        if pcall(vim.treesitter.start, buf, lang) then
                                                vim.bo[buf].indentexpr =
                                                        "v:lua.require'nvim-treesitter'.indentexpr()"
                                        end
                                end,
                        })
                end
        },

        -- GIT
        { "tpope/vim-fugitive", cmd = { "Git", "G", "Gdiffsplit", "Gwrite", "Gread", "Gblame" } },
        {
                "lewis6991/gitsigns.nvim",
                event = { "BufReadPre", "BufNewFile" },
                config = function()
                        require("gitsigns").setup({
                                signs = {
                                        add = { text = "+" },
                                        change = { text = "~" },
                                        delete = { text = "_" },
                                        topdelete = { text = "‾" },
                                        changedelete = { text = "~" },
                                },
                        })
                end
        },

        -- COMMENTS
        {
                "numToStr/Comment.nvim",
                keys = {
                        { "gc", mode = { "n", "v" } }, { "gcc", mode = "n" },
                        { "gb", mode = { "n", "v" } }, { "gbc", mode = "n" },
                },
                config = function() require("Comment").setup() end
        },

        -- STATUSLINE
        {
                "nvim-lualine/lualine.nvim",
                dependencies = { "nvim-tree/nvim-web-devicons" },
                event = "VeryLazy",
                config = function()
                        require("lualine").setup({
                                options = {
                                        theme = "auto",
                                        section_separators = { left = '', right = '' },
                                        component_separators = { left = '', right = '' },
                                },
                        })
                end
        },

        -- WHICH-KEY
        {
                "folke/which-key.nvim",
                event = "VeryLazy",
                config = function()
                        require("which-key").setup({
                                win = {
                                        border = "rounded",
                                        position = "bottom",
                                        margin = { 1, 0, 1, 0 },
                                        padding = { 1, 2, 1, 2 },
                                },
                        })
                end
        },

        -- LSP
        {
                "neovim/nvim-lspconfig",
                event = { "BufReadPre", "BufNewFile" },
                dependencies = {
                        -- blink supplies the client capabilities (it advertises
                        -- snippet/resolve support the servers key off), so it has
                        -- to be loaded before any server is configured.
                        -- lazydev is deliberately NOT listed here: naming it as a
                        -- dependency would force it to load on every buffer and
                        -- defeat its own ft = "lua" lazy trigger.
                        "saghen/blink.cmp",
                },
                config = function()
                        local capabilities = require("blink.cmp").get_lsp_capabilities()

                        -- Diagnostics render as a full virtual LINE under the cursor
                        -- rather than virtual TEXT at the end of it: end-of-line text
                        -- gets truncated at the window edge, which is exactly where
                        -- the useful half of a clangd or pyright message lives.
                        -- Only the current line is expanded, so the buffer doesn't
                        -- reflow as you move around.
                        vim.diagnostic.config({
                                virtual_text = false,
                                virtual_lines = { current_line = true },
                                underline = true,
                                update_in_insert = false,
                                severity_sort = true,
                                signs = {
                                        text = {
                                                [vim.diagnostic.severity.ERROR] = "E",
                                                [vim.diagnostic.severity.WARN]  = "W",
                                                [vim.diagnostic.severity.INFO]  = "I",
                                                [vim.diagnostic.severity.HINT]  = "H",
                                        },
                                },
                                float = { border = "rounded", source = true },
                        })

                        vim.api.nvim_create_autocmd("LspAttach", {
                                callback = function(args)
                                        local o = { noremap = true, silent = true, buffer = args.buf }
                                        vim.keymap.set("n", "gd", vim.lsp.buf.definition, o)
                                        vim.keymap.set("n", "gD", vim.lsp.buf.declaration, o)
                                        vim.keymap.set("n", "gi", vim.lsp.buf.implementation, o)
                                        vim.keymap.set("n", "gr", vim.lsp.buf.references, o)
                                        vim.keymap.set("n", "K", vim.lsp.buf.hover, o)
                                        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, o)
                                        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, o)
                                        vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, o)
                                        vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, o)

                                        -- Inlay hints: inferred types and parameter
                                        -- names rendered inline. On by default where
                                        -- the server supports it; <leader>ih toggles
                                        -- them per buffer when they get noisy.
                                        local client = vim.lsp.get_client_by_id(args.data.client_id)
                                        if client and client:supports_method("textDocument/inlayHint") then
                                                vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
                                                vim.keymap.set("n", "<leader>ih", function()
                                                        local on = vim.lsp.inlay_hint.is_enabled({ bufnr = args.buf })
                                                        vim.lsp.inlay_hint.enable(not on, { bufnr = args.buf })
                                                end, vim.tbl_extend("force", o, { desc = "Toggle inlay hints" }))
                                        end
                                end,
                        })

                        -- Per-server overrides, merged on top of the shared
                        -- capabilities. lua_ls only needs to be told about the
                        -- `vim` global here — lazydev.nvim supplies the runtime
                        -- library lazily, which is far faster than pushing all of
                        -- nvim_get_runtime_file() at it on every attach.
                        local server_settings = {
                                lua_ls = {
                                        settings = {
                                                Lua = {
                                                        runtime = { version = "LuaJIT" },
                                                        diagnostics = { globals = { "vim" } },
                                                        workspace = { checkThirdParty = false },
                                                        telemetry = { enable = false },
                                                        hint = { enable = true },
                                                },
                                        },
                                },
                                yamlls = {
                                        settings = {
                                                yaml = { keyOrdering = false },
                                        },
                                },
                                -- ruff and pyright both attach to python. ruff owns
                                -- lint + format + import sorting; pyright owns types
                                -- and hover docs, which ruff does not provide. Without
                                -- this, K returns ruff's empty hover about half the
                                -- time depending on which client answers first.
                                ruff = {
                                        on_attach = function(client)
                                                client.server_capabilities.hoverProvider = false
                                        end,
                                },
                        }

                        local servers = {
                                -- languages
                                "pyright", "ruff", "clangd", "ts_ls", "lua_ls", "luau_lsp",
                                -- web
                                "html", "cssls", "eslint",
                                -- config + prose formats
                                "jsonls", "yamlls", "taplo", "marksman", "bashls",
                        }
                        for _, server in ipairs(servers) do
                                vim.lsp.config(server, vim.tbl_deep_extend(
                                        "force",
                                        { capabilities = capabilities },
                                        server_settings[server] or {}
                                ))
                        end
                        vim.lsp.enable(servers)
                end
        },

        -- LUA DEV (nvim API types for lua_ls, loaded on demand)
        {
                "folke/lazydev.nvim",
                ft = "lua",
                opts = {
                        library = {
                                { path = "${3rd}/luv/library", words = { "vim%.uv" } },
                        },
                },
        },

        -- AUTOCOMPLETE
        -- blink.cmp replaces nvim-cmp + cmp-nvim-lsp/buffer/path/cmp_luasnip.
        -- It re-ranks on every keystroke (~1ms) instead of nvim-cmp's 60ms
        -- debounce, and the sources below are built in rather than five
        -- separate plugins. Pinned to v1: v2 is mid-rewrite and moves
        -- blink.lib out into a separate package.
        {
                "saghen/blink.cmp",
                version = "1.*",
                dependencies = { "L3MON4D3/LuaSnip" },
                opts = {
                        snippets = { preset = "luasnip" },

                        -- Same bindings as the old nvim-cmp setup. Each entry
                        -- falls through in order, so <Tab> selects the next item
                        -- when the menu is open, otherwise jumps a snippet
                        -- placeholder, otherwise inserts a literal tab.
                        keymap = {
                                preset = "none",
                                ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
                                ["<C-e>"] = { "hide", "fallback" },
                                ["<C-b>"] = { "scroll_documentation_up", "fallback" },
                                ["<C-f>"] = { "scroll_documentation_down", "fallback" },
                                ["<CR>"] = { "accept", "fallback" },
                                ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
                                ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
                        },

                        completion = {
                                -- preselect + no auto_insert reproduces nvim-cmp's
                                -- confirm({ select = true }): <CR> takes the top item
                                -- without it being typed into the buffer first.
                                list = { selection = { preselect = true, auto_insert = false } },
                                menu = { border = "rounded" },
                                documentation = { auto_show = true, auto_show_delay_ms = 200 },
                                ghost_text = { enabled = true },
                        },
                        signature = { enabled = true, window = { border = "rounded" } },

                        sources = {
                                default = { "lazydev", "lsp", "snippets", "buffer", "path" },
                                providers = {
                                        -- nvim API completion in lua files, ranked above
                                        -- the LSP's own results.
                                        lazydev = {
                                                name = "LazyDev",
                                                module = "lazydev.integrations.blink",
                                                score_offset = 100,
                                        },
                                },
                        },
                        fuzzy = { implementation = "prefer_rust_with_warning" },
                },
                opts_extend = { "sources.default" },
        },

        -- FORMATTER
        {
                "stevearc/conform.nvim",
                event = "BufWritePre",
                cmd = "ConformInfo",
                keys = { { "<leader>F", mode = { "n", "v" }, desc = "Format buffer" } },
                config = function()
                        local no_autoformat = { cpp = true, sh = true, bash = true }

                        require("conform").setup({
                                formatters_by_ft = {
                                        -- ruff, not black: every pyproject.toml in
                                        -- ~/Desktop/projects already declares ruff with
                                        -- line-length = 100, so black's default 88 was
                                        -- reformatting these files against their own
                                        -- project config on every save. ruff reads the
                                        -- nearest pyproject.toml, so the editor and CI
                                        -- finally agree.
                                        python = { "ruff_organize_imports", "ruff_format" },
                                        cpp = { "clang-format" },
                                        lua = { "stylua" },
                                        javascript = { "prettier" },
                                        typescript = { "prettier" },
                                        javascriptreact = { "prettier" },
                                        typescriptreact = { "prettier" },
                                        -- shfmt with the same 8-wide tab style the rest
                                        -- of this config uses; -ci indents switch cases.
                                        sh = { "shfmt" },
                                        bash = { "shfmt" },
                                        toml = { "taplo" },
                                        json = { "prettier" },
                                        jsonc = { "prettier" },
                                        yaml = { "prettier" },
                                        markdown = { "prettier" },
                                        html = { "prettier" },
                                        css = { "prettier" },
                                },
                                formatters = {
                                        -- 2 spaces matches the dominant style already in
                                        -- ~/dotfiles (44 scripts at 2, 22 at 4). -ci indents
                                        -- switch cases, -bn puts && / || at line starts.
                                        shfmt = { prepend_args = { "-i", "2", "-ci", "-bn" } },
                                },
                                -- Autoformat on save everywhere EXCEPT cpp and shell.
                                --   cpp:   during a contest you don't want clang-format
                                --          reflowing your solution (or the save latency).
                                --   shell: ~1/3 of the scripts in ~/dotfiles are indented
                                --          4-wide, so save-on-format would silently reflow
                                --          them — and the dotfiles LaunchAgent auto-commits
                                --          and pushes, turning that into a surprise diff.
                                -- Both format on demand with <leader>F.
                                format_on_save = function(bufnr)
                                        if no_autoformat[vim.bo[bufnr].filetype] then
                                                return
                                        end
                                        return { timeout_ms = 500, lsp_fallback = true }
                                end,
                        })
                        vim.keymap.set({ "n", "v" }, "<leader>F", function()
                                require("conform").format({ async = true, lsp_fallback = true })
                        end, { noremap = true, silent = true, desc = "Format buffer" })
                end
        },

        -- LINTER
        -- Fills the gap the LSP layer leaves: shellcheck catches the bugs that
        -- make shell scripts fail silently (unquoted expansions that word-split
        -- on paths with spaces, `[ $x = y ]` on an empty var, ignored exit
        -- codes). bash-language-server does not report these on its own.
        {
                "mfussenegger/nvim-lint",
                event = { "BufReadPost", "BufNewFile" },
                config = function()
                        local lint = require("lint")

                        -- zsh is deliberately absent: shellcheck cannot parse zsh
                        -- and reports "This shell type is unknown" on every file,
                        -- which would bury the real findings in .sh scripts.
                        lint.linters_by_ft = {
                                sh = { "shellcheck" },
                                bash = { "shellcheck" },
                        }

                        vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
                                callback = function()
                                        lint.try_lint()
                                end,
                        })

                        vim.keymap.set("n", "<leader>l", function()
                                lint.try_lint()
                        end, { noremap = true, silent = true, desc = "Lint buffer" })
                end
        },

        -- DIAGNOSTICS PANEL
        {
                "folke/trouble.nvim",
                dependencies = { "nvim-tree/nvim-web-devicons" },
                cmd = "Trouble",
                opts = { focus = true },
                keys = {
                        { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (workspace)" },
                        { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Diagnostics (buffer)" },
                        { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Symbol outline" },
                        { "<leader>xl", "<cmd>Trouble lsp toggle win.position=right<cr>", desc = "Definitions / references" },
                        { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix list" },
                },
        },

        -- TMUX NAVIGATOR (works with your tmux config!)
        {
                "christoomey/vim-tmux-navigator",
                keys = {
                        { "<C-h>", "<cmd>TmuxNavigateLeft<cr>" },
                        { "<C-j>", "<cmd>TmuxNavigateDown<cr>" },
                        { "<C-k>", "<cmd>TmuxNavigateUp<cr>" },
                        { "<C-l>", "<cmd>TmuxNavigateRight<cr>" },
                },
        },

        -- OPENCODE
        {
                "sudo-tee/opencode.nvim",
                -- Roughly 45ms of the old startup budget: it pulled in its
                -- session runtime, UI and renderer on every launch, including
                -- launches that never opened it.
                cmd = "Opencode",
                keys = {
                        { "<leader>og", desc = "Opencode toggle" },
                        { "<leader>oi", desc = "Opencode input" },
                        { "<leader>oI", desc = "Opencode input (new session)" },
                        { "<leader>oo", desc = "Opencode output" },
                        { "<leader>ot", desc = "Opencode toggle focus" },
                },
                -- Only load where the opencode binary exists. This config is
                -- shared with headless Linux nodes that have no opencode, and
                -- the plugin errors at startup there ("opencode command not
                -- found"), so every nvim launch on those machines opened with a
                -- red error for a tool that was never going to be installed.
                cond = function()
                        return vim.fn.executable("opencode") == 1
                end,
                dependencies = {
                        "nvim-lua/plenary.nvim",
                        {
                                "MeanderingProgrammer/render-markdown.nvim",
                                opts = {
                                        anti_conceal = { enabled = false },
                                        file_types = { "markdown", "opencode_output" },
                                },
                                ft = { "markdown", "opencode_output" },
                        },
                },
                config = function()
                        require("opencode").setup({
                                preferred_picker = "telescope",
                                keymap = {
                                        input_window = {
                                                ["<esc>"] = false,
                                                ["<C-q>"] = { "close" },
                                        },
                                },
                        })
                end,
        },

        -- PDF IMAGE RENDERING
        -- Paints a rasterized PDF page (and any other image) into the terminal
        -- over the Kitty graphics protocol, which Ghostty implements. Only the
        -- `gi` image view needs this; the text view below works without it, so
        -- it loads on demand, and not at all where there is provably no
        -- terminal to draw into (a headless run, TERM=dumb). Anything less
        -- certain than that still loads: skipping on "I could not tell" is how
        -- a perfectly capable setup ends up silently without images.
        {
                "3rd/image.nvim",
                ft = { "pdf" },
                cond = function()
                        return require("pdfview.deps").graphics_possible()
                end,
                opts = {
                        backend = "kitty",
                        -- magick_cli shells out to the `magick` binary from
                        -- `brew install imagemagick`. The alternative,
                        -- magick_rock, needs a working LuaRocks toolchain built
                        -- against ImageMagick headers — a dependency this
                        -- config would then have to reproduce on every machine.
                        processor = "magick_cli",
                        -- Every integration off on purpose: this plugin is here
                        -- to serve pdfview's `gi`, and silently changing how
                        -- markdown or HTML buffers render is not what was asked
                        -- for. Turn one on deliberately if you want it.
                        integrations = {
                                markdown = { enabled = false },
                                asciidoc = { enabled = false },
                                neorg = { enabled = false },
                                rst = { enabled = false },
                                typst = { enabled = false },
                                html = { enabled = false },
                                css = { enabled = false },
                        },
                        hijack_file_patterns = {},
                        max_width_window_percentage = 100,
                        max_height_window_percentage = 100,
                        -- Images are drawn into a dedicated split; clearing them
                        -- when another window overlaps keeps them from bleeding
                        -- over telescope and cmp popups.
                        window_overlap_clear_enabled = true,
                        editor_only_render_when_focused = true,
                        tmux_show_only_in_active_window = true,
                },
        },

        -- COMPETITIVE PROGRAMMING (testcase manager + Codeforces import)
        -- Runs your solution against stored testcases and shows pass/WA/TLE with
        -- a diff. `<leader>tc` imports samples from the browser via the
        -- Competitive Companion extension. Compiles with the same g++-16 flags
        -- as the <F5> keymap below.
        {
                "xeluxee/competitest.nvim",
                dependencies = { "MunifTanjim/nui.nvim" },
                cmd = "CompetiTest",
                keys = {
                        { "<leader>tr", "<cmd>CompetiTest run<cr>", desc = "CP: run testcases" },
                        { "<leader>ta", "<cmd>CompetiTest add_testcase<cr>", desc = "CP: add testcase" },
                        { "<leader>te", "<cmd>CompetiTest edit_testcase<cr>", desc = "CP: edit testcase" },
                        { "<leader>tc", "<cmd>CompetiTest receive testcases<cr>", desc = "CP: receive testcases" },
                        { "<leader>tp", "<cmd>CompetiTest receive problem<cr>", desc = "CP: receive problem" },
                },
                opts = {
                        compile_command = {
                                cpp = {
                                        exec = "g++-16",
                                        args = { "-std=gnu++17", "-O2", "-Wall", "-Wextra",
                                                "-fsanitize=address,undefined", "-D_GLIBCXX_DEBUG",
                                                "$(FNAME)", "-o", "$(FNOEXT)" },
                                },
                        },
                        run_command = {
                                cpp = { exec = "$(FNOEXT)" },
                        },
                        template_file = "~/Desktop/code-forces/template.cpp",
                        received_problems_path = "$(CWD)/$(PROBLEM).cpp",
                },
        },
})

-- ============================
-- ADDITIONAL SETTINGS
-- ============================

-- Disable netrw (since we use nvim-tree)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Indentation settings
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.softtabstop = 2

-- Better UI settings
vim.opt.cmdheight = 1
vim.opt.pumheight = 10
vim.opt.showmode = false
vim.opt.showtabline = 2
vim.opt.laststatus = 3
vim.opt.signcolumn = "yes"
vim.opt.wrap = false
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.cursorline = true

-- Search settings
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Better splits
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Better completion experience
vim.opt.completeopt = "menuone,noselect"

-- Faster update time
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

-- Auto-reload files changed externally (e.g. by opencode)
vim.opt.autoread = true
vim.api.nvim_create_autocmd({"FocusGained", "BufEnter"}, {
        command = "checktime"
})

-- Backup settings
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false
vim.opt.undofile = true

-- Clear search highlight with ESC
vim.keymap.set("n", "<Esc>", ":nohl<CR>", { silent = true })

-- Window navigation is owned by vim-tmux-navigator (see its `keys` spec).
-- It previously did NOT work with tmux despite the comment saying so: these
-- four lines ran after lazy.setup() and replaced the plugin's mappings with
-- plain <C-w> motions, so <C-h> at the leftmost split moved nowhere instead
-- of crossing into the tmux pane to its left.

-- ============================
-- PDF READING
-- ============================
-- `nvim paper.pdf` opens the document's text, searchable and yankable like any
-- other buffer, instead of a screenful of binary. ]p / [p walk pages, `gi`
-- renders the current page as an actual image (figures, equations, tables),
-- `go` hands it to Preview, and :PdfHealth says which of those are available
-- on this machine. Implementation lives in lua/pdfview/, tested by
-- base/nvim/tests/run.sh.
require("pdfview").setup()

-- ============================
-- C++ COMPETITIVE PROGRAMMING
-- ============================
-- <F5> debug build (ASan + UBSan + _GLIBCXX_DEBUG — catches OOB / UB / STL
--      misuse: the bugs that silently become WA/RE on the judge)
-- <F6> fast build (-O2 only — realistic timing for TLE checks)
-- Both compile the current file with g++-16 and run it in a bottom terminal
-- split, feeding stdin from ./input.txt whenever that file exists.
local function cpp_compile_run(debug_build)
        vim.cmd("silent! update") -- save first
        local src = vim.fn.expand("%:p")
        local dir = vim.fn.expand("%:p:h")
        local bin = "/tmp/cp_" .. vim.fn.expand("%:t:r")
        local flags = debug_build
                and "-std=gnu++17 -O2 -g -Wall -Wextra -fsanitize=address,undefined -D_GLIBCXX_DEBUG -DLOCAL"
                or "-std=gnu++17 -O2 -DLOCAL"
        local infile = dir .. "/input.txt"
        local redir = (vim.fn.filereadable(infile) == 1) and (" < " .. vim.fn.shellescape(infile)) or ""
        local cmd = string.format(
                "cd %s && g++-16 %s %s -o %s && echo '=== run ===' && %s%s; echo \"=== exit $? ===\"",
                vim.fn.shellescape(dir), flags, vim.fn.shellescape(src),
                vim.fn.shellescape(bin), vim.fn.shellescape(bin), redir
        )
        vim.cmd("botright 15split | enew")
        vim.fn.jobstart({ "bash", "-c", 'export PATH=/opt/homebrew/bin:"$PATH"; ' .. cmd }, { term = true })
        vim.cmd("startinsert")
end

vim.api.nvim_create_autocmd("FileType", {
        pattern = "cpp",
        callback = function(args)
                local o = { noremap = true, silent = true, buffer = args.buf }
                vim.keymap.set("n", "<F5>", function() cpp_compile_run(true) end, o)
                vim.keymap.set("n", "<F6>", function() cpp_compile_run(false) end, o)
        end,
})

-- New .cpp files start from the competitive-programming template, cursor
-- parked on the empty body line.
vim.api.nvim_create_autocmd("BufNewFile", {
        pattern = "*.cpp",
        callback = function(args)
                local tpl = {
                        "#include <bits/stdc++.h>",
                        "using namespace std;",
                        "",
                        "int main() {",
                        "    ios_base::sync_with_stdio(false);",
                        "    cin.tie(NULL);",
                        "",
                        "    ",
                        "",
                        "    return 0;",
                        "}",
                }
                vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, tpl)
                pcall(vim.api.nvim_win_set_cursor, 0, { 8, 4 })
        end,
})
