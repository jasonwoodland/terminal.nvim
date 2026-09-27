-- Usage: nvim --clean --headless -l tests/switching.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
local window = require("terminal.window")
terminal.setup({ keys = false, set_buffer_name = false })
local function settle() vim.wait(150, function() return false end) end
terminal.toggle()
settle()
terminal.vsplit()
settle()
vim.api.nvim_win_set_width(vim.t.term_winids[1], 15)
local first_width = vim.api.nvim_win_get_width(vim.t.term_winids[1])
terminal.new()
settle()
terminal.vsplit()
settle()
vim.api.nvim_win_set_width(vim.t.term_winids[1], 40)
local second_width = vim.api.nvim_win_get_width(vim.t.term_winids[1])
terminal.go_to(1)
settle()
assert(vim.api.nvim_win_get_width(vim.t.term_winids[1]) == first_width,
	"switching to the same shape restores its saved sizes")
terminal.go_to(2)
settle()
assert(vim.api.nvim_win_get_width(vim.t.term_winids[1]) == second_width,
	"round trip preserves the second tab's sizes")
terminal.toggle()
settle()
terminal.toggle()
settle()
assert(vim.api.nvim_win_get_width(vim.t.term_winids[1]) == second_width,
	"toggle preserves pane sizes")

-- Matching geometry still uses the existing windows.
local state = require("terminal.state")
local frame = require("terminal.frame")
window.save_tab_state()
local order = state.get_term_order()
frame.set_leaf_sizes(order[1].layout, vim.tbl_map(function(win)
	return { w = vim.api.nvim_win_get_width(win), h = vim.api.nvim_win_get_height(win) }
end, vim.t.term_winids))
vim.t.term_order = order
local wins = vim.t.term_winids
terminal.go_to(1)
settle()
assert(vim.deep_equal(wins, vim.t.term_winids), "matching geometry reuses pane windows")
print("Switching regressions passed")
