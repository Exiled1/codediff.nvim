-- Backward compatibility shim
-- Redirects old 'vscode-diff.virtual_file' to new 'codediff.core.virtual_file'
return require('codediff.core.virtual_file')
