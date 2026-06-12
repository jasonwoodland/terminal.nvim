-- terminal.nvim test runner
-- Usage: nvim --clean --headless -l tests/run.lua

local script = arg and arg[0] or "tests/run.lua"
local root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.runtimepath:prepend(root)

-- A predictable, child-free shell so delete() never hits the confirm() prompt
vim.env.SHELL = "/bin/sh"

local failed = 0
local passed = 0

local function ok(cond, label)
	if cond then
		passed = passed + 1
		print("ok   - " .. label)
	else
		failed = failed + 1
		print("FAIL - " .. label)
	end
end

local function eq(got, want, label)
	if vim.deep_equal(got, want) then
		passed = passed + 1
		print("ok   - " .. label)
	else
		failed = failed + 1
		print(("FAIL - %s\n       got:  %s\n       want: %s"):format(label, vim.inspect(got), vim.inspect(want)))
	end
end

-- Pump the event loop: flushes vim.schedule callbacks and the 100ms
-- term_toggling defer between operations.
local function settle(ms)
	vim.wait(ms or 200, function()
		return false
	end)
end

--------------------------------------------------------------------------------
-- Unit: pure width math
--------------------------------------------------------------------------------

local float_layout = require("terminal.float_layout")
local state = require("terminal.state")

eq(state.compute_equal_widths(10, 3), { 4, 3, 3 }, "compute_equal_widths distributes remainder left-first")
eq(state.compute_equal_widths(9, 3), { 3, 3, 3 }, "compute_equal_widths exact division")
eq(state.clamp(5, 1, 3), 3, "clamp upper")
eq(state.clamp(-2, 1, 3), 1, "clamp lower")

eq(
	float_layout.calc_resized_widths({ 30, 30, 30 }, 2, 5),
	{ 30, 35, 25 },
	"grow takes from right neighbor first"
)
eq(
	float_layout.calc_resized_widths({ 30, 30, 30 }, 3, 5),
	{ 30, 25, 35 },
	"grow last pane takes from left"
)
eq(
	float_layout.calc_resized_widths({ 30, 30, 30 }, 2, -5),
	{ 30, 25, 35 },
	"shrink gives to right neighbor"
)
eq(
	float_layout.calc_resized_widths({ 3, 2, 80 }, 1, 10),
	{ 13, 1, 71 },
	"grow cascades past min-width neighbor"
)

--------------------------------------------------------------------------------
-- Unit: term_order migration
--------------------------------------------------------------------------------

