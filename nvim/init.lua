

-- ============================
-- CORE SETTINGS
-- ============================
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = false
vim.opt.background = "dark"    -- or "light" if you prefer

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
                        })
                        vim.keymap.set("n", "<leader>f", ":Telescope find_files<CR>", { noremap = true, silent = true })
                        vim.keymap.set("n", "<leader>g", ":Telescope live_grep<CR>", { noremap = true, silent = true })
                        vim.keymap.set("n", "<leader>p", ":Telescope oldfiles<CR>", { noremap = true, silent = true })
                        vim.keymap.set("n", "<leader>b", ":Telescope buffers<CR>", { noremap = true, silent = true })
                end
        },

        -- SYNTAX HIGHLIGHTING
        {
                "nvim-treesitter/nvim-treesitter",
                build = ":TSUpdate",
                config = function()
                        require("nvim-treesitter.configs").setup({
                                ensure_installed = { "python", "cpp", "lua", "vim", "bash", "markdown", "json", "yaml", "javascript", "typescript", "tsx", "html", "css"},
                                auto_install = true,
                                highlight = {
                                        enable = true,
                                        additional_vim_regex_highlighting = false,
                                },
                                indent = { enable = true },
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
                                window = {
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

                        local servers = { "pyright", "clangd", "ts_ls", "html", "cssls" }
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
                                format_on_save = {
                                        timeout_ms = 500,
                                        lsp_fallback = true,
                                },
                        })
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
