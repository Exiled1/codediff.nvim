-- Command implementations for vscode-diff
local M = {}

local git = require("vscode-diff.git")
local diff = require("vscode-diff.diff")
local render = require("vscode-diff.render")

--- Handles diffing the current buffer against a given git revision.
-- @param revision string: The git revision (e.g., "HEAD", commit hash) to compare the current file against.
-- This function checks if the current buffer is a file and part of a git repository,
-- then asynchronously retrieves the file at the specified revision and computes the diff
-- between that version and the current buffer. The diff view is rendered after scheduling
-- the UI update to ensure thread safety.
local function handle_git_diff(revision)
  local current_file = vim.api.nvim_buf_get_name(0)

  if current_file == "" then
    vim.notify("Current buffer is not a file", vim.log.levels.ERROR)
    return
  end

  if not git.is_in_git_repo(current_file) then
    vim.notify("Current file is not in a git repository", vim.log.levels.ERROR)
    return
  end

  git.get_file_at_revision(revision, current_file, function(err, lines_git)
    vim.schedule(function()
      if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end

      -- Read fresh buffer content right before creating diff view
      -- This ensures we diff against the current buffer state, not a snapshot
      local lines_current = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      
      local lines_diff = diff.compute_diff(lines_git, lines_current)
      
      -- Get git root and relative path for virtual file URL
      local git_root = git.get_git_root(current_file)
      local relative_path = git.get_relative_path(current_file, git_root)
      
      -- Determine filetype from current buffer
      local filetype = vim.bo[0].filetype
      if not filetype or filetype == "" then
        filetype = vim.filetype.match({ filename = current_file })
      end
      
      render.create_diff_view(lines_git, lines_current, lines_diff, {
        left_type = render.BufferType.VIRTUAL_FILE,
        left_config = {
          git_root = git_root,
          git_revision = revision,
          relative_path = relative_path,
        },
        right_type = render.BufferType.REAL_FILE,
        right_config = {
          file_path = current_file,
        },
        filetype = filetype,
      })
    end)
  end)
end

local function handle_file_diff(file_a, file_b)
  local lines_a = vim.fn.readfile(file_a)
  local lines_b = vim.fn.readfile(file_b)

  local lines_diff = diff.compute_diff(lines_a, lines_b)
  
  -- Determine filetype from first file
  local filetype = vim.filetype.match({ filename = file_a })
  
  render.create_diff_view(lines_a, lines_b, lines_diff, {
    left_type = render.BufferType.REAL_FILE,
    left_config = { file_path = file_a },
    right_type = render.BufferType.REAL_FILE,
    right_config = { file_path = file_b },
    filetype = filetype,
  })
end

function M.vscode_diff(opts)
  local args = opts.fargs

  if #args == 0 then
    vim.notify("Usage: :CodeDiff <file_a> <file_b> OR :CodeDiff <revision>", vim.log.levels.ERROR)
    return
  end

  if #args == 1 then
    handle_git_diff(args[1])
  elseif #args == 2 then
    handle_file_diff(args[1], args[2])
  else
    vim.notify("Usage: :CodeDiff <file_a> <file_b> OR :CodeDiff <revision>", vim.log.levels.ERROR)
  end
end

return M
