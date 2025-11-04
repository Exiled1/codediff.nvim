#!/usr/bin/env bash
# Integration test: Verify virtual buffer diagnostics are disabled

set -e

cd "$(dirname "$0")/.."

echo "=== Integration Test: Virtual Buffer Diagnostics ==="
echo

# Create a test script
cat > /tmp/test_vscode_diff_diagnostics.lua << 'EOF'
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd('runtime! plugin/*.lua plugin/*.vim')
require('vscode-diff').setup()

-- Navigate to git repo
vim.cmd('cd ' .. vim.fn.getcwd())

-- Edit a file that exists in history
vim.cmd('edit lua/vscode-diff/git.lua')

-- Run CodeDiff
vim.cmd('CodeDiff HEAD~5')

-- Wait for diff view to be created
vim.wait(2000, function()
  return #vim.api.nvim_list_wins() > 1
end, 100)

-- Wait for async BufReadCmd callback to complete and disable diagnostics
vim.wait(1000)

-- Check all windows and buffers
local wins = vim.api.nvim_list_wins()
local virtual_buf_found = false
local virtual_buf_diag_disabled = false

for _, win in ipairs(wins) do
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  local is_virtual = name:match('^vscodediff://')
  
  if is_virtual then
    virtual_buf_found = true
    local diag_enabled = vim.diagnostic.is_enabled({bufnr = buf})
    if not diag_enabled then
      virtual_buf_diag_disabled = true
    end
    print(string.format('Virtual buffer %d: diagnostics=%s', buf, 
      diag_enabled and 'ENABLED (FAIL)' or 'DISABLED (PASS)'))
  end
end

if not virtual_buf_found then
  print('ERROR: No virtual buffer found')
  vim.cmd('cquit 1')
elseif not virtual_buf_diag_disabled then
  print('ERROR: Virtual buffer has diagnostics enabled')
  vim.cmd('cquit 1')
else
  print('SUCCESS: Virtual buffer has diagnostics disabled')
  vim.cmd('cquit 0')
end
EOF

# Run the test
echo "Running test..."
if nvim --headless -u /tmp/test_vscode_diff_diagnostics.lua 2>&1 | tee /tmp/test_output.log | grep -q "SUCCESS"; then
  echo
  echo "✓ Test passed: Virtual buffer diagnostics are properly disabled"
  exit 0
else
  echo
  echo "✗ Test failed"
  cat /tmp/test_output.log
  exit 1
fi
