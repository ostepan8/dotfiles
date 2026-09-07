

-- ============================
-- CORE SETTINGS
-- ============================
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = false
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
                dependencies = { "nvim-lua/plenary.nvim" },
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
                        vim.keymap.set("n", "<leader>f", ":Telescope find_files<CR>", { noremap = true, silent = true })
                        vim.keymap.set("n", "<leader>g", ":Telescope live_grep<CR>", { noremap = true, silent = true })
                        vim.keymap.set("n", "<leader>p", ":Telescope oldfiles<CR>", { noremap = true, silent = true })
                        vim.keymap.set("n", "<leader>b", ":Telescope buffers<CR>", { noremap = true, silent = true })
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
                        })

                        -- Filetypes whose name differs from the parser (language) name.
                        vim.treesitter.language.register("tsx", "typescriptreact")
                        vim.treesitter.language.register("javascript", "javascriptreact")
                        vim.treesitter.language.register("bash", "sh")

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
        { "tpope/vim-fugitive" },
        {
                "lewis6991/gitsigns.nvim",
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
                config = function() require("Comment").setup() end
        },

        -- STATUSLINE
        {
                "nvim-lualine/lualine.nvim",
                dependencies = { "nvim-tree/nvim-web-devicons" },
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
                dependencies = {
                        "hrsh7th/cmp-nvim-lsp",
                },
                config = function()
                        local capabilities = require("cmp_nvim_lsp").default_capabilities()

                        vim.diagnostic.config({
                                virtual_text = true,
                                signs = true,
                                underline = true,
                                update_in_insert = false,
                                severity_sort = true,
                        })

                        vim.api.nvim_create_autocmd("LspAttach", {
                                callback = function(args)
                                        local o = { noremap = true, silent = true, buffer = args.buf }
                                        vim.keymap.set("n", "gd", vim.lsp.buf.definition, o)
                                        vim.keymap.set("n", "K", vim.lsp.buf.hover, o)
                                        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, o)
                                        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, o)
                                        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, o)
                                        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, o)
                                end,
                        })

                        local servers = { "pyright", "clangd", "ts_ls", "html", "cssls", "luau_lsp" }
                        for _, server in ipairs(servers) do
                                vim.lsp.config(server, {
                                        capabilities = capabilities,
                                })
                        end
                        vim.lsp.enable(servers)
                end
        },

        -- AUTOCOMPLETE
        {
                "hrsh7th/nvim-cmp",
                dependencies = {
                        "hrsh7th/cmp-nvim-lsp",
                        "hrsh7th/cmp-buffer",
                        "hrsh7th/cmp-path",
                        "L3MON4D3/LuaSnip",
                        "saadparwaiz1/cmp_luasnip",
                },
                config = function()
                        local cmp = require("cmp")
                        local luasnip = require("luasnip")

                        cmp.setup({
                                snippet = {
                                        expand = function(args)
                                                luasnip.lsp_expand(args.body)
                                        end,
                                },
                                mapping = cmp.mapping.preset.insert({
                                        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
                                        ["<C-f>"] = cmp.mapping.scroll_docs(4),
                                        ["<C-Space>"] = cmp.mapping.complete(),
                                        ["<C-e>"] = cmp.mapping.abort(),
                                        ["<CR>"] = cmp.mapping.confirm({ select = true }),
                                        ["<Tab>"] = cmp.mapping(function(fallback)
                                                if cmp.visible() then
                                                        cmp.select_next_item()
                                                elseif luasnip.expand_or_jumpable() then
                                                        luasnip.expand_or_jump()
                                                else
                                                        fallback()
                                                end
                                        end, { "i", "s" }),
                                        ["<S-Tab>"] = cmp.mapping(function(fallback)
                                                if cmp.visible() then
                                                        cmp.select_prev_item()
                                                elseif luasnip.jumpable(-1) then
                                                        luasnip.jump(-1)
                                                else
                                                        fallback()
                                                end
                                        end, { "i", "s" }),
                                }),
                                sources = cmp.config.sources({
                                        { name = "nvim_lsp" },
                                        { name = "luasnip" },
                                        { name = "buffer" },
                                        { name = "path" },
                                }),
                        })
                end
        },

        -- FORMATTER
        {
                "stevearc/conform.nvim",
                config = function()
                        require("conform").setup({
                                formatters_by_ft = {
                                        python = { "black" },
                                        cpp = { "clang-format" },
                                        lua = { "stylua" },
                                        javascript = { "prettier" },
                                        typescript = { "prettier" },
                                        javascriptreact = { "prettier" },
                                        typescriptreact = { "prettier" },
                                },
                                -- Autoformat on save for everything EXCEPT cpp — during a
                                -- contest you don't want clang-format reflowing your solution
                                -- (or adding save latency). Format cpp manually with <leader>F.
                                format_on_save = function(bufnr)
                                        if vim.bo[bufnr].filetype == "cpp" then
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

        -- TMUX NAVIGATOR (works with your tmux config!)
        {
                "christoomey/vim-tmux-navigator",
                lazy = false,
        },

        -- OPENCODE
        {
                "sudo-tee/opencode.nvim",
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
        -- this is loaded on demand and skipped entirely on a terminal that
        -- cannot draw pixels (a plain ssh session, Terminal.app, a CI runner) —
        -- where it would otherwise emit escape garbage into the buffer.
        {
                "3rd/image.nvim",
                ft = { "pdf" },
                cond = function()
                        local capable = require("pdfview.deps").graphics_capable()
                        return capable
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

-- Better window navigation (works with tmux!)
vim.keymap.set("n", "<C-h>", "<C-w>h", { noremap = true, silent = true })
vim.keymap.set("n", "<C-j>", "<C-w>j", { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { noremap = true, silent = true })

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
