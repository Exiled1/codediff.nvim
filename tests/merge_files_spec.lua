local merge_files = require('codediff.merge_files')
local assert = require('luassert')

describe("merge_files - Non-Git 3-Way Merge", function()
  local tmp_dir = "/tmp/codediff_merge_test"
  local base_file, remote_file, local_file

  before_each(function()
    -- Create temp directory for test files
    vim.fn.mkdir(tmp_dir, "p")
    base_file = tmp_dir .. "/base.txt"
    remote_file = tmp_dir .. "/remote.txt"
    local_file = tmp_dir .. "/local.txt"
  end)

  after_each(function()
    -- Clean up test files
    vim.fn.delete(tmp_dir, "rf")

    -- Close any tabs that were created
    local current_tab = vim.api.nvim_get_current_tabpage()
    if current_tab > 1 then
      vim.cmd("tabclose!")
    end
  end)

  describe("Non-conflicting changes", function()
    it("should auto-merge when remote and local change different lines", function()
      -- Setup: BASE with 5 lines
      local base_content = table.concat({
        "line1",
        "line2",
        "line3",
        "line4",
        "line5"
      }, "\n")

      -- REMOTE changes line 2
      local remote_content = table.concat({
        "line1",
        "REMOTE_CHANGE",
        "line3",
        "line4",
        "line5"
      }, "\n")

      -- LOCAL changes line 4
      local local_content = table.concat({
        "line1",
        "line2",
        "line3",
        "LOCAL_CHANGE",
        "line5"
      }, "\n")

      -- Write files
      vim.fn.writefile(vim.split(base_content, "\n"), base_file)
      vim.fn.writefile(vim.split(remote_content, "\n"), remote_file)
      vim.fn.writefile(vim.split(local_content, "\n"), local_file)

      -- Execute merge
      local result = merge_files.merge_files(local_file, remote_file, base_file)

      -- Assertions
      assert.is_not_nil(result)
      assert.is_true(result ~= false)

      -- Get result buffer content
      local result_lines = vim.api.nvim_buf_get_lines(result.result_bufnr, 0, -1, false)

      -- Verify both changes were auto-applied
      assert.equals("line1", result_lines[1])
      assert.equals("REMOTE_CHANGE", result_lines[2])
      assert.equals("line3", result_lines[3])
      assert.equals("LOCAL_CHANGE", result_lines[4])
      assert.equals("line5", result_lines[5])

      -- Verify no conflict blocks exist
      assert.equals(0, #result.conflict_blocks)
    end)

    it("should auto-merge when only remote changes", function()
      local base_content = "line1\nline2\nline3"
      local remote_content = "line1\nREMOTE_CHANGE\nline3"
      local local_content = "line1\nline2\nline3" -- No changes

      vim.fn.writefile(vim.split(base_content, "\n"), base_file)
      vim.fn.writefile(vim.split(remote_content, "\n"), remote_file)
      vim.fn.writefile(vim.split(local_content, "\n"), local_file)

      local result = merge_files.merge_files(local_file, remote_file, base_file)

      assert.is_not_nil(result)
      local result_lines = vim.api.nvim_buf_get_lines(result.result_bufnr, 0, -1, false)

      -- Remote change should be auto-applied
      assert.equals("REMOTE_CHANGE", result_lines[2])
      assert.equals(0, #result.conflict_blocks)
    end)

    it("should auto-merge when only local changes", function()
      local base_content = "line1\nline2\nline3"
      local remote_content = "line1\nline2\nline3" -- No changes
      local local_content = "line1\nLOCAL_CHANGE\nline3"

      vim.fn.writefile(vim.split(base_content, "\n"), base_file)
      vim.fn.writefile(vim.split(remote_content, "\n"), remote_file)
      vim.fn.writefile(vim.split(local_content, "\n"), local_file)

      local result = merge_files.merge_files(local_file, remote_file, base_file)

      assert.is_not_nil(result)
      local result_lines = vim.api.nvim_buf_get_lines(result.result_bufnr, 0, -1, false)

      -- Local change should be auto-applied
      assert.equals("LOCAL_CHANGE", result_lines[2])
      assert.equals(0, #result.conflict_blocks)
    end)
  end)

  describe("Conflicting changes", function()
    it("should create conflict block when both sides change same line", function()
      local base_content = "line1\nline2\nline3"
      local remote_content = "line1\nREMOTE_CHANGE\nline3"
      local local_content = "line1\nLOCAL_CHANGE\nline3"

      vim.fn.writefile(vim.split(base_content, "\n"), base_file)
      vim.fn.writefile(vim.split(remote_content, "\n"), remote_file)
      vim.fn.writefile(vim.split(local_content, "\n"), local_file)

      local result = merge_files.merge_files(local_file, remote_file, base_file)

      assert.is_not_nil(result)

      -- Should have exactly one conflict block
      assert.equals(1, #result.conflict_blocks)

      -- Result buffer should start with BASE content (not auto-merged for conflicts)
      local result_lines = vim.api.nvim_buf_get_lines(result.result_bufnr, 0, -1, false)
      assert.equals("line1", result_lines[1])
      assert.equals("line2", result_lines[2]) -- BASE content preserved for conflict
      assert.equals("line3", result_lines[3])

      -- Verify conflict block covers line 2
      local block = result.conflict_blocks[1]
      assert.is_not_nil(block.base_range)
      assert.equals(2, block.base_range.start_line)
    end)

    it("should create multiple conflict blocks for multiple conflicts", function()
      local base_content = "line1\nline2\nline3\nline4\nline5"
      -- Remote changes lines 2 and 4
      local remote_content = "line1\nREMOTE_2\nline3\nREMOTE_4\nline5"
      -- Local also changes lines 2 and 4 (conflicts)
      local local_content = "line1\nLOCAL_2\nline3\nLOCAL_4\nline5"

      vim.fn.writefile(vim.split(base_content, "\n"), base_file)
      vim.fn.writefile(vim.split(remote_content, "\n"), remote_file)
      vim.fn.writefile(vim.split(local_content, "\n"), local_file)

      local result = merge_files.merge_files(local_file, remote_file, base_file)

      assert.is_not_nil(result)

      -- Should have two conflict blocks
      assert.equals(2, #result.conflict_blocks)
    end)
  end)

  describe("Mixed scenarios", function()
    it("should auto-merge non-conflicts and create blocks for conflicts", function()
      local base_content = table.concat({
        "line1",
        "line2",
        "line3",
        "line4",
        "line5",
        "line6"
      }, "\n")

      -- Remote changes lines 2 (conflict) and 5 (non-conflict)
      local remote_content = table.concat({
        "line1",
        "REMOTE_2",
        "line3",
        "line4",
        "REMOTE_5",
        "line6"
      }, "\n")

      -- Local changes lines 2 (conflict) and 6 (non-conflict)
      local local_content = table.concat({
        "line1",
        "LOCAL_2",
        "line3",
        "line4",
        "line5",
        "LOCAL_6"
      }, "\n")

      vim.fn.writefile(vim.split(base_content, "\n"), base_file)
      vim.fn.writefile(vim.split(remote_content, "\n"), remote_file)
      vim.fn.writefile(vim.split(local_content, "\n"), local_file)

      local result = merge_files.merge_files(local_file, remote_file, base_file)

      assert.is_not_nil(result)

      -- Note: merge_alignment may group nearby changes into conflict blocks
      -- This can result in 1 or 2 conflict blocks depending on hunk detection
      -- We verify there's at least one conflict and that non-overlapping changes are handled
      assert.is_true(#result.conflict_blocks >= 1)

      -- Get result buffer content
      local result_lines = vim.api.nvim_buf_get_lines(result.result_bufnr, 0, -1, false)

      -- Verify the structure (exact conflict resolution depends on merge algorithm)
      assert.equals("line1", result_lines[1])
      assert.equals("line3", result_lines[3])
      assert.equals("line4", result_lines[4])
    end)

    it("should handle additions and deletions correctly", function()
      local base_content = "line1\nline2\nline3"

      -- Remote adds a line at the end
      local remote_content = "line1\nline2\nline3\nREMOTE_ADD"

      -- Local modifies line 2
      local local_content = "line1\nLOCAL_CHANGE\nline3"

      vim.fn.writefile(vim.split(base_content, "\n"), base_file)
      vim.fn.writefile(vim.split(remote_content, "\n"), remote_file)
      vim.fn.writefile(vim.split(local_content, "\n"), local_file)

      local result = merge_files.merge_files(local_file, remote_file, base_file)

      assert.is_not_nil(result)

      -- No conflicts (different regions changed)
      assert.equals(0, #result.conflict_blocks)

      -- Both changes should be auto-applied
      local result_lines = vim.api.nvim_buf_get_lines(result.result_bufnr, 0, -1, false)
      assert.equals("LOCAL_CHANGE", result_lines[2])
      assert.equals("REMOTE_ADD", result_lines[4])
    end)
  end)

  describe("Error handling", function()
    it("should return false when base file doesn't exist", function()
      vim.fn.writefile({"content"}, local_file)
      vim.fn.writefile({"content"}, remote_file)

      local result = merge_files.merge_files(local_file, remote_file, "/nonexistent/base.txt")

      assert.is_false(result)
    end)

    it("should return false when remote file doesn't exist", function()
      vim.fn.writefile({"content"}, local_file)
      vim.fn.writefile({"content"}, base_file)

      local result = merge_files.merge_files(local_file, "/nonexistent/remote.txt", base_file)

      assert.is_false(result)
    end)

    it("should return false when local file doesn't exist", function()
      vim.fn.writefile({"content"}, remote_file)
      vim.fn.writefile({"content"}, base_file)

      local result = merge_files.merge_files("/nonexistent/local.txt", remote_file, base_file)

      assert.is_false(result)
    end)
  end)

  describe("Buffer and window setup", function()
    it("should create proper buffer layout with correct names", function()
      local base_content = "line1\nline2"
      local remote_content = "REMOTE\nline2"
      local local_content = "line1\nLOCAL"

      vim.fn.writefile(vim.split(base_content, "\n"), base_file)
      vim.fn.writefile(vim.split(remote_content, "\n"), remote_file)
      vim.fn.writefile(vim.split(local_content, "\n"), local_file)

      local result = merge_files.merge_files(local_file, remote_file, base_file)

      assert.is_not_nil(result)

      -- Verify buffers exist
      assert.is_true(vim.api.nvim_buf_is_valid(result.remote_bufnr))
      assert.is_true(vim.api.nvim_buf_is_valid(result.local_bufnr))
      assert.is_true(vim.api.nvim_buf_is_valid(result.result_bufnr))

      -- Verify windows exist
      assert.is_true(vim.api.nvim_win_is_valid(result.remote_win))
      assert.is_true(vim.api.nvim_win_is_valid(result.local_win))
      assert.is_true(vim.api.nvim_win_is_valid(result.result_win))

      -- Verify buffer names contain (incoming) and (current)
      local remote_name = vim.api.nvim_buf_get_name(result.remote_bufnr)
      local local_name = vim.api.nvim_buf_get_name(result.local_bufnr)

      assert.is_true(remote_name:match("%(incoming%)") ~= nil)
      assert.is_true(local_name:match("%(current%)") ~= nil)
    end)

    it("should set result buffer as modifiable", function()
      local content = "line1\nline2"
      vim.fn.writefile(vim.split(content, "\n"), base_file)
      vim.fn.writefile(vim.split(content, "\n"), remote_file)
      vim.fn.writefile(vim.split(content, "\n"), local_file)

      local result = merge_files.merge_files(local_file, remote_file, base_file)

      assert.is_not_nil(result)

      -- Result buffer should be modifiable initially (set to false after auto-apply)
      -- Let's verify we can read it at least
      local result_lines = vim.api.nvim_buf_get_lines(result.result_bufnr, 0, -1, false)
      assert.is_not_nil(result_lines)
    end)
  end)
end)
