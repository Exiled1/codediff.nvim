-- Configuration module
local M = {}

M.defaults = {
  -- Highlight configuration
  highlights = {
    -- Base highlight groups to derive colors from
    line_insert = "DiffAdd",      -- Line-level insertions (base color)
    line_delete = "DiffDelete",   -- Line-level deletions (base color)

    -- Character-level highlights use brighter versions of line highlights
    char_brightness = 1.4,  -- Multiplier for character backgrounds (1.3 = 130% = brighter)
  },

  -- Diff view behavior
  diff = {
    disable_inlay_hints = true,  -- Disable inlay hints in diff windows for cleaner view
    max_computation_time_ms = 5000,  -- Maximum time for diff computation (5 seconds, VSCode default)
  },

  -- Keymaps
  keymaps = {
    view = {
      next_hunk = "]c",
      prev_hunk = "[c",
      next_file = "]f",
      prev_file = "[f",
    },
    explorer = {
      select = "<CR>",
      hover = "K",
      refresh = "R",
    },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
