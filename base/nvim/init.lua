

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

-- Disable netrw (we use nvim-tree instead).
--
-- These MUST be set before require("lazy").setup() below: lazy sources every
-- runtime plugin/ file itself during setup, so anything set after that call
-- lands too late. Setting only `loaded_netrw` late is worse than not setting
-- it at all -- netrwPlugin.vim still registers its FileExplorer autocmds,
-- while autoload/netrw.vim bails on the same guard and never defines the
-- functions those autocmds call, so `nvim <dir>` dies with
-- "E117: Unknown function: netrw#LocalBrowseCheck".
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

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
                cmd = { "NvimTreeToggle", "NvimTreeFocus", "NvimTreeFindFile", "NvimTreeOpen" },
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
                -- The four originals stay on their bare single-letter keys --
                -- deliberately NOT moved under <leader>s, which would put a
                -- timeoutlen pause in front of the most-used mapping in the
                -- config. Everything added since lives under <leader>s.
                keys = {
                        { "<leader>f", "<cmd>Telescope find_files<cr>", desc = "Find files" },
                        { "<leader>g", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
                        { "<leader>p", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
                        { "<leader>b", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
                        -- resume reopens the previous picker with its query AND
                        -- its result list intact -- the one to reach for after
                        -- following a grep hit into a file and wanting the rest
                        -- of the matches back.
                        { "<leader>sr", "<cmd>Telescope resume<cr>", desc = "Resume last picker" },
                        { "<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps" },
                        { "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
                        { "<leader>sd", "<cmd>Telescope diagnostics<cr>", desc = "Diagnostics" },
                        { "<leader>sg", "<cmd>Telescope git_status<cr>", desc = "Git status" },
                        { "<leader>sc", "<cmd>Telescope git_commits<cr>", desc = "Git commits" },
                        -- treesitter, not lsp_document_symbols: the LSP version
                        -- returned an empty picker on a standalone .cpp with no
                        -- compile_commands.json, even with clangd attached and
                        -- answering textDocument/documentSymbol directly -- no
                        -- error, no notification, just no results. The treesitter
                        -- picker needs no server, is instant, and works in every
                        -- buffer that has a parser. Workspace symbols below still
                        -- needs the LSP; there is no treesitter equivalent.
                        { "<leader>ss", "<cmd>Telescope treesitter<cr>", desc = "Symbols in file" },
                        { "<leader>sS", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", desc = "Workspace symbols" },
                        -- Fuzzy search within the current buffer.
                        { "<leader>s/", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Search in buffer" },
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

                        -- Start highlighting for one buffer, if it is not already
                        -- running. Returns ok, err so the :TSRestart command below can
                        -- report a failure that the autocmd deliberately swallows.
                        local function ensure_highlight(buf)
                                if not vim.api.nvim_buf_is_valid(buf) then return false end
                                -- Already active: bail. The guard is what lets this be
                                -- attached to several events without restarting the
                                -- highlighter every time a buffer is re-entered.
                                if vim.treesitter.highlighter.active[buf] then return true end
                                local ft = vim.bo[buf].filetype
                                -- BufReadPost can arrive before filetype detection has
                                -- run. FileType will follow, so skip rather than guess.
                                if ft == "" then return false end
                                local lang = vim.treesitter.language.get_lang(ft) or ft
                                -- start() loads the parser; pcall so filetypes without one
                                -- (help without vimdoc, plain text, terminals) are skipped.
                                local ok, err = pcall(vim.treesitter.start, buf, lang)
                                if ok then
                                        vim.bo[buf].indentexpr =
                                                "v:lua.require'nvim-treesitter'.indentexpr()"
                                end
                                return ok, err
                        end

                        -- Three events, not just FileType. A buffer that loses its
                        -- highlighter -- after a reload, or because FileType never
                        -- reached it -- previously stayed unstyled for the rest of the
                        -- session with no error and no way to tell why: the pcall above
                        -- swallows the reason by design, since most of what it catches
                        -- is the unremarkable "this filetype has no parser". That is a
                        -- bad failure mode for something purely cosmetic, and it has
                        -- happened at least once on this machine (a markdown buffer
                        -- came back from :e! with highlighter.active empty). These
                        -- extra events make it self-healing: a reload, or simply
                        -- switching back to the buffer, starts it again.
                        --
                        -- BufEnter and not BufWinEnter: the latter fires when a buffer
                        -- is first DISPLAYED in a window, which a plain `wincmd w` back
                        -- onto an already-visible buffer does not do -- measured, it
                        -- left a stopped highlighter stopped. BufEnter fires on every
                        -- buffer entry, and the active[] guard above makes the common
                        -- case a single table lookup.
                        vim.api.nvim_create_autocmd({ "FileType", "BufReadPost", "BufEnter" }, {
                                group = vim.api.nvim_create_augroup("treesitter_start", { clear = true }),
                                callback = function(args) ensure_highlight(args.buf) end,
                        })

                        -- Manual escape hatch, and the only place the pcall's error is
                        -- surfaced. Run it when a buffer looks unstyled.
                        vim.api.nvim_create_user_command("TSRestart", function()
                                local buf = vim.api.nvim_get_current_buf()
                                vim.treesitter.stop(buf)
                                local ok, err = ensure_highlight(buf)
                                if ok then
                                        vim.notify("treesitter: highlighting " .. vim.bo[buf].filetype)
                                else
                                        vim.notify("treesitter: could not start for '"
                                                .. vim.bo[buf].filetype .. "' -- " .. tostring(err),
                                                vim.log.levels.WARN)
                                end
                        end, { desc = "Restart treesitter highlighting for this buffer" })
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
                                -- Inline blame for the current line only, after a
                                -- pause. Off by default in gitsigns; the delay is
                                -- what makes it tolerable -- at 0 it flickers on
                                -- every cursor move.
                                current_line_blame = true,
                                current_line_blame_opts = {
                                        virt_text_pos = "eol",
                                        delay = 400,
                                        ignore_whitespace = true,
                                },
                                -- This plugin was installed for two years with no
                                -- on_attach at all, which meant it drew signs in the
                                -- gutter and did nothing else: no hunk navigation, no
                                -- staging, no preview, no blame. Everything below is
                                -- what it was always capable of.
                                on_attach = function(bufnr)
                                        local gs = require("gitsigns")
                                        local function map(mode, lhs, rhs, desc, extra)
                                                vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", {
                                                        buffer = bufnr, noremap = true,
                                                        silent = true, desc = desc,
                                                }, extra or {}))
                                        end

                                        -- Hunk navigation. In a diff buffer ]c / [c are
                                        -- vim's own change motions and already do the
                                        -- right thing, so fall through there rather
                                        -- than shadowing them. expr = true is load-
                                        -- bearing: without it the returned "]c" string
                                        -- is treated as the mapping's result rather
                                        -- than as keys to feed back, and diff-mode
                                        -- navigation silently stops working.
                                        map("n", "]c", function()
                                                if vim.wo.diff then return "]c" end
                                                vim.schedule(function() gs.nav_hunk("next") end)
                                                return "<Ignore>"
                                        end, "Next hunk", { expr = true })
                                        map("n", "[c", function()
                                                if vim.wo.diff then return "[c" end
                                                vim.schedule(function() gs.nav_hunk("prev") end)
                                                return "<Ignore>"
                                        end, "Prev hunk", { expr = true })

                                        -- stage_hunk is a TOGGLE in current gitsigns:
                                        -- run it on an already-staged hunk and it
                                        -- unstages. undo_stage_hunk still exists but is
                                        -- marked @deprecated in actions.lua, so there
                                        -- is deliberately no <leader>hu here.
                                        map("n", "<leader>hs", gs.stage_hunk, "Stage / unstage hunk")
                                        map("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
                                        -- Visual-mode staging takes the selected line
                                        -- range, so you can stage part of a hunk.
                                        map("v", "<leader>hs", function()
                                                gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
                                        end, "Stage selection")
                                        map("v", "<leader>hr", function()
                                                gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
                                        end, "Reset selection")
                                        map("n", "<leader>hS", gs.stage_buffer, "Stage buffer")
                                        map("n", "<leader>hR", gs.reset_buffer, "Reset buffer")
                                        map("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
                                        map("n", "<leader>hb", function()
                                                gs.blame_line({ full = true })
                                        end, "Blame line (full)")
                                        map("n", "<leader>hB", gs.toggle_current_line_blame, "Toggle inline blame")
                                        map("n", "<leader>hd", gs.diffthis, "Diff against index")
                                        map("n", "<leader>hD", function()
                                                gs.diffthis("~")
                                        end, "Diff against last commit")
                                        map("n", "<leader>hq", function()
                                                gs.setqflist("all")
                                        end, "All hunks to quickfix")

                                        -- ih = "in hunk": dih discards a hunk, vih
                                        -- selects one, without moving to its edges
                                        -- first.
                                        map({ "o", "x" }, "ih", gs.select_hunk, "Select hunk")
                                end,
                        })
                end
        },

        -- COMMENTS: none. gc / gcc / gb / gbc are BUILT IN as of nvim 0.10
        -- (runtime/lua/vim/_core/defaults.lua). Comment.nvim used to live here
        -- binding those exact four keys on top of the natives -- same behaviour,
        -- one more plugin to load and keep current. Removed, not replaced.

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
                        local wk = require("which-key")
                        wk.setup({
                                -- Independent of timeoutlen (see the note by
                                -- vim.opt.timeoutlen below). Stated explicitly
                                -- so the next person to speed up the popup
                                -- changes THIS and not the timeout.
                                delay = 200,
                                win = {
                                        border = "rounded",
                                        position = "bottom",
                                        margin = { 1, 0, 1, 0 },
                                        padding = { 1, 2, 1, 2 },
                                },
                        })

                        -- Without these every multi-key leader tree rendered as a
                        -- column of bare prefixes -- the popup told you <leader>x
                        -- existed but not that it was Trouble. Labels only; the
                        -- mappings themselves stay with the plugins that own them.
                        wk.add({
                                { "<leader>h", group = "git hunks" },
                                { "<leader>o", group = "opencode" },
                                { "<leader>q", group = "session" },
                                { "<leader>s", group = "search (telescope)" },
                                { "<leader>t", group = "testcases (CP)" },
                                { "<leader>x", group = "trouble / diagnostics" },
                                { "<leader>c", group = "code" },
                                { "<leader>r", group = "refactor" },
                                { "[", group = "prev" },
                                { "]", group = "next" },
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

        -- SURROUND
        -- ysiw) / cs"' / ds( -- add, change, delete surrounding pairs.
        -- mini.surround rather than nvim-surround: same operations, but it does
        -- not claim the `s` prefix in visual mode (nvim-surround's visual `S`),
        -- and it ships as part of a library already proven against 0.12.
        -- Keys mirror nvim-surround's so muscle memory from any tutorial works:
        --   ysiw)   surround inner word with ()
        --   cs"'    change surrounding " to '
        --   ds(     delete surrounding ()
        {
                "echasnovski/mini.surround",
                keys = { "ys", "ds", "cs", { "S", mode = "x" } },
                opts = {
                        mappings = {
                                add = "ys",
                                delete = "ds",
                                replace = "cs",
                                find = "",
                                find_left = "",
                                highlight = "",
                                update_n_lines = "",
                        },
                        -- Jump to the next pair if there isn't one under the
                        -- cursor, instead of failing.
                        search_method = "cover_or_next",
                },
                config = function(_, opts)
                        require("mini.surround").setup(opts)

                        -- Visual-mode S. This MUST be the string form, not a
                        -- Lua function calling MiniSurround.add("visual"): the
                        -- function form runs after the selection has already
                        -- been left, so mini reads an empty region and inserts
                        -- a bare pair at the cursor ("hello -> ""hello) instead
                        -- of wrapping anything. The :<C-u> dance is what keeps
                        -- '< and '> intact, and is the form mini's own docs
                        -- give (lua/mini/surround.lua, the `S` recipe).
                        vim.keymap.set("x", "S", [[:<C-u>lua MiniSurround.add("visual")<CR>]],
                                { silent = true, desc = "Surround selection" })

                        -- yss<char> surrounds the whole line, matching
                        -- nvim-surround/vim-surround. mini ships no such
                        -- mapping -- `ys` there always wants a motion -- so
                        -- this feeds it the linewise `_` motion. remap = true
                        -- is required: the right-hand side has to go back
                        -- through mini's own expr-mapped `ys`.
                        vim.keymap.set("n", "yss", "ys_", { remap = true, desc = "Surround line" })
                end,
        },

        -- TREESITTER TEXTOBJECTS
        -- Syntax-aware motions: daf deletes a whole function, vif selects its
        -- body, ]f jumps to the next one. Worth the most in the C++ files below,
        -- where a function body is the unit you actually operate on.
        --
        -- `main` branch to match nvim-treesitter above -- the two branches have
        -- incompatible APIs, and pairing main treesitter with master textobjects
        -- fails at load. On main you call select_textobject() yourself rather
        -- than declaring a keymap table.
        --
        -- vim.g.no_plugin_maps is deliberately NOT set (the README suggests it):
        -- it disables EVERY built-in ftplugin mapping globally, which is a much
        -- wider blast radius than the handful of [[ / ]] motions it is meant to
        -- protect. The keys below avoid the ftplugin motions instead.
        {
                "nvim-treesitter/nvim-treesitter-textobjects",
                branch = "main",
                dependencies = { "nvim-treesitter/nvim-treesitter" },
                event = { "BufReadPost", "BufNewFile" },
                config = function()
                        require("nvim-treesitter-textobjects").setup({
                                select = {
                                        -- targets.vim behaviour: if there is no
                                        -- function under the cursor, jump forward to
                                        -- the next one rather than doing nothing.
                                        lookahead = true,
                                },
                                move = { set_jumps = true },
                        })

                        local sel = require("nvim-treesitter-textobjects.select")
                        local move = require("nvim-treesitter-textobjects.move")
                        local swap = require("nvim-treesitter-textobjects.swap")

                        -- af/if function, ac/ic class, aa/ia parameter,
                        -- al/il loop, ak/ik conditional ("k" for kond -- ic and
                        -- ii were already taken by class and nothing sensible
                        -- was left), a=/i= assignment, ar/ir return.
                        local objects = {
                                ["af"] = "@function.outer", ["if"] = "@function.inner",
                                ["ac"] = "@class.outer",    ["ic"] = "@class.inner",
                                ["aa"] = "@parameter.outer",["ia"] = "@parameter.inner",
                                ["al"] = "@loop.outer",     ["il"] = "@loop.inner",
                                ["ak"] = "@conditional.outer", ["ik"] = "@conditional.inner",
                                ["a="] = "@assignment.outer",  ["i="] = "@assignment.inner",
                                ["ar"] = "@return.outer",   ["ir"] = "@return.inner",
                        }
                        for lhs, query in pairs(objects) do
                                vim.keymap.set({ "x", "o" }, lhs, function()
                                        sel.select_textobject(query, "textobjects")
                                end, { desc = "textobject " .. query })
                        end

                        -- ]f / [f next & previous function start, ]F / [F its end.
                        -- ]m would be the vim-idiomatic choice but collides with
                        -- the built-in ftplugin method motions; ]c belongs to
                        -- gitsigns hunks above.
                        local moves = {
                                { "]f", move.goto_next_start, "@function.outer", "Next function" },
                                { "]F", move.goto_next_end,   "@function.outer", "Next function end" },
                                { "[f", move.goto_previous_start, "@function.outer", "Prev function" },
                                { "[F", move.goto_previous_end,   "@function.outer", "Prev function end" },
                                { "]a", move.goto_next_start, "@parameter.inner", "Next parameter" },
                                { "[a", move.goto_previous_start, "@parameter.inner", "Prev parameter" },
                        }
                        for _, m in ipairs(moves) do
                                local lhs, fn, query, desc = m[1], m[2], m[3], m[4]
                                vim.keymap.set({ "n", "x", "o" }, lhs, function()
                                        fn(query, "textobjects")
                                end, { desc = desc })
                        end

                        -- Reorder function arguments without touching the commas.
                        -- <leader>a / <leader>A, not <leader>s*: the <leader>s
                        -- prefix belongs to the Telescope search pickers, and
                        -- mixing "swap" and "search" under one key reads badly
                        -- in which-key.
                        vim.keymap.set("n", "<leader>a", function()
                                swap.swap_next("@parameter.inner")
                        end, { desc = "Swap parameter next" })
                        vim.keymap.set("n", "<leader>A", function()
                                swap.swap_previous("@parameter.inner")
                        end, { desc = "Swap parameter prev" })
                end,
        },

        -- SESSIONS
        -- Restores the buffers, window layout, folds and cwd of whatever you
        -- last had open in this directory. Added to close a gap that had been
        -- open silently: .tmux.conf set @resurrect-strategy-nvim 'session',
        -- which reopens nvim as `nvim -S Session.vim` -- but nothing in this
        -- config ever ran :mksession, so no Session.vim existed anywhere on
        -- disk and the strategy restored exactly nothing, every time. That
        -- line is gone now; this plugin is the replacement.
        --
        -- Deliberately NOT auto-loading on startup: `nvim file.py` should open
        -- file.py, not silently reinstate nine other buffers. tmux-resurrect
        -- brings the nvim process back (nvim is on its default whitelist) and
        -- <leader>qs brings the session back into it.
        --
        -- Sessions live in stdpath("state")/sessions keyed by cwd, so nothing
        -- is written into the repo itself -- which is also why this is safe
        -- with the dotfiles LaunchAgent that auto-commits and pushes.
        {
                "folke/persistence.nvim",
                event = "BufReadPre",
                opts = {},
                keys = {
                        { "<leader>qs", function() require("persistence").load() end, desc = "Session: restore for cwd" },
                        { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Session: restore last" },
                        { "<leader>qS", function() require("persistence").select() end, desc = "Session: pick" },
                        { "<leader>qd", function() require("persistence").stop() end, desc = "Session: stop saving" },
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

-- With netrw disabled nothing renders a directory buffer, so `nvim .` would
-- otherwise land on an empty unnamed buffer. Hand directory arguments to
-- nvim-tree instead; :NvimTreeOpen pulls the lazy-loaded plugin in on demand.
vim.api.nvim_create_autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("open_tree_on_directory", { clear = true }),
        desc = "Open nvim-tree when nvim is started on a directory",
        callback = function(event)
                local target = event.file
                if target == "" or vim.fn.isdirectory(target) ~= 1 then
                        return
                end

                local ok, err = pcall(function()
                        vim.cmd.cd(target)
                        vim.cmd.enew()
                        vim.cmd.bwipeout(event.buf)
                        vim.cmd.NvimTreeOpen()
                end)
                if not ok then
                        vim.notify("Could not open nvim-tree for " .. target .. ": " .. tostring(err), vim.log.levels.WARN)
                end
        end,
})

-- Indentation settings
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.softtabstop = 2

-- Live preview of :s///, :g and friends in a scratch split as you type the
-- pattern, showing the off-screen matches too. Default is "nosplit", which
-- highlights in place but shows nothing you cannot already see.
vim.opt.inccommand = "split"

-- Keep the text where it is when a split opens or closes above it. Default
-- ("cursor") keeps the cursor line fixed and lets everything else jump.
vim.opt.splitkeep = "screen"

-- One default border for every floating window nvim opens itself -- LSP hover,
-- signature help, diagnostic floats. Added in 0.11; before it, each of those
-- had to be passed border = "rounded" separately, which is why the LSP block
-- above sets it on its diagnostic float and blink.cmp sets it twice more.
vim.o.winborder = "rounded"

-- Briefly highlight the yanked region. The only feedback that a yank took the
-- range you meant -- without it an off-by-one motion is invisible until paste.
vim.api.nvim_create_autocmd("TextYankPost", {
        group = vim.api.nvim_create_augroup("highlight_on_yank", { clear = true }),
        desc = "Highlight yanked text",
        callback = function()
                vim.hl.on_yank({ timeout = 150 })
        end,
})

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

-- timeoutlen: how long vim waits for the REST of a multi-key mapping.
--
-- This was 300ms, which silently broke every two-key mapping whose first key
-- is also a complete command on its own -- ys, ds, cs, and every <leader>
-- sequence. `y` is both the yank operator and the start of mini.surround's
-- `ys`, so vim waits timeoutlen to disambiguate; pause longer than that
-- between y and s and it commits to plain `y`, the surround never fires, and
-- nothing at all appears to happen. 300ms is well inside a normal thinking
-- pause, so this read as "ysiw is broken" rather than as a timing problem.
--
-- Measured through real keystrokes (tmux send-keys into a live nvim, not
-- nvim_feedkeys -- its 'x' flag force-executes each chunk and aborts any
-- incomplete command, which makes every multi-key mapping look broken
-- regardless of this setting):
--     timeoutlen=300,  0.6s pause -> no surround   (3/3 runs)
--     timeoutlen=1000, 0.6s pause -> surrounds        (3/3 runs)
--     timeoutlen=1000, 1.5s pause -> no surround      (3/3 runs)
-- Identical results with the plugin preloaded, so lazy-loading is not a
-- factor.
--
-- Note the third line: this widens the window from 0.3s to 1s, it does not
-- remove it. Pausing longer than timeoutlen mid-sequence will always fall
-- back to plain `y`. That is inherent to mapping a two-key sequence whose
-- first key is a valid operator, and is the same deal vim-surround users
-- have always had at the default 1000.
--
-- Raised again to 3000 after using it: 1s is still a race when you are reading
-- the which-key popup to decide what comes next, and the "much above 1000 gets
-- laggy" worry that used to sit here does not survive contact with this
-- particular keymap. Every key that STARTS a sequence in this config -- y, d,
-- c, g, [, ] and <leader> itself -- is an incomplete command on its own: `d`
-- does nothing until it gets a motion, and <Space> has no solo mapping at all.
-- So the timeout never delays a command that could already have run; it only
-- decides how long you are allowed to take. A long timeout only bites on
-- complete-command prefixes, and this config maps none of those
-- (mini.surround takes ys/ds/cs, never bare s).
--
-- Terminal <Esc> latency is ttimeoutlen, not this, and stays at 50ms.
--
-- 300 was presumably chosen to make which-key pop up quickly. It never did
-- anything of the sort: which-key's delay is its own option and is explicitly
-- independent of timeoutlen (README: "Delay: delay is independent of
-- `timeoutlen`"), defaulting to 200ms. So the short timeout was pure downside.
--
-- 1000 is vim's own default. It costs nothing here: after `y`, any key that
-- cannot continue `ys` resolves instantly, so yy / yiw / yap are unaffected.
-- The wait only happens when what you typed really is still ambiguous.
vim.opt.timeoutlen = 3000

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

-- The cost of clipboard = "unnamedplus" at the top of this file: EVERY delete
-- and change goes to the system clipboard too, so yanking a line, deleting
-- another, then pasting gives you the deleted one. These route the common
-- throwaway edits to the black-hole register instead, leaving the clipboard
-- holding whatever you actually yanked.
--   <leader>d / <leader>D   delete without clobbering the clipboard
--   <leader>p (visual)      paste over a selection without capturing it
-- x is remapped outright: single-character deletes are never worth a clipboard
-- slot, and no muscle memory depends on x populating one.
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d', { desc = "Delete (no clipboard)" })
vim.keymap.set({ "n", "v" }, "<leader>D", '"_D', { desc = "Delete to EOL (no clipboard)" })
vim.keymap.set("x", "<leader>p", '"_dP', { desc = "Paste over (keep clipboard)" })
vim.keymap.set("n", "x", '"_x', { desc = "Delete char (no clipboard)" })

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
