-- Test init file for plenary tests
-- This loads the plugin and plenary.nvim

-- Disable auto-installation in tests (library is already built by CI)
vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = "1"

-- Add current directory to runtimepath
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)

-- Ensure lua/ directory is in package.path for direct requires
package.path = package.path .. ";" .. cwd .. "/lua/?.lua;" .. cwd .. "/lua/?/init.lua"

vim.opt.swapfile = false

-- Setup plenary.nvim in Neovim's data directory (proper location)
local plenary_dir = vim.fn.stdpath("data") .. "/plenary.nvim"
if vim.fn.isdirectory(plenary_dir) == 0 then
  -- Clone plenary if not found
  print("Installing plenary.nvim for tests...")
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/nvim-lua/plenary.nvim",
    plenary_dir,
  })
end
vim.opt.rtp:prepend(plenary_dir)

-- Setup nui.nvim (required for explorer mode)
local nui_dir = vim.fn.stdpath("data") .. "/nui.nvim"
if vim.fn.isdirectory(nui_dir) == 0 then
  print("Installing nui.nvim for tests...")
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/MunifTanjim/nui.nvim",
    nui_dir,
  })
end
vim.opt.rtp:prepend(nui_dir)

-- Load plugin files (for integration tests that need commands)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')

-- Setup plugin
require("vscode-diff").setup()