eq(state.migrate_term_order({}), {}, "migrate empty order")
do
	local v2 = state.migrate_term_order({ 7, 8 })
	ok(#v2 == 2, "migrate v1 keeps tab count")
	local bufs1 = v2[1].bufs or v2[1]
	local bufs2 = v2[2].bufs or v2[2]
	eq({ bufs1, bufs2 }, { { 7 }, { 8 } }, "migrate v1 wraps each buffer in its own tab")
end
do
	local v2 = state.migrate_term_order({ { 7, 8 }, { 9 } })
	local bufs1 = v2[1].bufs or v2[1]
	eq(bufs1, { 7, 8 }, "migrate v2 preserves pane grouping")
end

--------------------------------------------------------------------------------
-- Integration smoke (headless): drive the real plugin
--------------------------------------------------------------------------------

local terminal = require("terminal")
terminal.setup({})

-- Shape-agnostic helpers (work for both the v2 list-of-buf-lists model and the
-- v3 entry-record model)
local function tabs()
	return state.get_tabs()
end
local function tab_bufs(i)
	local t = tabs()[i]
	if not t then
		return nil
	end
	return t.bufs or t
end
local function open_term_wins()
	local wins = {}
	for _, w in ipairs(vim.t.term_winids or {}) do
		if vim.api.nvim_win_is_valid(w) then
			table.insert(wins, w)
		end
	end
	return wins
end

-- open from empty state
terminal.toggle()
settle()
ok(#tabs() == 1, "toggle from empty creates one tab")
ok(#open_term_wins() == 1, "toggle opens one pane window")
ok(vim.bo[vim.api.nvim_get_current_buf()].buftype == "terminal", "focus lands in a terminal buffer")

-- new tab
terminal.new()
settle()
ok(#tabs() == 2, "new() creates a second tab")
eq(vim.t.term_tab_idx, 2, "new() focuses the new tab")

-- vsplit pane
terminal.vsplit()
settle()
eq(#tab_bufs(2), 2, "vsplit adds a second pane to current tab")
ok(#open_term_wins() == 2, "vsplit shows two pane windows")

-- switch to tab 1 (pane counts differ: full rebuild path)
terminal.go_to(1)
settle()
eq(vim.t.term_tab_idx, 1, "go_to(1) switches tab index")
eq(vim.api.nvim_win_get_buf(vim.t.term_winid), tab_bufs(1)[1], "go_to(1) displays tab 1's buffer")

-- another single-pane tab; new() inserts directly after the current tab, so
-- it lands at index 2. Switching 1<->2 exercises the fast-path swap.
terminal.new()
settle()
ok(#tabs() == 3, "third tab created")
local new_tab_buf = tab_bufs(2)[1]
terminal.go_to(1)
settle()
terminal.go_to(2)
settle()
eq(vim.api.nvim_win_get_buf(vim.t.term_winid), new_tab_buf, "fast-path switch displays target buffer")

-- move tab right (wraps to front)
terminal.go_to(3)
settle()
local moved_buf = tab_bufs(3)[1]
terminal.move(1)
settle()
eq(tab_bufs(1)[1], moved_buf, "move(1) from last position wraps tab to front")
eq(vim.t.term_tab_idx, 1, "move keeps the moved tab current")

-- delete one pane of the two-pane tab
local two_pane_idx
for i = 1, #tabs() do
	if #tab_bufs(i) == 2 then
		two_pane_idx = i
	end
end
ok(two_pane_idx ~= nil, "two-pane tab still present after move")
terminal.go_to(two_pane_idx)
settle()
terminal.delete()
settle()
eq(#tab_bufs(two_pane_idx), 1, "delete() removes one pane, keeps the tab")

-- delete whole tab (single pane)
local count_before = #tabs()
terminal.delete()
settle()
ok(#tabs() == count_before - 1, "delete() on single-pane tab removes the tab")

-- toggle close / reopen
terminal.toggle()
settle()
ok(#open_term_wins() == 0, "toggle closes all pane windows")
ok(#tabs() >= 1, "tabs survive close")
terminal.toggle()
settle()
ok(#open_term_wins() >= 1, "toggle reopens the terminal")

-- regression: per-tab state (focus/widths/modes) must follow the tab when
-- indices shift. With the old index-keyed side tables, deleting an earlier
-- tab left every later tab reading its left neighbour's saved state.
local a_idx = vim.t.term_tab_idx or 1
terminal.new()
settle()
terminal.vsplit()
settle()
local b_idx = vim.t.term_tab_idx
local b_focused_buf = vim.api.nvim_win_get_buf(vim.t.term_winid)
eq(#tab_bufs(b_idx), 2, "regression setup: tab B has two panes, focus on pane 2")

terminal.go_to(a_idx)
settle()
terminal.delete()
settle()
local shifted_idx = state.find_buf_tab(b_focused_buf)
eq(shifted_idx, b_idx - 1, "deleting an earlier tab shifts B's index down")
terminal.go_to(shifted_idx)
settle()
eq(
	vim.api.nvim_win_get_buf(vim.t.term_winid),
	b_focused_buf,
	"saved focus follows the tab across index shifts"
)

--------------------------------------------------------------------------------
-- Float mode smoke
--------------------------------------------------------------------------------

terminal.float_toggle()
settle()
ok(#open_term_wins() >= 1, "float_toggle rebuilds windows")
local float_cfg = vim.api.nvim_win_get_config(vim.t.term_winid)
ok(float_cfg.relative ~= "", "pane window is floating after float_toggle")

terminal.zoom()
settle()
ok(vim.t.term_zoom == true, "zoom engages in float mode")
terminal.zoom()
settle()
ok(not vim.t.term_zoom, "zoom toggles back off")

terminal.float_toggle()
settle()
local drawer_cfg = vim.api.nvim_win_get_config(vim.t.term_winid)
eq(drawer_cfg.relative, "", "float_toggle returns to drawer mode")

--------------------------------------------------------------------------------

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	os.exit(1)
end
os.exit(0)
