-- Usage: nvim --clean --headless -l tests/launch.lua (requires python3)
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
vim.env.TERMINAL_TEST_PARENT = "inherited"
local terminal = require("terminal")
local state = require("terminal.state")
terminal.setup({ keys = false, set_buffer_name = false })
local root = vim.fn.tempname()
local first_dir, second_dir = root .. "/first project", root .. "/second project"
vim.fn.mkdir(first_dir, "p")
vim.fn.mkdir(second_dir, "p")
local program = [[
import json, os, sys
with open(os.environ["TERMINAL_TEST_REPORT"], "w") as f:
    json.dump({"cwd": os.getcwd(), "value": os.environ["TERMINAL_TEST_VALUE"],
               "parent": os.environ["TERMINAL_TEST_PARENT"], "args": sys.argv[1:]}, f)
sys.stdin.readline()
]]
local function report(path)
	local result
	assert(vim.wait(3000, function()
		if vim.fn.filereadable(path) == 0 then return false end
		local ok, value = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
		if ok then result = value; return true end
	end, 10), "launch report is written")
	return result
end
local function opts(path, dir, name)
	return {
		cmd = { "python3", "-c", program, "literal $HOME; $(not-a-command)", "" },
		cwd = dir, name = name,
		env = { TERMINAL_TEST_REPORT = path, TERMINAL_TEST_VALUE = "configured" },
	}
end
local function settle() vim.wait(150, function() return false end) end
terminal.toggle()
settle()
local shell = vim.api.nvim_get_current_buf()
local defaults = vim.b[shell].terminal_launch
assert(defaults.cmd == "/bin/sh" and next(defaults.env) == nil, "toggle keeps default shell settings")

local path = root .. "/first.json"
local settings = opts(path, first_dir, " Service ")
local buf = terminal.new(settings)
local output = report(path)
assert(buf == vim.api.nvim_get_current_buf() and state.is_managed(buf), "new returns its managed terminal buffer")
assert(output.cwd == vim.uv.fs_realpath(first_dir) and output.value == "configured" and output.parent == "inherited",
	"launch applies cwd and environment overrides while inheriting parent environment")
assert(vim.deep_equal(output.args, { "literal $HOME; $(not-a-command)", "" }), "argument-list commands preserve literal and empty arguments")
assert(vim.env.TERMINAL_TEST_VALUE == nil, "launch environment does not modify Neovim's environment")
assert(state.get_title(buf) == "Service", "launch name appears in terminal metadata")
settings.cmd[3], settings.env.TERMINAL_TEST_VALUE = "invalid program", "mutated"
assert(terminal.rename("Renamed service", buf))
vim.cmd("lcd " .. vim.fn.fnameescape(second_dir))
vim.fn.delete(path)
local reset = terminal.reset()
output = report(path)
assert(reset ~= buf and output.cwd == vim.uv.fs_realpath(first_dir) and output.value == "configured",
	"reset reuses captured launch settings rather than current cwd or mutated caller options")
assert(state.get_title(reset) == "Renamed service", "reset retains a subsequent custom name")

local worker_path = root .. "/worker.json"
local worker = terminal.vsplit(opts(worker_path, second_dir, "Worker"))
assert(report(worker_path).cwd == vim.uv.fs_realpath(second_dir) and #state.get_current_tab().bufs == 2,
	"split accepts independent launch options")
assert(state.get_title(worker) == "Worker", "split applies its own name")
vim.cmd("lcd " .. vim.fn.fnameescape(first_dir))
local plain = terminal.hsplit()
local plain_settings = vim.b[plain].terminal_launch
assert(plain_settings.cmd == "/bin/sh" and next(plain_settings.env) == nil and not vim.b[plain].terminal_custom_name,
	"default split does not inherit a sibling command, environment or name")
local plain_cwd = root .. "/plain-cwd.txt"
terminal.send("pwd > " .. vim.fn.shellescape(plain_cwd) .. "\n")
assert(vim.wait(3000, function() return vim.fn.filereadable(plain_cwd) == 1 end, 10), "default shell reports its cwd")
assert(vim.fn.readfile(plain_cwd)[1] == vim.uv.fs_realpath(second_dir),
	"default split inherits the source pane's launch cwd without a shell report")
terminal.delete()
settle()

local before = state.get_current_tab()
local wins, bufs = vim.deepcopy(vim.t.term_winids), vim.api.nvim_list_bufs()
local previous = vim.t.term_prev_tab_id
for _, invalid in ipairs({ false, { cmd = false }, { cmd = "" }, { cmd = {} }, { cmd = { "sh", 1 } },
	{ cwd = root .. "/missing" }, { env = { BAD = 1 } }, { env = { ["BAD=KEY"] = "x" } },
	{ name = "bad\nname" }, { unknown = true } }) do
	assert(not pcall(terminal.new, invalid), "invalid launch options fail")
	assert(vim.deep_equal(wins, vim.t.term_winids) and vim.deep_equal(bufs, vim.api.nvim_list_bufs()),
		"invalid options leave the workspace untouched")
end
local native = vim.fn.termopen
vim.fn.termopen = function() error("injected launch failure") end
for _, action in ipairs({ terminal.new, terminal.vsplit }) do
	assert(not pcall(action), "startup failures are reported")
	assert(vim.deep_equal(state.get_current_tab(), before) and vim.deep_equal(vim.t.term_winids, wins)
		and vim.deep_equal(vim.api.nvim_list_bufs(), bufs) and vim.t.term_prev_tab_id == previous,
		"failed launch preserves layout, windows, buffers and tab history")
end
vim.fn.termopen = native
assert(not pcall(terminal.new, { cmd = { root .. "/not-executable" } }), "missing executables are rejected")
assert(vim.deep_equal(state.get_current_tab(), before) and vim.deep_equal(vim.t.term_winids, wins),
	"missing executables do not replace the current workspace")

-- String commands and command wrappers use the shell; an empty workspace
-- still honors launch options passed to split().
vim.cmd("tabnew")
settle()
local from_split = terminal.split("col", opts(root .. "/empty.json", second_dir, "First pane"))
assert(report(root .. "/empty.json").value == "configured" and state.get_current_tab().bufs[1] == from_split,
	"split on an empty workspace honors launch options")
local shell_path = root .. "/shell.txt"
vim.cmd("TermNew printf 'shell command works' > " .. vim.fn.shellescape(shell_path) .. "; read ignored")
assert(vim.wait(3000, function() return vim.fn.filereadable(shell_path) == 1 end, 10), "TermNew executes shell command")
assert(table.concat(vim.fn.readfile(shell_path)) == "shell command works", "string command uses shell syntax")
vim.cmd("TermVsplit /bin/sh")
assert(vim.b.terminal_launch.cmd == "/bin/sh" and #state.get_current_tab().bufs == 2,
	"TermVsplit accepts a command")
vim.cmd("TermSplit /bin/sh")
assert(#state.get_current_tab().bufs == 3, "TermSplit accepts a command")
vim.fn.delete(root, "rf")
print("Terminal launch option regressions passed")
