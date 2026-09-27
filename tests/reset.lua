-- Usage: nvim --clean --headless -l tests/reset.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
local state = require("terminal.state")
terminal.setup({ keys = false, set_buffer_name = false })
local function settle() vim.wait(160, function() return false end) end
terminal.toggle()
terminal.vsplit()
settle()
local old = vim.api.nvim_get_current_buf()
local original = state.get_current_tab()
local wins = vim.deepcopy(vim.t.term_winids)
local inspect, confirm = vim.api.nvim_get_proc_children, vim.fn.confirm
local confirmations, answer = 0, 2
vim.api.nvim_get_proc_children = function() return { 12345 } end
vim.fn.confirm = function(_, _, default)
	assert(default == 2, "confirmation defaults to keeping the terminal")
	confirmations = confirmations + 1
	return answer
end
terminal.reset()
assert(vim.api.nvim_get_current_buf() == old and confirmations == 1, "reset cancellation leaves the job intact")
terminal.delete()
assert(vim.api.nvim_buf_is_valid(old) and confirmations == 2, "delete uses the same confirmation")
answer = 1
vim.cmd("TermReset")
settle()
local replaced = vim.api.nvim_get_current_buf()
local current = state.get_current_tab()
assert(replaced ~= old and not vim.api.nvim_buf_is_valid(old), "reset replaces the old job")
assert(current.id == original.id and #current.bufs == 2 and #state.get_tabs() == 1, "reset preserves tab identity and pane count")
assert(vim.deep_equal(wins, vim.t.term_winids), "reset reuses the existing pane windows")
assert(current.layout.w == original.layout.w and current.layout.h == original.layout.h, "reset preserves geometry")
assert(confirmations == 3, "TermReset also confirms")
vim.api.nvim_get_proc_children = function() error("unavailable") end
answer = 2
terminal.reset()
assert(vim.api.nvim_get_current_buf() == replaced and confirmations == 4, "inspection failure asks instead of silently killing the job")
vim.api.nvim_get_proc_children = function() return {} end
local termopen = vim.fn.termopen
vim.fn.termopen = function() error("injected startup failure") end
assert(not pcall(terminal.reset), "startup errors are reported")
vim.fn.termopen = termopen
assert(vim.api.nvim_buf_is_valid(replaced) and state.get_current_tab().focus == replaced,
	"failed reset preserves the original job and pane state")
assert(vim.deep_equal(wins, vim.t.term_winids) and #state.get_tabs() == 1, "failed reset does not disturb windows or create a tab")
local native_open = vim.api.nvim_open_win
local buffer_count = #vim.api.nvim_list_bufs()
vim.api.nvim_open_win = function() error("injected startup window failure") end
assert(not pcall(terminal.reset), "startup window errors are reported")
vim.api.nvim_open_win = native_open
assert(#vim.api.nvim_list_bufs() == buffer_count, "failed startup window does not leak replacement buffer")
assert(vim.api.nvim_buf_is_valid(replaced) and state.get_current_tab().focus == replaced,
	"failed startup window keeps the original terminal")
vim.api.nvim_get_proc_children, vim.fn.confirm = inspect, confirm
print("Reset and confirmation regressions passed")
