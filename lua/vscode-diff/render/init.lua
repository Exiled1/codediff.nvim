-- Render module facade
-- Provides backward compatibility and unified exports
local M = {}

local highlights = require('vscode-diff.render.highlights')
local view = require('vscode-diff.render.view')
local core = require('vscode-diff.render.core')
local lifecycle = require('vscode-diff.render.lifecycle')

-- Re-export main functions for backward compatibility
M.setup_highlights = highlights.setup
M.create_diff_view = view.create
M.render_diff = core.render_diff

-- Export buffer type enum
M.BufferType = view.BufferType

-- Export lifecycle functions
M.cleanup = lifecycle.cleanup
M.cleanup_all = lifecycle.cleanup_all

-- Namespace access (for backward compatibility)
M.ns_highlight = highlights.ns_highlight
M.ns_filler = highlights.ns_filler

-- Initialize lifecycle management
lifecycle.setup()

return M
