-- Test explorer staging/unstaging workflow with highlights
-- This tests buffer management during file switching in explorer mode

describe("Explorer Buffer Management", function()
  local test_dir
  local test_file
  local test_file_rel = "test.txt"
  local original_content = "line 1\nline 2\nline 3\n"
  
  before_each(function()
    -- Create a temp git repo
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
    
    -- Initialize git repo
    vim.fn.system("cd " .. test_dir .. " && git init")
    vim.fn.system("cd " .. test_dir .. " && git config user.email 'test@test.com'")
    vim.fn.system("cd " .. test_dir .. " && git config user.name 'Test'")
    
    -- Create initial file and commit
    test_file = test_dir .. "/" .. test_file_rel
    vim.fn.writefile(vim.split(original_content, "\n", { plain = true }), test_file)
    vim.fn.system("cd " .. test_dir .. " && git add test.txt && git commit -m 'initial'")
  end)
  
  after_each(function()
    -- Cleanup
    if test_dir then
      vim.fn.delete(test_dir, "rf")
    end
  end)
  
  -- Helper to count orphan buffers
  local function count_orphan_buffers()
    local count = 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
        local name = vim.api.nvim_buf_get_name(buf)
        if name == "" then
          count = count + 1
        end
      end
    end
    return count
  end
  
  it("should parse virtual file URLs correctly", function()
    local virtual_file = require('vscode-diff.virtual_file')
    
    -- Test HEAD revision
    local url1 = virtual_file.create_url("/tmp/test", "HEAD", "file.txt")
    local g1, c1, f1 = virtual_file.parse_url(url1)
    assert.equals("/tmp/test", g1)
    assert.equals("HEAD", c1)
    assert.equals("file.txt", f1)
    
    -- Test :0 (staged) revision
    local url2 = virtual_file.create_url("/tmp/test", ":0", "file.txt")
    local g2, c2, f2 = virtual_file.parse_url(url2)
    assert.equals("/tmp/test", g2)
    assert.equals(":0", c2)
    assert.equals("file.txt", f2)
    
    -- Test SHA hash
    local url3 = virtual_file.create_url("/tmp/test", "abc123def456", "file.txt")
    local g3, c3, f3 = virtual_file.parse_url(url3)
    assert.equals("/tmp/test", g3)
    assert.equals("abc123def456", c3)
    assert.equals("file.txt", f3)
  end)
  
  it("should not leave orphan buffers after creating and closing diff view", function()
    -- Make changes to create staged state
    vim.fn.writefile(vim.split("line 1\nline 2\nline 3\nchange A\n", "\n", { plain = true }), test_file)
    vim.fn.system("cd " .. test_dir .. " && git add test.txt")
    
    -- Count orphan buffers before
    local orphans_before = count_orphan_buffers()
    
    local view = require('vscode-diff.render.view')
    local lifecycle = require('vscode-diff.render.lifecycle')
    
    -- Create view for staged changes (index vs working)
    local session_config = {
      mode = "standalone",
      git_root = test_dir,
      original_path = test_file_rel,
      modified_path = test_file,
      original_revision = ":0",
      modified_revision = "WORKING",
    }
    
    local result = view.create(session_config, "text")
    assert.is_not_nil(result, "Should create diff view")
    
    local tabpage = vim.api.nvim_get_current_tabpage()
    
    -- Wait for async virtual file load
    vim.wait(2000, function()
      local session = lifecycle.get_session(tabpage)
      return session and session.diff_result ~= nil
    end, 100)
    
    -- Close the diff
    lifecycle.cleanup(tabpage)
    
    -- Count orphan buffers after
    local orphans_after = count_orphan_buffers()
    
    -- Should not have created orphan buffers
    assert.equals(orphans_before, orphans_after, 
      "Should not create orphan buffers. Before: " .. orphans_before .. ", After: " .. orphans_after)
  end)
end)
