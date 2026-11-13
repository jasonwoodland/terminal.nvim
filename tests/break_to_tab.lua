-- Usage: nvim --clean --headless -l tests/break_to_tab.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
local state = require("terminal.state")
terminal.setup({ keys = { wincmd = "<F6>" }, set_buffer_name = false })
local function settle() vim.wait(160, function() return false end) end
local function feed(keys)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
	settle()
end

for _, floating in ipairs({ false, true }) do
	vim.cmd("tabnew")
	terminal.toggle()
	settle()
	if floating then terminal.float_toggle(); settle() end
	-- Keep another tab after the source to verify insertion rather than append.
	local source = state.get_current_tab().id
	terminal.new()
	settle()
	local following = state.get_current_tab().id
	terminal.go_to(1)
	settle()
	for _, keys in ipairs({ "<F6>T", "<C-w>T" }) do
		terminal.vsplit()
		settle()
		local bufnr = vim.api.nvim_get_current_buf()
		feed(keys)
		local tabs = state.get_tabs()
		assert(#tabs == 3 and tabs[1].id == source and tabs[3].id == following,
			"break inserts a tab immediately after the source")
		assert(#tabs[1].bufs == 1 and #tabs[2].bufs == 1 and tabs[2].bufs[1] == bufnr,
			"break moves only the selected pane")
		assert(state.get_current_tab().id == tabs[2].id and vim.api.nvim_get_current_buf() == bufnr,
			"break focuses the moved pane")
		feed(keys)
		assert(#state.get_tabs() == 3 and vim.api.nvim_get_current_buf() == bufnr,
			"breaking a single-pane tab does nothing")
		terminal.delete()
		settle()
		terminal.go_to(1)
		settle()
	end
end
print("Break-to-tab regressions passed")
