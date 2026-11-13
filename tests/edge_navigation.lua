-- Usage: nvim --clean --headless -l tests/edge_navigation.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
terminal.setup({ keys = { wincmd = "<F6>" }, set_buffer_name = false })
local function settle() vim.wait(160, function() return false end) end
local function feed(keys)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
	settle()
end
for _, floating in ipairs({ false, true }) do
	vim.cmd("tabnew")
	local editor = vim.api.nvim_get_current_win()
	terminal.toggle()
	settle()
	if floating then terminal.float_toggle(); settle() end
	terminal.vsplit()
	settle()
	terminal.hsplit()
	settle()
	local wins = vim.t.term_winids
	local first = floating and wins[1] or editor
	local last = wins[#wins]
	for _, prefix in ipairs({ "<F6>", "<C-w>" }) do
		vim.api.nvim_set_current_win(wins[2])
		feed(prefix .. "t")
		assert(vim.api.nvim_get_current_win() == first, "t focuses top-left window")
		vim.api.nvim_set_current_win(wins[2])
		feed(prefix .. "b")
		assert(vim.api.nvim_get_current_win() == last, "b focuses bottom-right window")
	end
	-- The custom prefix also navigates back from an editor window in drawers.
	feed("<F6>t")
	feed("<F6>b")
	assert(vim.api.nvim_get_current_win() == last, "b returns from top-left window")
end
print("Edge navigation regressions passed")
