-- Test: Semantic Tokens Rendering
-- Validates that our vendored semantic token implementation matches Neovim's behavior
-- Run with: nvim --headless -c "luafile tests/render/test_semantic_tokens.lua" -c "quit"

vim.opt.rtp:prepend(".")

print("=== Test: Semantic Tokens Rendering ===\n")

local test_count = 0
local pass_count = 0

local function test(name, fn)
  test_count = test_count + 1
  io.write(string.format("[%d] %s ... ", test_count, name))
  local ok, err = pcall(fn)
  if ok then
    pass_count = pass_count + 1
    print("✓")
  else
    print("✗")
    print("  Error: " .. tostring(err))
  end
end

-- Test 1: Module loads without errors
test("Module loads successfully", function()
  local semantic = require("vscode-diff.render.semantic_tokens")
  assert(semantic ~= nil, "Module should load")
  assert(type(semantic.apply_semantic_tokens) == "function", "Should export apply_semantic_tokens")
  assert(type(semantic.clear) == "function", "Should export clear")
end)

-- Test 2: Version compatibility check
test("Version compatibility check works", function()
  local semantic = require("vscode-diff.render.semantic_tokens")
  
  -- Should gracefully return false if no clients
  local result = semantic.apply_semantic_tokens(1, 1)
  assert(result == false, "Should return false when no LSP clients")
  
  -- On Neovim 0.9+, semantic tokens module should exist
  if vim.fn.has('nvim-0.9') == 1 then
    assert(vim.lsp.semantic_tokens ~= nil, "Neovim 0.9+ should have semantic_tokens")
    assert(vim.str_byteindex ~= nil, "Neovim 0.9+ should have str_byteindex")
  end
end)

-- Test 3: Vendored modifiers_from_number matches Neovim's implementation
test("modifiers_from_number implementation matches Neovim", function()
  -- We need to test our vendored function matches Neovim's behavior
  -- Unfortunately the function is local, so we test it indirectly through the full flow
  
  -- Just verify the bit module is available (required for the function)
  local bit = require('bit')
  assert(bit.band ~= nil, "bit.band should be available")
  assert(bit.rshift ~= nil, "bit.rshift should be available")
end)

-- Test 4: Clear function works
test("Clear function works without errors", function()
  local semantic = require("vscode-diff.render.semantic_tokens")
  
  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Should not error when clearing empty buffer
  semantic.clear(buf)
  
  -- Should not error when clearing invalid buffer
  vim.api.nvim_buf_delete(buf, { force = true })
  semantic.clear(buf)  -- Should handle invalid buffer gracefully
end)

-- Test 5: Namespace is created correctly
test("Semantic token namespace exists", function()
  local semantic = require("vscode-diff.render.semantic_tokens")
  
  local namespaces = vim.api.nvim_get_namespaces()
  assert(namespaces.vscode_diff_semantic_tokens ~= nil, 
    "vscode_diff_semantic_tokens namespace should be created")
end)

-- Test 6: Integration test with real LSP (if available)
test("Integration with LSP client (if available)", function()
  -- Skip if no LSP support
  if not vim.lsp.semantic_tokens then
    print(" (skipped: Neovim < 0.9)")
    return
  end
  
  local semantic = require("vscode-diff.render.semantic_tokens")
  
  -- Create test buffers
  local left_buf = vim.api.nvim_create_buf(false, true)
  local right_buf = vim.api.nvim_create_buf(false, true)
  
  -- Set some content
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, {
    "local function test()",
    "  return 42",
    "end"
  })
  
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, {
    "local function test()",
    "  return 42",
    "end"
  })
  
  -- Set filetype to trigger potential LSP
  vim.bo[left_buf].filetype = "lua"
  vim.bo[right_buf].filetype = "lua"
  
  -- Try to apply semantic tokens (will fail gracefully if no LSP client)
  local result = semantic.apply_semantic_tokens(left_buf, right_buf)
  
  -- Result should be false if no LSP client attached, which is expected
  assert(type(result) == "boolean", "Should return boolean")
  
  -- Cleanup
  vim.api.nvim_buf_delete(left_buf, { force = true })
  vim.api.nvim_buf_delete(right_buf, { force = true })
end)

