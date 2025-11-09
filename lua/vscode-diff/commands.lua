-- Command implementations for vscode-diff
local M = {}

local git = require("vscode-diff.git")
local diff = require("vscode-diff.diff")
local render = require("vscode-diff.render")

--- Handles diffing the current buffer against a given git revision.
-- @param revision string: The git revision (e.g., "HEAD", commit hash, branch name) to compare the current file against.
-- This function chains async git operations to get git root, resolve revision to hash, and get file content.
local function handle_git_diff(revision)
  local current_file = vim.api.nvim_buf_get_name(0)

  if current_file == "" then
    vim.notify("Current buffer is not a file", vim.log.levels.ERROR)
    return
  end

  -- Determine filetype from current buffer (sync operation, no git involved)
  local filetype = vim.bo[0].filetype
  if not filetype or filetype == "" then
    filetype = vim.filetype.match({ filename = current_file }) or ""
  end

  -- Async chain: get_git_root -> resolve_revision -> get_file_content -> render_diff
  git.get_git_root(current_file, function(err_root, git_root)
    if err_root then
      vim.schedule(function()
        vim.notify(err_root, vim.log.levels.ERROR)
      end)
      return
    end

    local relative_path = git.get_relative_path(current_file, git_root)

    git.resolve_revision(revision, git_root, function(err_resolve, commit_hash)
      if err_resolve then
        vim.schedule(function()
          vim.notify(err_resolve, vim.log.levels.ERROR)
        end)
        return
      end

      git.get_file_content(commit_hash, git_root, relative_path, function(err, lines_git)
        vim.schedule(function()
          if err then
            vim.notify(err, vim.log.levels.ERROR)
            return
          end

          -- Read fresh buffer content right before creating diff view
          local lines_current = vim.api.nvim_buf_get_lines(0, 0, -1, false)

          local config = require("vscode-diff.config")
          local diff_options = {
            max_computation_time_ms = config.options.diff.max_computation_time_ms,
          }
          local lines_diff = diff.compute_diff(lines_git, lines_current, diff_options)
          if not lines_diff then
            vim.notify("Failed to compute diff", vim.log.levels.ERROR)
            return
          end

          -- Create lifecycle session FIRST with git context
          local lifecycle = require('vscode-diff.render.lifecycle')
          -- Create new tab for diff view
          vim.cmd("tabnew")
          local tabpage = vim.api.nvim_get_current_tabpage()
          lifecycle.create_session(
            tabpage,
            "standalone",  -- mode
            git_root,      -- git_root
            relative_path, -- original_path
            relative_path, -- modified_path (same file, different versions)
            commit_hash,   -- original_revision (git version)
            "WORKING"      -- modified_revision (current working copy)
          )

          -- Now create diff view (it reads everything from lifecycle)
          render.create_diff_view(lines_git, lines_current, lines_diff, tabpage, filetype)
        end)
      end)
    end)
  end)
end

local function handle_file_diff(file_a, file_b)
  local lines_a = vim.fn.readfile(file_a)
  local lines_b = vim.fn.readfile(file_b)

  local config = require("vscode-diff.config")
  local diff_options = {
    max_computation_time_ms = config.options.diff.max_computation_time_ms,
  }
  local lines_diff = diff.compute_diff(lines_a, lines_b, diff_options)
  if not lines_diff then
    vim.notify("Failed to compute diff", vim.log.levels.ERROR)
    return
  end

  -- Determine filetype from first file
  local filetype = vim.filetype.match({ filename = file_a }) or ""

  -- Create lifecycle session FIRST (no git context for file compare)
  local lifecycle = require('vscode-diff.render.lifecycle')
  -- Create new tab for diff view
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  lifecycle.create_session(
    tabpage,
    "standalone",  -- mode
    nil,           -- git_root (no git for file compare)
    file_a,        -- original_path (absolute)
    file_b,        -- modified_path (absolute)
    nil,           -- original_revision (nil = non-git file)
    nil            -- modified_revision (nil = non-git file)
  )

  -- Create diff view (it reads everything from lifecycle)
  render.create_diff_view(lines_a, lines_b, lines_diff, tabpage, filetype)
end

function M.vscode_diff(opts)
  local args = opts.fargs

  if #args == 0 then
    vim.notify("TODO: File explorer not implemented yet. Usage: :CodeDiff file <revision> OR :CodeDiff file <file_a> <file_b>", vim.log.levels.WARN)
    return
  end

  local subcommand = args[1]

  if subcommand == "file" then
    if #args == 2 then
      -- :CodeDiff file HEAD
      handle_git_diff(args[2])
    elseif #args == 3 then
      -- :CodeDiff file file_a.txt file_b.txt
      handle_file_diff(args[2], args[3])
    else
      vim.notify("Usage: :CodeDiff file <revision> OR :CodeDiff file <file_a> <file_b>", vim.log.levels.ERROR)
    end
  elseif subcommand == "install" or subcommand == "install!" then
    -- :CodeDiff install or :CodeDiff install!
    -- Handle both :CodeDiff! install and :CodeDiff install!
    local force = opts.bang or subcommand == "install!"
    local installer = require("vscode-diff.installer")
    
    if force then
      vim.notify("Reinstalling libvscode-diff...", vim.log.levels.INFO)
    end
    
    local success, err = installer.install({ force = force, silent = false })
    
    if success then
      vim.notify("libvscode-diff installation successful!", vim.log.levels.INFO)
    else
      vim.notify("Installation failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  else
    -- :CodeDiff without "file" is reserved for explorer mode (not implemented yet)
    vim.notify("TODO: Explorer mode not implemented. Use :CodeDiff file <revision> for now", vim.log.levels.WARN)
  end
end

return M
