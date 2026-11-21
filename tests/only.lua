-- Usage: nvim --clean --headless -l tests/only.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
local state = require("terminal.state")
terminal.setup({ keys = { wincmd = "<F6>" }, set_buffer_name = false })
local function settle() vim.wait(160, function() return false end) end
local function feed(keys)
	vim.cmd("stopinsert")
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end
local confirm = vim.fn.confirm
local answer, prompts, message = 2, 0, nil
vim.fn.confirm = function(text, _, default)
	message, prompts = text, prompts + 1
	assert(default == 2, "confirmation defaults to No")
	return answer
end
for _, float in ipairs({ false, true }) do
	vim.cmd("tabnew")
	local editor = vim.api.nvim_get_current_win()
	local other = terminal.new()
	local keep = terminal.new({ cmd = { "sleep", "60" } })
	if float then terminal.float_toggle() end
	local idle = terminal.vsplit()
	local busy = terminal.hsplit({ cmd = { "sleep", "60" } })
	terminal.vsplit({ cmd = { "sleep", "60" } })
	terminal.focus(keep)
	settle()
	local original, wins = state.get_term_order(), vim.deepcopy(vim.t.term_winids)
	local prior = prompts
	feed("<F6>o")
	assert(prompts == prior + 1 and message == "2 of 3 other terminal panes have running processes. Close anyway?",
		"prompt counts busy siblings only, excluding the retained busy pane")
	assert(vim.deep_equal(original, state.get_term_order()) and vim.deep_equal(wins, vim.t.term_winids),
		"decline preserves all panes, layout, and windows, including idle siblings")
	answer = 1
	feed("<C-w>o")
	settle()
	assert(prompts == prior + 2, "native prefix uses the same single confirmation")
	assert(#state.get_tabs() == 2 and #state.get_current_tab().bufs == 1,
		"only removes siblings in the selected terminal tab")
	assert(vim.api.nvim_get_current_buf() == keep and vim.api.nvim_buf_is_valid(other)
		and not vim.api.nvim_buf_is_valid(idle) and not vim.api.nvim_buf_is_valid(busy),
		"retained pane, other tab, and editor survive")
	assert(vim.api.nvim_win_is_valid(editor), "editor windows are kept")
	assert(terminal.only() and prompts == prior + 2, "one pane is a silent no-op even when busy")
	-- Idle siblings close silently; an inspection failure must still prompt.
	terminal.vsplit()
	terminal.focus(keep)
	settle()
	local inspect = vim.api.nvim_get_proc_children
	vim.api.nvim_get_proc_children = function() error("unavailable") end
	answer = 2
	assert(not terminal.only() and message == "Could not check 1 other terminal pane for a running process. Close anyway?",
		"inspection failure confirms and cancels without deletion")
	vim.api.nvim_get_proc_children = inspect
	local count = prompts
	assert(terminal.only() and prompts == count, "idle sibling closes without confirmation")
	answer = 2
end
vim.fn.confirm = confirm
print("Terminal only-pane regressions passed")