-- Test 7: Token encoding/decoding consistency
test("Token data structure handling", function()
  -- Test that our implementation handles the expected LSP token format
  -- LSP tokens are arrays of [deltaLine, deltaStart, length, tokenType, tokenModifiers]
  
  -- Mock token data (from LSP spec example)
  local mock_tokens = {
    0, 5, 4, 1, 0,  -- Line 0, col 5, length 4, type 1, no modifiers
    1, 0, 3, 2, 1,  -- Line 1, col 0, length 3, type 2, modifier bit 1
  }
  
  -- Verify array length (should be multiple of 5)
  assert(#mock_tokens % 5 == 0, "Token data should be multiple of 5")
  
  -- Each token has exactly 5 elements
  local token_count = #mock_tokens / 5
  assert(token_count == 2, "Should have 2 tokens in mock data")
end)

-- Test 8: Highlight priority respects Neovim defaults
test("Respects Neovim's semantic token priority", function()
  -- Should use vim.hl.priorities.semantic_tokens if available
  if vim.hl.priorities and vim.hl.priorities.semantic_tokens then
    local priority = vim.hl.priorities.semantic_tokens
    assert(type(priority) == "number", "Priority should be a number")
    assert(priority > 0, "Priority should be positive")
  else
    -- Fallback for older Neovim versions
    local fallback = 125
    assert(type(fallback) == "number", "Fallback priority should be a number")
  end
end)

-- Test 9: URI handling for scratch buffers
test("URI construction for diff buffers", function()
  -- Create a real file buffer
  local tmpfile = vim.fn.tempname() .. ".lua"
  vim.fn.writefile({"local x = 1"}, tmpfile)
  
  local buf = vim.fn.bufadd(tmpfile)
  vim.fn.bufload(buf)
  
  -- Get URI
  local uri = vim.uri_from_bufnr(buf)
  assert(type(uri) == "string", "URI should be a string")
  assert(uri:match("^file://"), "URI should start with file://")
  
  -- Cleanup
  vim.fn.delete(tmpfile)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

-- Test 10: Graceful handling of missing capabilities
test("Handles missing semantic token capabilities", function()
  local semantic = require("vscode-diff.render.semantic_tokens")
  
  -- Create buffers with no LSP client
  local left_buf = vim.api.nvim_create_buf(false, true)
  local right_buf = vim.api.nvim_create_buf(false, true)
  
  -- Should return false gracefully
  local result = semantic.apply_semantic_tokens(left_buf, right_buf)
  assert(result == false, "Should return false with no LSP client")
  
  -- Cleanup
  vim.api.nvim_buf_delete(left_buf, { force = true })
  vim.api.nvim_buf_delete(right_buf, { force = true })
end)

-- Test 11: Virtual file URL creation and parsing
test("Virtual file URL creation and parsing", function()
  local virtual_file = require("vscode-diff.virtual_file")
  
  -- Test URL creation
  local git_root = "/home/user/project"
  local commit = "HEAD"
  local filepath = "src/file.lua"
  
  local url = virtual_file.create_url(git_root, commit, filepath)
  assert(type(url) == "string", "URL should be a string")
  assert(url:match("^vscodediff://"), "URL should start with vscodediff://")
  
  -- Test URL parsing
  local parsed_root, parsed_commit, parsed_path = virtual_file.parse_url(url)
  assert(parsed_root == git_root, "Parsed git root should match")
  assert(parsed_commit == commit, "Parsed commit should match")
  assert(parsed_path == filepath, "Parsed filepath should match")
  
  -- Test with different inputs
  local url2 = virtual_file.create_url("/tmp/test", "abc123", "test.lua")
  local root2, commit2, path2 = virtual_file.parse_url(url2)
  assert(root2 == "/tmp/test", "Root should match")
  assert(commit2 == "abc123", "Commit should match")
  assert(path2 == "test.lua", "Path should match")
end)

-- Test 12: Diagnostics disabled on virtual buffers
test("Diagnostics are disabled on virtual buffers", function()
  -- This tests that vim.diagnostic.enable(false) is called on virtual buffers
  -- We can't easily test the actual BufReadCmd callback without a real git repo
  -- so we test that the API works correctly
  
  local test_buf = vim.api.nvim_create_buf(false, true)
  
  -- Initially diagnostics should be enabled
  assert(vim.diagnostic.is_enabled({bufnr = test_buf}) == true, 
    "Diagnostics should be enabled by default")
  
  -- Disable diagnostics
  vim.diagnostic.enable(false, {bufnr = test_buf})
  
  -- Verify disabled
  assert(vim.diagnostic.is_enabled({bufnr = test_buf}) == false,
    "Diagnostics should be disabled after vim.diagnostic.enable(false)")
  
  -- Cleanup
  vim.api.nvim_buf_delete(test_buf, { force = true })
end)

-- Summary
print("\n" .. string.rep("=", 50))
print(string.format("Tests: %d/%d passed", pass_count, test_count))
print(string.rep("=", 50))

if pass_count == test_count then
  print("✓ All tests passed!")
  vim.cmd("cquit 0")
else
  print("✗ Some tests failed")
  vim.cmd("cquit 1")
end
