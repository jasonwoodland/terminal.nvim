-- Usage: nvim --clean --headless -l tests/cwd.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
terminal.setup({ keys = false })
local root = vim.fn.tempname()
local first, second = root .. "/first", root .. "/second project"
vim.fn.mkdir(first, "p")
vim.fn.mkdir(second, "p")
local source = terminal.new({ cwd = first })
local ready = root .. "/ready"
terminal.send("cd " .. vim.fn.shellescape(second) .. "; touch " .. vim.fn.shellescape(ready) .. "\n")
assert(vim.wait(3000, function() return vim.fn.filereadable(ready) == 1 end, 10), "plain cd completed")
assert(vim.b[source].terminal_cwd == nil, "plain shell emits no OSC 7 report")
local plain_split = terminal.vsplit()
assert(vim.b[plain_split].terminal_launch.cwd == vim.uv.fs_realpath(second),
	"split inherits shell cwd without OSC 7")
terminal.focus(source)
local plain_tab = terminal.new()
assert(vim.b[plain_tab].terminal_launch.cwd == vim.uv.fs_realpath(second),
	"new terminal tab inherits shell cwd without OSC 7")
terminal.focus(source)
local function request(uri)
	vim.api.nvim_exec_autocmds("TermRequest", {
		buffer = source, data = { sequence = "\27]7;" .. uri },
	})
end
request("file://remote.invalid" .. second)
assert(vim.b[source].terminal_cwd == nil, "remote reports are ignored")
-- Exercise actual PTY output and Neovim's TermRequest delivery.
terminal.send("cd " .. vim.fn.shellescape(second) .. "; printf '\\033]7;file://%s\\007' \"$PWD\"\n")
assert(vim.wait(3000, function() return vim.b[source].terminal_cwd == second end, 10),
	"OSC 7 tracks shell cd through actual terminal output")
local child = terminal.vsplit()
assert(vim.b[child].terminal_launch.cwd == vim.uv.fs_realpath(second), "split inherits current cwd")
terminal.focus(source)
local tab = terminal.new()
assert(vim.b[tab].terminal_launch.cwd == vim.uv.fs_realpath(second), "new terminal tab inherits current cwd")
terminal.focus(source)
local explicit = terminal.new({ cwd = first })
assert(vim.fn.fnamemodify(vim.b[explicit].terminal_launch.cwd, ":h") == first,
	"explicit cwd overrides shell report")
terminal.focus(source)
request("file://localhost" .. second:gsub(" ", "%%20"))
assert(vim.b[source].terminal_cwd == second, "URI escapes are decoded")
request("file://localhost" .. first .. "%00")
assert(vim.b[source].terminal_cwd == second, "invalid reports preserve last usable directory")
vim.fn.delete(second, "d")
assert(require("terminal.cwd").resolve():gsub("/$", "") == first,
	"deleted reported directory falls back to launch directory")
vim.cmd("tabnew")
vim.wait(200, function() return false end)
vim.cmd("lcd " .. vim.fn.fnameescape(root))
local editor = terminal.new()
assert(vim.b[editor].terminal_launch.cwd == vim.uv.fs_realpath(root), "new Vim tab uses editor cwd")
vim.fn.delete(root, "rf")
print("Terminal cwd regressions passed")
