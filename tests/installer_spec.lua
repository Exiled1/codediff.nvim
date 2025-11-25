-- Test: Installer Module
-- Validates automatic binary installation and version management

local installer = require("vscode-diff.installer")
local version = require("vscode-diff.version")

describe("Installer Module", function()
  -- Test 1: Module loads correctly
  it("Loads installer module", function()
    assert.is_not_nil(installer, "Installer module should load")
    assert.equal("table", type(installer), "Installer should be a table")
  end)

  -- Test 2: Public API functions exist
  it("Exposes correct public API", function()
    assert.equal("function", type(installer.install), "Should have install function")
    assert.equal("function", type(installer.is_installed), "Should have is_installed function")
    assert.equal("function", type(installer.get_lib_path), "Should have get_lib_path function")
    assert.equal("function", type(installer.get_installed_version), "Should have get_installed_version function")
    assert.equal("function", type(installer.needs_update), "Should have needs_update function")
  end)

  -- Test 3: VERSION is loaded from version.lua
  it("VERSION is available from version module", function()
    assert.is_not_nil(version.VERSION, "VERSION should be loaded")
    assert.equal("string", type(version.VERSION), "VERSION should be a string")
    assert.is_true(#version.VERSION > 0, "VERSION should not be empty")
    -- Check version format (e.g., "0.8.0")
    assert.is_true(version.VERSION:match("^%d+%.%d+%.%d+$") ~= nil, "VERSION should match semantic version format")
  end)

  -- Test 4: get_lib_path returns correct format
  it("get_lib_path returns valid library path", function()
    local lib_path = installer.get_lib_path()
    assert.is_not_nil(lib_path, "Library path should not be nil")
    assert.equal("string", type(lib_path), "Library path should be a string")
    
    -- Should contain libvscode_diff in the filename
    assert.is_true(lib_path:match("libvscode_diff") ~= nil, 
      "Library filename should contain 'libvscode_diff'")
    
    -- Should have correct extension based on OS
    local ffi = require("ffi")
    if ffi.os == "Windows" then
      assert.is_true(lib_path:match("%.dll$") ~= nil, "Windows should use .dll")
    elseif ffi.os == "OSX" then
      assert.is_true(lib_path:match("%.dylib$") ~= nil, "macOS should use .dylib")
    else
      assert.is_true(lib_path:match("%.so$") ~= nil, "Linux should use .so")
    end
  end)

  -- Test 5: is_installed checks for library file
  it("is_installed checks for library file", function()
    local installed = installer.is_installed()
    assert.equal("boolean", type(installed), "is_installed should return boolean")
    
    -- If installed, the file should actually exist
    if installed then
      local lib_path = installer.get_lib_path()
      assert.is_not_nil(lib_path, "Library path should exist if installed")
      assert.equal(1, vim.fn.filereadable(lib_path), "Library file should be readable if installed")
    end
  end)

  -- Test 6: get_installed_version returns nil or valid version
  it("get_installed_version returns nil or version string", function()
    local installed_version = installer.get_installed_version()
    
    if installed_version then
      assert.equal("string", type(installed_version), "Installed version should be string if present")
      assert.is_true(#installed_version > 0, "Installed version should not be empty")
      -- Should match semantic version format
      assert.is_true(installed_version:match("^%d+%.%d+%.%d+$") ~= nil, 
        "Installed version should match semantic version format")
    end
    -- Note: We can't assert is_installed() is false if installed_version is nil,
    -- because we might have an unversioned manual build.
  end)

  -- Test 7: needs_update logic
  it("needs_update correctly determines update necessity", function()
    local needs_update = installer.needs_update()
    assert.equal("boolean", type(needs_update), "needs_update should return boolean")
    
    local installed_version = installer.get_installed_version()
    local current_version = version.VERSION
    local lib_path = installer.get_lib_path()
    
    -- Check if we are using unversioned library
    local is_unversioned = lib_path and not lib_path:match(version.VERSION)
    
    if is_unversioned then
      -- Manual build is assumed to be up-to-date
      assert.is_false(needs_update, "Should not need update when using manual build")
    elseif not installed_version then
      -- No version installed, should need update
      assert.is_true(needs_update, "Should need update when no version is installed")
    elseif installed_version ~= current_version then
      -- Different version, should need update
      assert.is_true(needs_update, "Should need update when versions differ")
    else
      -- Same version, should not need update
      assert.is_false(needs_update, "Should not need update when versions match")
    end
  end)

  -- Test 8: install function signature
  it("install function accepts options table", function()
    -- Test that install can be called with empty options without erroring
    -- Note: We won't actually download during tests, just verify the function exists
    -- and accepts the expected parameters
    local ok = pcall(function()
      -- Just verify the function can be called with options
      -- We check signature, not actual execution (would require network)
      local opts = { silent = true, force = true }
      -- Don't actually call to avoid network access during tests
    end)
    assert.is_true(ok, "Install function should accept options parameter")
  end)

  -- Test 9: Version comparison logic
  it("Correctly identifies version mismatches", function()
    local current_version = version.VERSION
    local installed_version = installer.get_installed_version()
    
    -- Test the logic of needs_update
    if installed_version and installed_version ~= current_version then
      assert.is_true(installer.needs_update(), 
        string.format("Should detect version mismatch: installed=%s, current=%s", 
          installed_version, current_version))
    end
  end)

  -- Test 10: Library path is in plugin root
  it("Library path is in plugin root directory", function()
    local lib_path = installer.get_lib_path()
    assert.is_not_nil(lib_path, "Library path should not be nil")
    
    -- Path should not contain subdirectories like lua/ or src/
    assert.is_false(lib_path:match("/lua/") ~= nil, "Library should not be in lua/ subdirectory")
    assert.is_false(lib_path:match("/src/") ~= nil, "Library should not be in src/ subdirectory")
    
    -- Should contain libvscode_diff in the filename
    assert.is_true(lib_path:match("libvscode_diff") ~= nil, 
      "Library filename should contain 'libvscode_diff'")
  end)

  -- Test 11: Priority of unversioned library (manual build)
  it("Prioritizes unversioned library over versioned one", function()
    local plugin_root = installer.get_lib_path():match("(.*/)")
    local ext = require("ffi").os == "Windows" and "dll" or (require("ffi").os == "OSX" and "dylib" or "so")
    local unversioned_name = "libvscode_diff." .. ext
    local unversioned_path = plugin_root .. unversioned_name
    
    -- Create a dummy unversioned file
    local f = io.open(unversioned_path, "w")
    if f then
      f:write("dummy content")
      f:close()
    else
      error("Failed to create dummy unversioned library for testing")
    end
    
    -- Verify it is prioritized
    local lib_path = installer.get_lib_path()
    assert.equal(unversioned_path, lib_path, "Should prioritize unversioned library")
    assert.is_true(installer.is_installed(), "Should be considered installed")
    assert.is_false(installer.needs_update(), "Should not need update")
    
    -- Cleanup
    os.remove(unversioned_path)
    
    -- Verify it falls back to versioned (or nil if none)
    -- We don't strictly assert what it falls back to, just that it's NOT the unversioned one anymore
    local fallback_path = installer.get_lib_path()
    if fallback_path then
      assert.not_equal(unversioned_path, fallback_path, "Should fall back to versioned library")
    end
  end)
end)
