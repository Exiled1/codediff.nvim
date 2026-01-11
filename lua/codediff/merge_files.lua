-- Non-git 3-way merge for arbitrary files
-- Enables use as ChezMoi merge tool or other non-git merge scenarios

local M = {}

--- Read file into lines array
---@param path string Absolute path to file
---@return string[]|nil lines Array of lines from file, or nil on error
---@return string|nil error Error message if failed
local function read_file_lines(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, "Cannot open file: " .. (err or "unknown error")
  end

  local content = file:read("*all")
  file:close()

  -- Split content into lines, preserving empty lines
  local lines = {}
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end

  -- Remove trailing empty line if file didn't end with newline
  if #lines > 0 and lines[#lines] == "" and not content:match("\n$") then
    table.remove(lines)
  end

  return lines, nil
end

--- Perform 3-way merge on arbitrary files (non-git)
--- Creates a new tab with 3-way merge view:
--- - Left: REMOTE (incoming) file
--- - Right: LOCAL (current) file
--- - Bottom: Result buffer (editable, initially LOCAL content or BASE if conflict markers)
---
---@param local_path string Path to LOCAL file (your version)
---@param remote_path string Path to REMOTE file (their version)
---@param base_path string Path to BASE file (common ancestor)
---@return table|false result Table with merge view info, or false on error
function M.merge_files(local_path, remote_path, base_path)
  -- Get config for options
  local config = require("codediff.config")

  -- 1. Validate and expand file paths
  local_path = vim.fn.expand(local_path)
  remote_path = vim.fn.expand(remote_path)
  base_path = vim.fn.expand(base_path)

  for name, path in pairs({ LOCAL = local_path, REMOTE = remote_path, BASE = base_path }) do
    if vim.fn.filereadable(path) == 0 then
      vim.notify(string.format("%s file not found: %s", name, path), vim.log.levels.ERROR)
      return false
    end
  end

  -- Make paths absolute
  local_path = vim.fn.fnamemodify(local_path, ":p")
  remote_path = vim.fn.fnamemodify(remote_path, ":p")
  base_path = vim.fn.fnamemodify(base_path, ":p")

  -- 2. Read all three files
  local local_lines, local_err = read_file_lines(local_path)
  if not local_lines then
    vim.notify("Failed to read LOCAL file: " .. local_err, vim.log.levels.ERROR)
    return false
  end

  local remote_lines, remote_err = read_file_lines(remote_path)
  if not remote_lines then
    vim.notify("Failed to read REMOTE file: " .. remote_err, vim.log.levels.ERROR)
    return false
  end

  local base_lines, base_err = read_file_lines(base_path)
  if not base_lines then
    vim.notify("Failed to read BASE file: " .. base_err, vim.log.levels.ERROR)
    return false
  end

  -- 3. Create new tab and window layout
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()

  -- Create left/right split (respects original_position config)
  local split_cmd = config.options.diff.original_position == "right" and "leftabove vsplit" or "vsplit"
  vim.cmd(split_cmd)

  local remote_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd w")
  local local_win = vim.api.nvim_get_current_win()

  -- 4. Create and populate scratch buffers for remote and local
  local remote_bufnr = vim.api.nvim_create_buf(false, true)
  local local_bufnr = vim.api.nvim_create_buf(false, true)

  -- Set descriptive buffer names
  local remote_name = "merge://REMOTE/" .. vim.fn.fnamemodify(remote_path, ":t")
  local local_name = "merge://LOCAL/" .. vim.fn.fnamemodify(local_path, ":t")
  vim.api.nvim_buf_set_name(remote_bufnr, remote_name)
  vim.api.nvim_buf_set_name(local_bufnr, local_name)

  -- Populate buffers with content
  vim.api.nvim_buf_set_lines(remote_bufnr, 0, -1, false, remote_lines)
  vim.api.nvim_buf_set_lines(local_bufnr, 0, -1, false, local_lines)

  -- Set buffer options (read-only scratch buffers)
  for _, bufnr in ipairs({ remote_bufnr, local_bufnr }) do
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false
  end

  -- Set filetype for syntax highlighting
  local filetype = vim.filetype.match({ filename = local_path }) or ""
  if filetype ~= "" then
    vim.bo[remote_bufnr].filetype = filetype
    vim.bo[local_bufnr].filetype = filetype
  end

  -- Attach buffers to windows
  vim.api.nvim_win_set_buf(remote_win, remote_bufnr)
  vim.api.nvim_win_set_buf(local_win, local_bufnr)

  -- 5. Compute diffs: base → remote, base → local
  local diff_module = require("codediff.core.diff")
  local diff_options = {
    max_computation_time_ms = config.options.diff.max_computation_time_ms,
  }

  local base_to_remote_diff = diff_module.compute_diff(base_lines, remote_lines, diff_options)
  if not base_to_remote_diff then
    vim.notify("Failed to compute base→remote diff", vim.log.levels.ERROR)
    vim.cmd("tabclose")
    return false
  end

  local base_to_local_diff = diff_module.compute_diff(base_lines, local_lines, diff_options)
  if not base_to_local_diff then
    vim.notify("Failed to compute base→local diff", vim.log.levels.ERROR)
    vim.cmd("tabclose")
    return false
  end

  -- 6. Render merge view (highlights and filler lines)
  local core = require("codediff.ui.core")
  local render_result = core.render_merge_view(
    remote_bufnr,
    local_bufnr,
    base_to_remote_diff,
    base_to_local_diff,
    base_lines,
    remote_lines,
    local_lines
  )

  -- 7. Create result window (bottom split)
  vim.api.nvim_set_current_win(local_win)
  vim.cmd("belowright split " .. vim.fn.fnameescape(local_path))
  local result_win = vim.api.nvim_get_current_win()
  local result_bufnr = vim.api.nvim_get_current_buf()

  -- Rearrange: move remote to be vertical split with local
  vim.fn.win_splitmove(remote_win, local_win, { vertical = true, rightbelow = false })

  -- Set result window height (30% of total or minimum 10 lines)
  local result_height = math.max(10, math.floor(vim.o.lines * 0.3))
  vim.api.nvim_win_set_height(result_win, result_height)

  -- Reset content to BASE (required for conflict tracking to work)
  -- The conflict blocks are positioned relative to BASE content
  vim.api.nvim_buf_set_lines(result_bufnr, 0, -1, false, base_lines)
  vim.bo[result_bufnr].modified = true

  if filetype ~= "" then
    vim.bo[result_bufnr].filetype = filetype
  end

  -- 8. Create lifecycle session
  local lifecycle = require("codediff.ui.lifecycle")
  lifecycle.create_session(
    tabpage,
    "standalone", -- mode
    nil, -- git_root (no git!)
    remote_path, -- original_path (absolute)
    local_path, -- modified_path (absolute)
    nil, -- original_revision
    nil, -- modified_revision
    remote_bufnr,
    local_bufnr,
    remote_win,
    local_win,
    base_to_local_diff -- stored_diff_result
  )

  -- Set result buffer info in session
  lifecycle.set_result(tabpage, result_bufnr, result_win)
  lifecycle.set_result_base_lines(tabpage, base_lines)
  lifecycle.set_conflict_blocks(tabpage, render_result.conflict_blocks)

  -- Track conflict file for unsaved warnings
  lifecycle.track_conflict_file(tabpage, local_path)

  -- 9. Initialize conflict tracking and keymaps
  local conflict = require("codediff.ui.conflict")

  -- Initialize extmark-based conflict tracking
  conflict.initialize_tracking(result_bufnr, render_result.conflict_blocks)

  -- Setup auto-refresh of conflict signs on buffer changes
  conflict.setup_sign_refresh_autocmd(tabpage, result_bufnr)

  -- Initial sign refresh
  local session = lifecycle.get_session(tabpage)
  if session then
    conflict.refresh_all_conflict_signs(session)
  end

  -- Setup view keymaps (quit, navigation, etc.)
  local view_keymaps = require("codediff.ui.view.keymaps")
  view_keymaps.setup_all_keymaps(tabpage, remote_bufnr, local_bufnr, false)

  -- Setup conflict resolution keymaps (accept incoming/current/both, etc.)
  conflict.setup_keymaps(tabpage)

  -- 10. Set window options
  -- Disable wrap
  vim.wo[remote_win].wrap = false
  vim.wo[local_win].wrap = false
  vim.wo[result_win].wrap = false

  -- Set cursor to top of all windows
  vim.api.nvim_win_set_cursor(remote_win, { 1, 0 })
  vim.api.nvim_win_set_cursor(local_win, { 1, 0 })
  vim.api.nvim_win_set_cursor(result_win, { 1, 0 })

  -- Enable scrollbind for synchronized scrolling
  vim.wo[remote_win].scrollbind = true
  vim.wo[local_win].scrollbind = true
  vim.wo[result_win].scrollbind = true

  -- Disable inlay hints if configured
  if config.options.diff.disable_inlay_hints then
    vim.lsp.inlay_hint.enable(false, { bufnr = remote_bufnr })
    vim.lsp.inlay_hint.enable(false, { bufnr = local_bufnr })
    vim.lsp.inlay_hint.enable(false, { bufnr = result_bufnr })
  end

  -- Set cursorline for better visibility
  vim.wo[remote_win].cursorline = true
  vim.wo[local_win].cursorline = true
  vim.wo[result_win].cursorline = true

  -- Return merge view info
  return {
    tabpage = tabpage,
    remote_bufnr = remote_bufnr,
    local_bufnr = local_bufnr,
    result_bufnr = result_bufnr,
    remote_win = remote_win,
    local_win = local_win,
    result_win = result_win,
    conflict_blocks = render_result.conflict_blocks,
  }
end

return M
