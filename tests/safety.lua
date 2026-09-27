-- Usage: nvim --clean --headless -l tests/safety.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local frame = require("terminal.frame")
local function leaf(buf, w, h) return { t = "leaf", buf = buf, w = w, h = h } end
local original = { t = "row", w = 94, h = 3, children = {
	leaf(1, 90, 3), { t = "col", w = 3, h = 3, children = {
		leaf(2, 3, 1), { t = "row", w = 3, h = 1, children = { leaf(3, 1, 1), leaf(4, 1, 1) } },
	} },
} }
local function valid(node)
	assert(node.w >= 1 and node.h >= 1, "positive leaf and branch dimensions")
	if node.t == "leaf" then return end
	local axis, cross = node.t == "row" and "w" or "h", node.t == "row" and "h" or "w"
	local total = #node.children - 1
	for _, child in ipairs(node.children) do
		valid(child)
		total = total + child[axis]
		assert(child[cross] == node[cross], "cross-axis extent matches")
	end
	assert(total == node[axis], "children and separators exactly fill their parent")
end
for _, resize in ipairs({ frame.rescale, frame.equalize }) do
	for w = 5, 25 do
		for h = 3, 10 do
			local tree = vim.deepcopy(original)
			resize(tree, w, h)
			valid(tree)
		end
	end
	for _, size in ipairs({ { 4, 3 }, { 5, 2 }, { 0, 0 } }) do
		local tree = vim.deepcopy(original)
		assert(not pcall(resize, tree, size[1], size[2]), "undersized request is rejected")
		assert(vim.deep_equal(tree, original), "rejection leaves the tree unchanged")
	end
end

local terminal = require("terminal")
local window = require("terminal.window")
local state = require("terminal.state")
terminal.setup({ keys = false, set_buffer_name = false })
local function settle() vim.wait(160, function() return false end) end
terminal.toggle()
settle()
terminal.vsplit()
settle()
local existing = vim.t.term_winids
local padding = terminal.config.float.padding
terminal.config.float.padding = { x = vim.o.columns, y = vim.o.lines }
terminal.float_toggle()
assert(vim.deep_equal(vim.t.term_winids, existing), "undersized mode change preserves existing windows")
assert(not require("terminal.config").is_float_mode(), "rejected mode change restores config")
terminal.config.float.padding = padding
terminal.float_toggle()
settle()
existing = vim.t.term_winids
local buffer_count = #vim.api.nvim_list_bufs()
local padding_x = terminal.config.float.padding.x
terminal.config.float.padding.x = (vim.o.columns - 4) / 2
terminal.vsplit()
assert(vim.deep_equal(vim.t.term_winids, existing), "undersized split preserves the current view")
assert(#vim.api.nvim_list_bufs() == buffer_count, "rejected split starts no terminal")
terminal.config.float.padding.x = padding_x
terminal.toggle()
settle()

-- Reuse the canvas/overlay buffers allocated above; all attempt-local resources
-- must disappear on failure, including the scratch for a failed open call.
local before_wins, before_bufs = vim.api.nvim_list_wins(), vim.api.nvim_list_bufs()
local native_open = vim.api.nvim_open_win
local calls = 0
vim.api.nvim_open_win = function(buf, enter, cfg)
	if cfg.zindex == 30 or cfg.zindex == 31 then
		calls = calls + 1
		if calls == 2 then error("injected open failure") end
	end
	return native_open(buf, enter, cfg)
end
local ok, err = pcall(window.open_tab_windows, state.get_current_tab())
vim.api.nvim_open_win = native_open
assert(not ok and tostring(err):find("injected open failure"), "injected open failure surfaces")
assert(vim.deep_equal(vim.api.nvim_list_wins(), before_wins), "failed open leaves no windows")
assert(vim.deep_equal(vim.api.nvim_list_bufs(), before_bufs), "failed open leaves no scratch buffers")

local native_attach = vim.api.nvim_win_set_buf
vim.o.eventignore = "CursorHold"
vim.api.nvim_win_set_buf = function(win, buf)
	if vim.bo[buf].buftype == "terminal" then error("injected attach failure") end
	return native_attach(win, buf)
end
ok, err = pcall(window.open_tab_windows, state.get_current_tab())
vim.api.nvim_win_set_buf = native_attach
assert(not ok and tostring(err):find("injected attach failure"), "attachment failure surfaces")
assert(vim.o.eventignore == "CursorHold", "eventignore is restored on failure")
vim.o.eventignore = ""
assert(vim.deep_equal(vim.api.nvim_list_wins(), before_wins), "failed attachment leaves no windows")
assert(vim.deep_equal(vim.api.nvim_list_bufs(), before_bufs), "failed attachment leaves no scratches")
terminal.toggle()
settle()

local native_close = vim.api.nvim_win_close
vim.api.nvim_win_close = function(win, force)
	if win == vim.t.term_test_failure_win then error("injected close failure") end
	return native_close(win, force)
end
vim.t.term_test_failure_win = vim.t.term_winids[1]
assert(not pcall(window.close_pane_windows), "close failure surfaces")
vim.api.nvim_win_close = native_close
window.close_pane_windows()
assert(not state.is_term_open(), "a failed close does not poison the reentrancy guard")

terminal.config.float.enabled = false
vim.t.term_float_enabled = nil
before_wins, before_bufs = vim.api.nvim_list_wins(), vim.api.nvim_list_bufs()
calls = 0
vim.api.nvim_open_win = function(buf, enter, cfg)
	if cfg.split then
		calls = calls + 1
		if calls == 2 then error("injected split failure") end
	end
	return native_open(buf, enter, cfg)
end
ok, err = pcall(window.open_tab_windows, state.get_current_tab())
vim.api.nvim_open_win = native_open
assert(not ok and tostring(err):find("injected split failure"), "drawer construction failure surfaces")
assert(vim.deep_equal(vim.api.nvim_list_wins(), before_wins), "intermediate drawer windows are cleaned")
assert(vim.deep_equal(vim.api.nvim_list_bufs(), before_bufs), "drawer scratches are cleaned")

local native_termopen = vim.fn.termopen
vim.fn.termopen = function() error("injected startup failure") end
local scratch = vim.api.nvim_create_buf(false, true)
ok, err = pcall(window.termopen_with_size, scratch)
vim.fn.termopen = native_termopen
assert(not ok and tostring(err):find("injected startup failure"), "startup failure surfaces")
assert(vim.deep_equal(vim.api.nvim_list_wins(), before_wins), "startup failure closes the temporary window")
assert(vim.deep_equal(vim.api.nvim_list_bufs(), before_bufs), "startup failure deletes the unused buffer")
terminal.toggle()
settle()
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if not vim.tbl_contains(vim.t.term_winids, win) and vim.api.nvim_win_get_config(win).relative == "" then
		vim.api.nvim_win_close(win, true)
	end
end
window.close_pane_windows()
assert(not state.is_term_open() and vim.bo.buftype ~= "terminal", "last ordinary pane becomes an editor window")
print("Layout safety regressions passed")
