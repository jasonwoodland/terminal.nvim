-- Usage: nvim --clean --headless -l tests/layout.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
local config = require("terminal.config")
local window = require("terminal.window")
config.setup({ float = { padding = { x = 3 } }, float_zoom_show_tabline = false })
local cfg = window.get_float_win_config()
assert(cfg.col == 3 and cfg.row == 4, "partial padding keeps the default for the other axis")
vim.cmd("tabnew")
vim.o.showtabline = 1
vim.t.term_zoom = true
assert(window.get_float_win_config().row == 0, "hidden zoom tabline stays hidden with multiple tabs")

local frame = require("terminal.frame")
local function leaf(buf, w, h) return { t = "leaf", buf = buf, w = w, h = h } end
local inner = { t = "row", w = 7, h = 2, children = { leaf(1, 3, 2), leaf(2, 3, 2) } }
local root = { t = "row", w = 16, h = 5, children = {
	{ t = "col", w = 7, h = 5, children = { inner, leaf(3, 7, 2) } },
	leaf(4, 8, 5),
} }
local _, seps = frame.rects(root)
local outer
for _, sep in ipairs(seps) do if sep.node == root then outer = sep end end
frame.drag(root, outer, 2)
assert(inner.children[1].w == 3 and inner.children[2].w == 5,
	"drag grows the nested pane nearest the separator")
print("Layout regressions passed")
