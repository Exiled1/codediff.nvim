-- Backward compatibility shim
-- Redirects old 'vscode-diff.diff' to new 'codediff.core.diff'
return require('codediff.core.diff')
