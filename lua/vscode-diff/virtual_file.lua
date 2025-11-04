-- Virtual file scheme for git revisions
-- Inspired by vim-fugitive's fugitive:// URL scheme
-- This allows LSP to attach to git historical content

local M = {}

local api = vim.api

-- Create a fugitive-style URL for a git revision
-- Format: vscodediff:///<git-root>///<commit>/<filepath>
function M.create_url(git_root, commit, filepath)
  -- Encode components to handle special characters
  local encoded_root = vim.fn.fnamemodify(git_root, ':p'):gsub('/$', '')
  local encoded_commit = commit or 'HEAD'
  local encoded_path = filepath:gsub('^/', '')
  
  return string.format('vscodediff:///%s///%s/%s', 
    encoded_root, encoded_commit, encoded_path)
end

-- Parse a vscodediff:// URL
-- Returns: git_root, commit, filepath
function M.parse_url(url)
  local pattern = '^vscodediff:///(.-)///([^/]+)/(.+)$'
  local git_root, commit, filepath = url:match(pattern)
  return git_root, commit, filepath
end

-- Setup the BufReadCmd autocmd to handle vscodediff:// URLs
function M.setup()
  -- Create autocmd group
  local group = api.nvim_create_augroup('VscodeDiffVirtualFile', { clear = true })
  
  -- Handle reading vscodediff:// URLs
  api.nvim_create_autocmd('BufReadCmd', {
    group = group,
    pattern = 'vscodediff:///*',
    callback = function(args)
      local url = args.match
      local buf = args.buf
      
      local git_root, commit, filepath = M.parse_url(url)
      
      if not git_root or not commit or not filepath then
        vim.notify('Invalid vscodediff URL: ' .. url, vim.log.levels.ERROR)
        return
      end
      
      -- Set buffer options FIRST to prevent LSP attachment
      -- LSP checks buftype when deciding whether to attach
      vim.bo[buf].buftype = 'nowrite'
      vim.bo[buf].bufhidden = 'wipe'  -- Auto-delete when hidden
      
      -- Get the file content from git
      local git = require('vscode-diff.git')
      local full_path = git_root .. '/' .. filepath
      
      git.get_file_at_revision(commit, full_path, function(err, lines)
        vim.schedule(function()
          if err then
            -- Set error message in buffer
            api.nvim_buf_set_lines(buf, 0, -1, false, {
              'Error reading from git:',
              err
            })
            vim.bo[buf].modifiable = false
            vim.bo[buf].readonly = true
            return
          end
          
          -- Set the content
          api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          
          -- Make it read-only
          vim.bo[buf].modifiable = false
          vim.bo[buf].readonly = true
          
          -- Detect filetype from the original file path (for TreeSitter only)
          local ft = vim.filetype.match({ filename = filepath })
          if ft then
            vim.bo[buf].filetype = ft
          end
          
          -- Disable diagnostics for this buffer completely
          -- This prevents LSP diagnostics from showing even though LSP might attach
          vim.diagnostic.enable(false, { bufnr = buf })
          
          api.nvim_exec_autocmds('User', {
            pattern = 'VscodeDiffVirtualFileLoaded',
            data = { buf = buf }
          })
          
          -- DO NOT trigger BufRead - we don't want LSP to attach
          -- TreeSitter will work from filetype alone
        end)
      end)
    end,
  })
  
  -- Prevent writing to these buffers
  api.nvim_create_autocmd('BufWriteCmd', {
    group = group,
    pattern = 'vscodediff:///*',
    callback = function()
      vim.notify('Cannot write to git revision buffer', vim.log.levels.WARN)
    end,
  })
end

return M
