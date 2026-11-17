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

local nested = { t = 'row', w = 20, h = 9, children = {
	{ t = 'leaf', buf = 1, w = 9, h = 9 },
	{ t = 'col', w = 10, h = 9, children = {
		{ t = 'leaf', buf = 2, w = 10, h = 4 }, { t = 'leaf', buf = 3, w = 10, h = 4 },
	} },
} }
local plain = {row=0, col=0, border='none'}
local function divider()
	local canvas = vim.api.nvim_win_get_buf(vim.t.term_canvas_winid)
	local line = vim.api.nvim_buf_get_lines(canvas, 4, 5, false)[1]
	return vim.fn.strcharpart(line, 9, 1)
end
-- Restore fillchars modified above so the expected divider is unambiguous.
vim.opt.fillchars:append({vert='│'})
render.update_canvas(nested, plain)
assert(divider() == '├', 'plain floats join a visible horizontal separator')
vim.t.term_zoom = true
render.update_canvas(nested, plain)
assert(divider() == '│', 'zoom statuslines do not create horizontal junction arms')
vim.t.term_zoom = nil
render.update_canvas(nested, plain)
assert(divider() == '├', 'leaving zoom restores separator junctions with identical geometry')
render.close_canvas()
print('Canvas rendering regressions passed')

-- A stacked left column beside a full-height right pane: the upper
-- statusline must leave the vertical canvas divider uncovered.
local statusline = require('terminal.statusline')
local pane_buf = vim.api.nvim_create_buf(false, true)
local function pane(row, col, width, height)
	return vim.api.nvim_open_win(pane_buf, false, {
		relative='editor', row=row, col=col, width=width, height=height,
		style='minimal', border='none',
	})
end
local upper, lower, right = pane(0, 0, 9, 3), pane(4, 0, 9, 4), pane(0, 10, 10, 8)
vim.t.term_zoom = true
vim.t.term_winids = {upper, lower, right}
statusline.update()
local seen = {}
for _, overlay in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	local b = vim.api.nvim_win_get_buf(overlay)
	local owner = vim.b[b].terminal_stl_pane
	if owner then seen[owner] = vim.api.nvim_win_get_width(overlay) end
end
assert(seen[upper] == 9, 'upper statusline leaves the continuing vertical divider visible')
assert(seen[lower] == 10, 'bottom statusline covers the separator at aligned pane bottoms')
assert(seen[right] == 10, 'rightmost statusline stays within the pane width')
statusline.close()
for _, w in ipairs({upper, lower, right}) do vim.api.nvim_win_close(w, true) end
print('Zoom statusline divider regressions passed')
