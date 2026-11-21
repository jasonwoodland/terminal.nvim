-- Usage: nvim --clean --headless -l tests/term_tab_close.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
local state = require("terminal.state")
terminal.setup({ keys = false, set_buffer_name = false })
local function settle() vim.wait(160, function() return false end) end
local editor = vim.api.nvim_get_current_win()
assert(not terminal.close_tab(), "empty workspace returns a failure")
local survivor = terminal.new()
local first = terminal.new()
local busy = terminal.vsplit()
terminal.send("sleep 60\n")
local pid = vim.fn.jobpid(vim.b[busy].terminal_job_id)
assert(vim.wait(3000, function() return #vim.api.nvim_get_proc_children(pid) > 0 end, 10),
	"background pane has a running command")
terminal.focus(first)
settle()
local before, wins = state.get_term_order(), vim.deepcopy(vim.t.term_winids)
local confirm, inspect = vim.fn.confirm, vim.api.nvim_get_proc_children
local prompts, answer = 0, 2
vim.fn.confirm = function(_, _, default)
	prompts = prompts + 1
	assert(default == 2, "confirmation defaults to No")
	return answer
end
local ok = terminal.close_tab()
assert(not ok and prompts == 1, "busy nonfocused pane triggers confirmation")
assert(vim.deep_equal(state.get_term_order(), before) and vim.deep_equal(vim.t.term_winids, wins),
	"cancellation preserves all panes and windows")
assert(vim.api.nvim_buf_is_valid(first) and vim.api.nvim_buf_is_valid(busy), "cancel deletes no buffers")
answer = 1
vim.cmd("TermTabClose")
settle()
assert(prompts == 2 and not vim.api.nvim_buf_is_valid(first) and not vim.api.nvim_buf_is_valid(busy),
	"confirmed command closes every pane with one prompt")
assert(#state.get_tabs() == 1 and vim.api.nvim_get_current_buf() == survivor,
	"other terminal tabs survive and become selected")
vim.api.nvim_get_proc_children = function() error("inspection unavailable") end
answer = 2
assert(not terminal.close_tab() and prompts == 3 and vim.api.nvim_buf_is_valid(survivor),
	"inspection failure also confirms and can cancel")
vim.api.nvim_get_proc_children = inspect
terminal.toggle({ open = false })
settle()
assert(terminal.close_tab(), "hidden idle tab closes without a prompt")
assert(prompts == 3 and #state.get_tabs() == 0 and not state.is_term_open(), "last tab closes cleanly")
assert(vim.api.nvim_get_current_win() == editor, "editor focus is preserved")
local last = terminal.new()
settle()
vim.api.nvim_set_current_win(editor)
assert(terminal.close_tab() and not vim.api.nvim_buf_is_valid(last), "command works from an editor window")
assert(vim.api.nvim_get_current_win() == editor and #state.get_tabs() == 0, "open last tab restores editor")
local program = terminal.new({ cmd = { "sleep", "60" } })
answer = 2
assert(not terminal.close_tab() and prompts == 4 and vim.api.nvim_buf_is_valid(program),
	"direct programs without children also require confirmation")
answer = 1
assert(terminal.close_tab() and prompts == 5 and not vim.api.nvim_buf_is_valid(program),
	"direct program closes after confirmation")
vim.fn.confirm = confirm
print("Terminal tab close regressions passed")
