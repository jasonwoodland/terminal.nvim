-- Usage: nvim --clean --headless -l tests/deferred.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
local state = require("terminal.state")
local window = require("terminal.window")
local layout = require("terminal.float_layout")
local frame = require("terminal.frame")
terminal.setup({ keys = false, set_buffer_name = false, float = { enabled = true, padding = { x = 2, y = 2 } } })
local function settle() vim.wait(160, function() return false end) end
terminal.toggle()
terminal.vsplit()
settle()
local source = vim.api.nvim_get_current_tabpage()
local function separator_mouse()
	local _, seps = frame.rects(state.get_current_tab().layout)
	local row, col = layout.content_origin(window.get_float_win_config())
	return { winid = vim.t.term_canvas_winid, line = 1, column = 1,
		screenrow = row + seps[1].row + 2, screencol = col + seps[1].col + 1 }
end
local updates = 0
local apply = layout.apply_layout
layout.apply_layout = function(entry) updates = updates + 1; return apply(entry) end
local mouse = separator_mouse()
local width = vim.api.nvim_win_get_width(vim.t.term_winids[1])
layout.on_left_mouse(mouse)
mouse.screencol = mouse.screencol + 1
layout.on_left_drag(mouse)
mouse.screencol = mouse.screencol + 1
layout.on_left_drag(mouse)
layout.on_left_release(mouse)
settle()
assert(updates == 1, "drag burst queues one layout application")
assert(vim.api.nvim_win_get_width(vim.t.term_winids[1]) == width + 2, "coalesced drag applies the final position")

mouse = separator_mouse()
layout.on_left_mouse(mouse)
mouse.screencol = mouse.screencol + 1
layout.on_left_drag(mouse)
vim.cmd("tabnew")
terminal.toggle()
local target = vim.api.nvim_get_current_tabpage()
local target_order = vim.t.term_order
settle()
layout.on_left_drag(mouse)
layout.on_left_release(mouse)
settle()
assert(updates == 1, "drag from another Vim tab is discarded")
assert(vim.deep_equal(vim.t.term_order, target_order), "stale drag does not overwrite another tab's layout")
layout.apply_layout = apply

vim.api.nvim_set_current_tabpage(source)
settle()
terminal.zoom()
settle()
local pane = vim.t.term_winids[1]
local stl
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.b[vim.api.nvim_win_get_buf(win)].terminal_stl_pane == pane then stl = win end
end
local cfg = vim.api.nvim_win_get_config(stl)
layout.on_left_mouse({ winid = stl, line = 1, column = 1, screenrow = cfg.row + 1, screencol = cfg.col + 1 })
vim.api.nvim_win_close(pane, true)
local focus = vim.api.nvim_get_current_win()
settle()
assert(vim.api.nvim_get_current_win() == focus, "deferred statusline click ignores its closed pane")

window.rebuild_tab()
terminal.new()
settle()
terminal.go_to(1)
settle()
local foreign = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(foreign, 0, -1, false, { "requested file" })
vim.api.nvim_win_set_buf(vim.t.term_winid, foreign)
terminal.go_to(2)
local expected = vim.t.term_bufnr
settle()
assert(vim.api.nvim_get_current_buf() == expected, "stale file routing cannot steal focus after a tab switch")

-- Even a round trip to the same entry/window buffers invalidates old callbacks.
local calls = 0
state.defer_view(state.capture_view(), function() calls = calls + 1 end)
terminal.go_to(1)
terminal.go_to(2)
settle()
assert(calls == 0, "window generations reject stale work after a round trip")
assert(vim.api.nvim_tabpage_is_valid(target), "unrelated Vim tab remains intact")
print("Deferred UI regressions passed")
