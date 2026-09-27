-- Usage: nvim --clean --headless -l tests/render.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
local render = require('terminal.float_layout')
local config = require('terminal.config')
config.setup({ float = { enabled = true } })
local tree = { t = 'row', w = 20, h = 5, children = {
	{ t = 'leaf', buf = 1, w = 9, h = 5 }, { t = 'leaf', buf = 2, w = 10, h = 5 },
} }
local base = { row = 1, col = 2, border = 'rounded', title = ' T ' }
local function update() render.update_canvas(tree, base) end
update()
local win = vim.t.term_canvas_winid
local buf = vim.api.nvim_win_get_buf(win)
local function tick() return vim.api.nvim_buf_get_changedtick(buf) end
local function text() return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local original_tick, original_text = tick(), text()
local configure = vim.api.nvim_win_set_config
local calls = 0
vim.api.nvim_win_set_config = function(...) calls = calls + 1; return configure(...) end
update()
tree.children[1].buf, tree.children[2].buf = 3, 4
update()
assert(tick() == original_tick and calls == 0, 'unchanged artwork and geometry do not write buffers or window config')
base.row = 2
update()
assert(tick() == original_tick and calls == 1 and vim.api.nvim_win_get_position(win)[1] == 2,
	'reposition changes only the window')
vim.api.nvim_win_set_config = configure

tree.children[1].w, tree.children[2].w = 7, 12
update()
assert(tick() > original_tick and not vim.deep_equal(text(), original_text), 'separator geometry invalidates artwork')
base.border = { '+', '-', '+', '|', '+', '-', '+', '|' }
update()
local border_text = text()
base.border[1] = '*'
update()
assert(text()[1]:sub(1, 1) == '*' and not vim.deep_equal(text(), border_text), 'in-place border changes invalidate artwork')
vim.opt.fillchars:append({ vert = '!' })
update()
assert(table.concat(text()):find('!', 1, true), 'fillchars invalidates artwork')
base.title = ' New '
update()
assert(text()[1]:find(' New ', 1, true), 'title invalidates artwork')
local expected = text()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'external change' })
update()
assert(vim.deep_equal(text(), expected), 'external buffer changes invalidate artwork')
vim.api.nvim_buf_delete(buf, { force = true })
update()
buf = vim.api.nvim_win_get_buf(vim.t.term_canvas_winid)
assert(vim.deep_equal(text(), expected), 'recreated buffer receives complete artwork')
render.close_canvas()
print('Canvas rendering regressions passed')
