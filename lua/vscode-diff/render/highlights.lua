-- Highlight setup for diff rendering
local M = {}
local config = require('vscode-diff.config')

-- Namespaces for highlights and fillers
M.ns_highlight = vim.api.nvim_create_namespace("vscode-diff-highlight")
M.ns_filler = vim.api.nvim_create_namespace("vscode-diff-filler")

-- Helper function to adjust color brightness
local function adjust_brightness(color, factor)
  if not color then return nil end
  local r = math.floor(color / 65536) % 256
  local g = math.floor(color / 256) % 256
  local b = color % 256

  -- Apply factor and clamp to 0-255
  r = math.min(255, math.floor(r * factor))
  g = math.min(255, math.floor(g * factor))
  b = math.min(255, math.floor(b * factor))

  return r * 65536 + g * 256 + b
end

-- Setup VSCode-style highlight groups
function M.setup()
  -- Get base highlight colors from config
  local line_insert_hl = vim.api.nvim_get_hl(0, { name = config.options.highlights.line_insert })
  local line_delete_hl = vim.api.nvim_get_hl(0, { name = config.options.highlights.line_delete })
  local char_brightness = config.options.highlights.char_brightness

  -- Line-level highlights: Use base colors directly (DiffAdd, DiffDelete)
  vim.api.nvim_set_hl(0, "CodeDiffLineInsert", {
    bg = line_insert_hl.bg or 0x1d3042,  -- Fallback to default green
    default = true,
  })

  vim.api.nvim_set_hl(0, "CodeDiffLineDelete", {
    bg = line_delete_hl.bg or 0x351d2b,  -- Fallback to default red
    default = true,
  })

  -- Character-level highlights: Brighter versions of line highlights
  vim.api.nvim_set_hl(0, "CodeDiffCharInsert", {
    bg = adjust_brightness(line_insert_hl.bg, char_brightness) or 0x2a4556,  -- Brighter green
    default = true,
  })

  vim.api.nvim_set_hl(0, "CodeDiffCharDelete", {
    bg = adjust_brightness(line_delete_hl.bg, char_brightness) or 0x4b2a3d,  -- Brighter red
    default = true,
  })

  -- Filler lines (no highlight, inherits editor default background)
  vim.api.nvim_set_hl(0, "CodeDiffFiller", {
    fg = "#444444",  -- Subtle gray for the slash character
    default = true,
  })
  
  -- Explorer directory text (smaller and dimmed)
  vim.api.nvim_set_hl(0, "ExplorerDirectorySmall", {
    link = "Comment",
    default = true,
  })

  -- Explorer selected file
  vim.api.nvim_set_hl(0, "CodeDiffExplorerSelected", {
    link = "Visual",
    default = true,
  })
end

return M
