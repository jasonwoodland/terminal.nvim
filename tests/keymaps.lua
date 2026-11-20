-- Usage: nvim --clean --headless -l tests/keymaps.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
local terminal = require("terminal")
terminal.setup({ keys = { wincmd = "<F6>" } })
local panes = require("terminal.panes")
local function feed(keys)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end
local count
panes.cycle = function(value) count = value end
feed("<F6>1w")
assert(count == 1, "explicit count one selects the first window")
feed("<F6>w")
assert(count == nil, "omitted count cycles")
panes.set_size = function(_, value) count = value end
feed("<F6>1|")
assert(count == 1, "explicit count one sets width rather than maximizing")
panes.exchange = function(value) count = value end
feed("<F6>1x")
assert(count == 1, "explicit count one exchanges with the first pane")

vim.cmd("vnew")
vim.cmd("vnew")
vim.cmd("wincmd l")
vim.cmd("wincmd l")
feed("2<C-w>h")
assert(vim.fn.winnr() == 1, "native fallback preserves the count outside terminal panes")

for _, float in ipairs({ false, true }) do
	vim.cmd("tabnew")
	local editor = vim.api.nvim_get_current_win()
	local first = terminal.new()
	if float then terminal.float_toggle() end
	local second = terminal.vsplit()
	vim.wait(200, function() return false end)
	local second_win = vim.api.nvim_get_current_win()
	local wins = vim.t.term_winids
	vim.api.nvim_set_current_win(wins[1])
	local first_win = vim.api.nvim_get_current_win()
	-- The editor becomes Vim's previous window, but terminal history must
	-- still return to the other terminal pane.
	vim.api.nvim_set_current_win(editor)
	vim.api.nvim_set_current_win(first_win)
	vim.cmd("stopinsert")
	feed("<F6>p")
	assert(vim.api.nvim_get_current_buf() == second, "prefix p uses terminal history in both display modes")
	vim.api.nvim_set_current_win(editor)
	vim.api.nvim_set_current_win(second_win)
	vim.cmd("stopinsert")
	feed("<C-S-p>")
	assert(vim.api.nvim_get_current_buf() == first, "standalone p uses the same terminal history")
end
print("Keymap regressions passed")
