-- vscode-diff main API
local M = {}

-- Configuration setup - the ONLY public API users need
function M.setup(opts)
  local config = require("codediff.config")
  config.setup(opts)

  local render = require("codediff.ui")
  render.setup_highlights()
end

-- 3-way merge for arbitrary files (non-git)
-- Opens a merge view with REMOTE (left), LOCAL (right), and result (bottom) buffers
-- @param local_path string Path to LOCAL file (your version)
-- @param remote_path string Path to REMOTE file (their version)
-- @param base_path string Path to BASE file (common ancestor)
-- @return table|false Merge view info or false on error
function M.merge_files(local_path, remote_path, base_path)
  local merge = require("codediff.merge_files")
  return merge.merge_files(local_path, remote_path, base_path)
end

return M
