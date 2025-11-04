-- Lifecycle management for diff views
-- Handles tracking, cleanup, and state restoration
local M = {}

local highlights = require('vscode-diff.render.highlights')

-- Track active diff sessions
-- Structure: { tabpage_id = { left_bufnr, right_bufnr, left_win, right_win } }
local active_diffs = {}

-- Autocmd group for cleanup
local augroup = vim.api.nvim_create_augroup('vscode_diff_lifecycle', { clear = true })

-- Setup lifecycle tracking for a new diff view
-- @param tabpage number: Tab page ID
-- @param left_bufnr number: Left buffer number
-- @param right_bufnr number: Right buffer number
-- @param left_win number: Left window ID
-- @param right_win number: Right window ID
function M.register(tabpage, left_bufnr, right_bufnr, left_win, right_win)
  active_diffs[tabpage] = {
    left_bufnr = left_bufnr,
    right_bufnr = right_bufnr,
    left_win = left_win,
    right_win = right_win,
  }
  
  -- Mark windows with our restore flag (similar to vim-fugitive)
  vim.w[left_win].vscode_diff_restore = 1
  vim.w[right_win].vscode_diff_restore = 1
end

-- Clear highlights and extmarks from a buffer
-- @param bufnr number: Buffer number to clean
local function clear_buffer_highlights(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  
  -- Clear both highlight and filler namespaces
  vim.api.nvim_buf_clear_namespace(bufnr, highlights.ns_highlight, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, highlights.ns_filler, 0, -1)
end

-- Cleanup a specific diff session
-- @param tabpage number: Tab page ID
local function cleanup_diff(tabpage)
  local diff = active_diffs[tabpage]
  if not diff then
    return
  end
  
  -- Clear highlights from both buffers
  clear_buffer_highlights(diff.left_bufnr)
  clear_buffer_highlights(diff.right_bufnr)
  
  -- Delete left buffer if it's a virtual file (starts with vscodediff://)
  if vim.api.nvim_buf_is_valid(diff.left_bufnr) then
    local bufname = vim.api.nvim_buf_get_name(diff.left_bufnr)
    if bufname:match('^vscodediff://') then
      pcall(vim.api.nvim_buf_delete, diff.left_bufnr, { force = true })
    end
  end
  
  -- Clear window variables if windows still exist
  if vim.api.nvim_win_is_valid(diff.left_win) then
    vim.w[diff.left_win].vscode_diff_restore = nil
  end
  if vim.api.nvim_win_is_valid(diff.right_win) then
    vim.w[diff.right_win].vscode_diff_restore = nil
  end
  
  -- Remove from tracking
  active_diffs[tabpage] = nil
end

-- Count windows in current tabpage that have diff markers
local function count_diff_windows()
  local count = 0
  for i = 1, vim.fn.winnr('$') do
    local win = vim.fn.win_getid(i)
    if vim.w[win].vscode_diff_restore then
      count = count + 1
    end
  end
  return count
end

-- Check if we should trigger cleanup for a window
local function should_cleanup(winid)
  return vim.w[winid].vscode_diff_restore and vim.api.nvim_win_is_valid(winid)
end

-- Setup autocmds for automatic cleanup
function M.setup_autocmds()
  -- When a window is closed, check if we should cleanup the diff
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    callback = function(args)
      local closed_win = tonumber(args.match)
      if not closed_win then
        return
      end
      
      -- Give Neovim a moment to update window state
      vim.schedule(function()
        -- Check if the closed window was part of a diff
        for tabpage, diff in pairs(active_diffs) do
          if diff.left_win == closed_win or diff.right_win == closed_win then
            -- If we're down to 1 or 0 diff windows, cleanup
            local diff_win_count = count_diff_windows()
            if diff_win_count <= 1 then
              cleanup_diff(tabpage)
            end
            break
          end
        end
      end)
    end,
  })
  
  -- When a tab is closed, cleanup its diff
  vim.api.nvim_create_autocmd('TabClosed', {
    group = augroup,
    callback = function()
      -- TabClosed doesn't give us the tab number, so we need to scan
      -- Remove any diffs for tabs that no longer exist
      local valid_tabs = {}
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        valid_tabs[tabpage] = true
      end
      
      for tabpage, _ in pairs(active_diffs) do
        if not valid_tabs[tabpage] then
          cleanup_diff(tabpage)
        end
      end
    end,
  })
  
  -- Fallback: When entering a buffer, check if we need cleanup
  vim.api.nvim_create_autocmd('BufEnter', {
    group = augroup,
    callback = function()
      local current_tab = vim.api.nvim_get_current_tabpage()
      local diff = active_diffs[current_tab]
      
      if diff then
        local diff_win_count = count_diff_windows()
        -- If only 1 diff window remains, the user likely closed the other side
        if diff_win_count == 1 then
          cleanup_diff(current_tab)
        end
      end
    end,
  })
end

-- Manual cleanup function (can be called explicitly)
function M.cleanup(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  cleanup_diff(tabpage)
end

-- Cleanup all active diffs (useful for plugin unload/reload)
function M.cleanup_all()
  for tabpage, _ in pairs(active_diffs) do
    cleanup_diff(tabpage)
  end
end

-- Initialize lifecycle management
function M.setup()
  M.setup_autocmds()
end

return M
