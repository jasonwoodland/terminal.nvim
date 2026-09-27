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
print("Keymap regressions passed")
