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

local state = require("terminal.state")

eq(state.compute_equal_widths(10, 3), { 4, 3, 3 }, "compute_equal_widths distributes remainder left-first")
eq(state.compute_equal_widths(9, 3), { 3, 3, 3 }, "compute_equal_widths exact division")
eq(state.clamp(5, 1, 3), 3, "clamp upper")
eq(state.clamp(-2, 1, 3), 1, "clamp lower")

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
do
	local v4 = state.migrate_term_order({
		{ bufs = { 7, 8 }, widths = { 20, 11 }, focus = 2, modes = { "n", "t" } },
	})
	local e = v4[1]
	eq(e.layout.t, "row", "migrate v3 builds a row layout")
	eq({ e.layout.children[1].w, e.layout.children[2].w }, { 20, 11 }, "migrate v3 keeps saved widths")
	eq(e.focus, 8, "migrate v3 converts focus index to bufnr")
	eq(e.modes, { ["7"] = "n", ["8"] = "t" }, "migrate v3 keys modes by bufnr")
	eq(e.widths, nil, "migrate v3 drops the widths array")
	ok(state.migrate_term_order(v4)[1].layout ~= nil, "migrate v4 passes through")
end

--------------------------------------------------------------------------------
-- Unit: frame tree engine (pure)
--------------------------------------------------------------------------------

local frame = require("terminal.frame")

local function leaf(buf, w, h)
	return { t = "leaf", buf = buf, w = w, h = h }
end

-- split: promotion (different direction) and sibling insert (same direction)
do
	local root = leaf(1, 21, 10)
	root = frame.split(root, 1, "row", 2)
	eq(root.t, "row", "split leaf promotes to a row")
	eq({ root.children[1].w, root.children[2].w }, { 10, 10 }, "vsplit halves width minus separator")
	eq(frame.leaves(root), { 1, 2 }, "new pane goes after current")

	root = frame.split(root, 2, "row", 3)
	eq(#root.children, 3, "same-direction split inserts sibling, no nesting")
	eq(frame.leaves(root), { 1, 2, 3 }, "sibling inserted after current")

	root = frame.split(root, 2, "col", 4)
	eq(root.children[2].t, "col", "cross split promotes leaf to col in place")
	eq(frame.leaves(root), { 1, 2, 4, 3 }, "DFS order after nested split")
	local col = root.children[2]
	eq({ col.children[1].h, col.children[2].h }, { 4, 5 }, "hsplit halves height, old keeps ceil-half minus sep")

	local tiny = leaf(9, 2, 2)
	local _, err = frame.split(tiny, 9, "col", 10)
	ok(err ~= nil, "split fails when not enough room")
end

-- remove: absorb rules + flatten
do
	local root = leaf(1, 32, 10)
	root = frame.split(root, 1, "row", 2)
	root = frame.split(root, 2, "row", 3)
	local w2 = root.children[2].w
	local w3 = root.children[3].w
	local absorbed
	root, absorbed = frame.remove(root, 2)
	eq(absorbed, 3, "next sibling absorbs the freed space")
	eq(root.children[2].w, w2 + w3 + 1, "absorber gains size plus separator")

	root, absorbed = frame.remove(root, 3)
	eq(absorbed, 1, "previous sibling absorbs when closing the last")
	eq(root.t, "leaf", "row collapses to a leaf")
	eq(root.w, 32, "collapsed leaf takes the full width")

	root, absorbed = frame.remove(root, 1)
	ok(root == nil, "removing the only pane returns nil root")

	-- flatten splices same-type grandchildren
	local r2 = leaf(1, 32, 11)
	r2 = frame.split(r2, 1, "col", 2)
	r2 = frame.split(r2, 2, "row", 3)
	r2 = frame.split(r2, 3, "col", 4)
	r2 = select(1, frame.remove(r2, 2))
	local function assert_invariant(node)
		if node.t == "leaf" then
			return true
		end
		for _, c in ipairs(node.children) do
			if c.t == node.t or not assert_invariant(c) then
				return false
			end
		end
		return true
	end
	ok(assert_invariant(r2), "flatten restores the no-same-type-nesting invariant")
end

-- set_size: vim's next-first/prev-second cascade
do
	local root = { t = "col", w = 20, h = 32, children = { leaf(1, 20, 10), leaf(2, 20, 10), leaf(3, 20, 10) } }
	frame.set_size(root, 2, "h", 15)
	eq({ root.children[1].h, root.children[2].h, root.children[3].h }, { 10, 15, 5 }, "grow takes from next sibling first")

	root = { t = "col", w = 20, h = 32, children = { leaf(1, 20, 10), leaf(2, 20, 10), leaf(3, 20, 10) } }
	frame.set_size(root, 2, "h", 22)
	eq({ root.children[1].h, root.children[2].h, root.children[3].h }, { 7, 22, 1 }, "grow cascades past min to prev siblings")

	root = { t = "col", w = 20, h = 32, children = { leaf(1, 20, 10), leaf(2, 20, 10), leaf(3, 20, 10) } }
	frame.set_size(root, 2, "h", 5)
	eq({ root.children[1].h, root.children[2].h, root.children[3].h }, { 10, 5, 15 }, "shrink gives everything to next sibling")
end

-- equalize: proportional with remainder to the last child
do
	local root = { t = "row", w = 32, h = 10, children = { leaf(1, 5, 10), leaf(2, 20, 10), leaf(3, 5, 10) } }
	frame.equalize(root, 32, 10)
	eq({ root.children[1].w, root.children[2].w, root.children[3].w }, { 10, 10, 10 }, "equalize splits evenly")

	local nested = { t = "row", w = 32, h = 10, children = {
		leaf(1, 10, 10),
		{ t = "col", w = 21, h = 10, children = {
			leaf(2, 21, 4),
			{ t = "row", w = 21, h = 5, children = { leaf(3, 10, 5), leaf(4, 10, 5) } },
		} },
	} }
	frame.equalize(nested, 32, 10)
	eq(nested.children[1].w, 10, "single window gets one share")
	eq(nested.children[2].w, 21, "nested pair gets two shares plus remainder")
end

-- rects + separators
do
	local root = { t = "row", w = 21, h = 10, children = {
		leaf(1, 10, 10),
		{ t = "col", w = 10, h = 10, children = { leaf(2, 10, 4), leaf(3, 10, 5) } },
	} }
	local rects, seps = frame.rects(root, 0, 0)
	eq(rects[1], { row = 0, col = 0, w = 10, h = 10 }, "first pane rect")
	eq(rects[2], { row = 0, col = 11, w = 10, h = 4 }, "top-right pane rect")
	eq(rects[3], { row = 5, col = 11, w = 10, h = 5 }, "bottom-right pane rect")
	eq(#seps, 2, "one vertical and one horizontal separator")
	local sep = frame.sep_at(root, 4, 11)
	ok(sep and sep.axis == "h", "sep_at finds the horizontal separator")
	ok(frame.sep_at(root, 2, 10) and frame.sep_at(root, 2, 10).axis == "v", "sep_at finds the vertical separator")
end

-- navigate: cursor-column/row descent (vim win_vert/horz_neighbor)
do
	local root = { t = "row", w = 21, h = 10, children = {
		leaf(1, 10, 10),
		{ t = "col", w = 10, h = 10, children = { leaf(2, 10, 4), leaf(3, 10, 5) } },
	} }
	eq(frame.navigate(root, 1, "l", 1, { row = 0, col = 0 }), 2, "right from top area lands in top pane")
	eq(frame.navigate(root, 1, "l", 1, { row = 8, col = 0 }), 3, "right from bottom area lands in bottom pane")
	eq(frame.navigate(root, 2, "h", 1, { row = 0, col = 11 }), 1, "left crosses back")
	eq(frame.navigate(root, 3, "k", 1, { row = 6, col = 15 }), 2, "up within the col")
	eq(frame.navigate(root, 2, "k", 1, { row = 0, col = 11 }), 2, "no neighbor: stay put")
	eq(frame.navigate(root, 1, "j", 1, { row = 0, col = 0 }), 1, "full-height pane has no vertical neighbor")
end

-- rotate / exchange
do
	local root = { t = "row", w = 32, h = 10, children = { leaf(1, 10, 10), leaf(2, 10, 10), leaf(3, 10, 10) } }
	frame.rotate(root, 1, false, 1)
	eq(frame.leaves(root), { 3, 1, 2 }, "rotate downwards moves last buf to front")
	frame.rotate(root, 1, true, 1)
	eq(frame.leaves(root), { 1, 2, 3 }, "rotate upwards undoes it")
	eq(root.children[1].w, 10, "rotate keeps slot geometry")

	local nested = { t = "row", w = 21, h = 10, children = {
		leaf(1, 10, 10),
		{ t = "col", w = 10, h = 10, children = { leaf(2, 10, 4), leaf(3, 10, 5) } },
	} }
	local _, err = frame.rotate(nested, 1, false, 1)
	ok(err and err:match("E443"), "rotate refuses when a sibling is split (E443)")

	local ex = { t = "row", w = 32, h = 10, children = { leaf(1, 10, 10), leaf(2, 10, 10), leaf(3, 10, 10) } }
	local _, focus = frame.exchange(ex, 1)
	eq(frame.leaves(ex), { 2, 1, 3 }, "exchange swaps with next sibling")
	eq(focus, 2, "focus stays in the original slot (now the other buf)")
end

-- splitmove (CTRL-W J): full width at the bottom, height preserved
do
	local root = { t = "row", w = 21, h = 20, children = { leaf(1, 10, 20), leaf(2, 10, 20) } }
	root = frame.splitmove(root, 1, "bottom")
	eq(root.t, "col", "splitmove wraps the layout in a col")
	eq(frame.leaves(root), { 2, 1 }, "moved pane is at the bottom")
	eq(root.children[2].w, 21, "moved pane is full width")
	eq(root.children[2].h, 20 - frame.min_size(root.children[1], "h") - 1, "height preserved up to available room")
end

-- drag
do
	local root = { t = "row", w = 32, h = 10, children = { leaf(1, 10, 10), leaf(2, 10, 10), leaf(3, 10, 10) } }
	local _, seps = frame.rects(root, 0, 0)
	frame.drag(root, seps[1], 4)
	eq({ root.children[1].w, root.children[2].w, root.children[3].w }, { 14, 6, 10 }, "drag right grows left pane, shrinks neighbor")
	frame.drag(root, seps[1], 15)
	eq({ root.children[1].w, root.children[2].w, root.children[3].w }, { 28, 1, 1 }, "drag clamps to available room and cascades")
end

-- rescale / same_shape / from_bufs
do
	local root = frame.from_bufs({ 1, 2 }, { 20, 11 }, 32, 10)
	frame.rescale(root, 64, 20)
	eq(root.w, 64, "rescale sets new width")
	ok(root.children[1].w > root.children[2].w, "rescale keeps proportions")
	eq(root.children[1].w + root.children[2].w, 63, "rescale accounts for the separator")

	local a = frame.from_bufs({ 1, 2 }, nil, 32, 10)
	local b = frame.from_bufs({ 7, 8 }, nil, 60, 20)
	ok(frame.same_shape(a, b), "same_shape ignores bufs and sizes")
	local c = frame.split(frame.from_bufs({ 1, 2 }, nil, 32, 10), 2, "col", 3)
	ok(not frame.same_shape(a, c), "same_shape detects structural difference")
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

-- OSC titles use a terminal URI namespace, so a cwd title cannot make
-- :edit . reopen the hidden terminal.
do
	local term_buf = vim.api.nvim_get_current_buf()
	local pid = vim.fn.jobpid(vim.b[term_buf].terminal_job_id)
	vim.api.nvim_chan_send(vim.b[term_buf].terminal_job_id, "printf '\\033]0;.\\007'\n")
	settle()
	eq(vim.api.nvim_buf_get_name(term_buf), "terminal://" .. pid .. "//.", "job PID and OSC title name the terminal buffer")
	local rendered = vim.api.nvim_eval_statusline(vim.wo[vim.t.term_winid].statusline, {
		winid = vim.t.term_winid,
	})
	eq(rendered.str, ".", "terminal pane statusline displays the OSC title")
	terminal.toggle()
	settle()
	vim.cmd.edit(".")
	settle()
	ok(vim.api.nvim_get_current_buf() ~= term_buf, ":edit . does not reopen a hidden cwd-titled terminal")
	ok(vim.bo.buftype ~= "terminal", ":edit . opens a normal directory buffer")
	terminal.toggle()
	settle()

	terminal.config.statusline = false
	terminal.toggle()
	settle()
	terminal.toggle()
	settle()
	eq(vim.wo[vim.t.term_winid].statusline, vim.o.statusline, "statusline=false preserves the global statusline")
	terminal.config.statusline = true
	terminal.toggle()
	settle()
	terminal.toggle()
	settle()
end

-- new tab
terminal.new()
settle()
ok(#tabs() == 2, "new() creates a second tab")
eq(vim.t.term_tab_idx, 2, "new() focuses the new tab")

-- Activity observation is armed only for background terminal tabs and
-- detaches itself as soon as the first update has been recorded.
do
	local activity = require("terminal.activity")
	local background_buf = tab_bufs(1)[1]
	local foreground_buf = tab_bufs(2)[1]
	ok(activity.is_armed(background_buf), "background terminal has an activity watcher")
	ok(not activity.is_armed(foreground_buf), "foreground terminal has no armed activity watcher")

	vim.api.nvim_chan_send(vim.b[background_buf].terminal_job_id, "printf 'activity-watch-test\\n'\n")
	settle()
	local background_idx = state.find_buf_tab(background_buf)
	ok(tabs()[background_idx].activity == true, "first background update sets activity")
	ok(not activity.is_armed(background_buf), "activity watcher detaches after the first update")

	terminal.go_to(1)
	settle()
	ok(not tabs()[1].activity, "focusing a terminal clears its activity")
	ok(activity.is_armed(foreground_buf), "previous terminal is armed when it becomes background")
	terminal.go_to(2)
	settle()
end

-- Neovim owns b:term_title. Multiple title requests in one input burst are
-- collapsed into one buffer rename and one winbar/statusline refresh.
do
	local buf = tab_bufs(2)[1]
	local pid = vim.fn.jobpid(vim.b[buf].terminal_job_id)
	local winbar_mod = require("terminal.winbar")
	local statusline_mod = require("terminal.statusline")
	local old_winbar_update = winbar_mod.update
	local old_statusline_update = statusline_mod.update
	local winbar_updates = 0
	local statusline_updates = 0
	local buffer_count_before = #vim.api.nvim_list_bufs()
	local alternate_before = vim.fn.bufnr("#")
	winbar_mod.update = function(...)
		winbar_updates = winbar_updates + 1
		return old_winbar_update(...)
	end
	statusline_mod.update = function(...)
		statusline_updates = statusline_updates + 1
		return old_statusline_update(...)
	end

	vim.api.nvim_chan_send(
		vim.b[buf].terminal_job_id,
		"printf '\\033]0;title-one\\007\\033]0;title-two\\007'\n"
	)
	settle()
	vim.api.nvim_chan_send(vim.b[buf].terminal_job_id, "printf '\\033]0;title-two\\007'\n")
	settle()

	winbar_mod.update = old_winbar_update
	statusline_mod.update = old_statusline_update
	eq(vim.b[buf].term_title, "title-two", "native terminal title keeps the final OSC title")
	eq(vim.api.nvim_buf_get_name(buf), "terminal://" .. pid .. "//title-two", "title update names the terminal buffer")
	eq(winbar_updates, 1, "title burst renders the winbar once")
	eq(statusline_updates, 1, "title burst renders the statusline once")
	eq(#vim.api.nvim_list_bufs(), buffer_count_before, "title rename removes Neovim's old-name placeholder")
	eq(vim.fn.bufnr("#"), alternate_before, "title rename preserves the alternate buffer")
	local win = vim.fn.bufwinid(buf)
	local rendered = vim.api.nvim_eval_statusline(vim.wo[win].statusline, { winid = win })
	eq(rendered.str, "title-two", "terminal pane statusline displays the final title")
end

-- vsplit pane
terminal.vsplit()
settle()
eq(#tab_bufs(2), 2, "vsplit adds a second pane to current tab")
ok(#open_term_wins() == 2, "vsplit shows two pane windows")

-- hsplit: stack a pane below the current one (2-D drawer layout)
local span_before = state.drawer_span()
terminal.hsplit()
settle()
eq(state.drawer_span(), span_before, "hsplit preserves the drawer height")
eq(#tab_bufs(2), 3, "hsplit adds a third pane to current tab")
ok(#open_term_wins() == 3, "hsplit shows three pane windows")
do
	local t = tabs()[2]
	eq(t.layout.t, "row", "hsplit keeps the row root")
	eq(t.layout.children[2].t, "col", "hsplit nests a col under the split pane")
	local wins = open_term_wins()
	local p2 = vim.api.nvim_win_get_position(wins[2])
	local p3 = vim.api.nvim_win_get_position(wins[3])
	eq(p2[2], p3[2], "stacked panes share the same column")
	ok(p3[1] > p2[1], "third pane sits below the second")
	eq(vim.api.nvim_win_get_buf(vim.t.term_winid), tab_bufs(2)[3], "hsplit focuses the new pane")

	-- only top-row panes reserve the winbar slot; a stacked pane reserving
	-- it shows a blank line under the separator
	eq(vim.wo[wins[2]].winbar, " ", "top-row pane reserves the winbar slot")
	eq(vim.wo[wins[3]].winbar, "", "stacked pane has no blank winbar line")
end

-- toggle round-trip preserves the 2-D layout
terminal.toggle()
settle()
terminal.toggle()
settle()
do
	local t = tabs()[2]
	eq(t.layout.children[2].t, "col", "2-D layout survives toggle")
	ok(#open_term_wins() == 3, "three windows after reopen")
	eq(state.drawer_span(), span_before, "drawer height survives toggle round-trip")
end

-- zoom round-trip from drawer mode keeps the drawer height
terminal.zoom()
settle()
ok(vim.t.term_zoom == true, "zoom engages from drawer mode")
terminal.zoom()
settle()
eq(state.drawer_span(), span_before, "drawer height survives zoom round-trip")
eq(vim.t.term_height, span_before, "term_height tracks the drawer span, not the first pane")

-- delete the stacked pane: the sibling absorbs and the layout flattens
terminal.delete()
settle()
eq(#tab_bufs(2), 2, "delete removes the stacked pane")
do
	local t = tabs()[2]
	eq(t.layout.t, "row", "layout flattens back to a row")
	eq(t.layout.children[2].t, "leaf", "row children are leaves again")
end

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

-- float 2-D: vsplit + hsplit on a fresh single-pane tab render as
-- positioned floats over a canvas
terminal.new()
settle()
terminal.vsplit()
settle()
local float_buf_x = vim.api.nvim_get_current_buf()
terminal.hsplit()
settle()
local float_buf_y = vim.api.nvim_get_current_buf()
do
	local wins = open_term_wins()
	ok(#wins == 3, "float: three panes open after vsplit+hsplit")
	local all_float = true
	for _, w in ipairs(wins) do
		local c = vim.api.nvim_win_get_config(w)
		if not c.relative or c.relative == "" then
			all_float = false
		end
	end
	ok(all_float, "float: all panes are floating windows")
	ok(vim.t.term_canvas_winid ~= nil and vim.api.nvim_win_is_valid(vim.t.term_canvas_winid), "float: canvas float exists")

	local t = tabs()[vim.t.term_tab_idx]
	local ix, iy
	for i, b in ipairs(t.bufs) do
		if b == float_buf_x then ix = i end
		if b == float_buf_y then iy = i end
	end
	eq(iy, ix + 1, "float: hsplit pane follows its sibling in DFS order")
	local cx = vim.api.nvim_win_get_config((vim.t.term_winids or {})[ix])
	local cy = vim.api.nvim_win_get_config((vim.t.term_winids or {})[iy])
	eq(cx.col, cy.col, "float: stacked panes share the same column")
	ok(cy.row > cx.row, "float: split pane sits below its sibling")

	-- canvas has a junction where the horizontal separator meets the
	-- vertical one
	local canvas_buf = vim.api.nvim_win_get_buf(vim.t.term_canvas_winid)
	local text = table.concat(vim.api.nvim_buf_get_lines(canvas_buf, 0, -1, false), "\n")
	ok(text:find("│", 1, true) ~= nil, "canvas draws vertical separators")
	ok(text:find("─", 1, true) ~= nil, "canvas draws horizontal separators")
	ok(text:find("├", 1, true) ~= nil or text:find("┤", 1, true) ~= nil, "canvas draws the junction char")

	-- vim-style directional navigation between float panes
	local panes = require("terminal.panes")
	eq(vim.api.nvim_get_current_buf(), float_buf_y, "float: focus is on the split pane")
	panes.navigate("k")
	settle()
	eq(vim.api.nvim_get_current_buf(), float_buf_x, "float: navigate k lands on the pane above")
	panes.navigate("j")
	settle()
	eq(vim.api.nvim_get_current_buf(), float_buf_y, "float: navigate j goes back down")
end

-- delete the two extra panes; canvas disappears with the last separator
terminal.delete()
settle()
terminal.delete()
settle()
ok(#open_term_wins() == 1, "float: back to a single pane")
ok(vim.t.term_canvas_winid == nil or not vim.api.nvim_win_is_valid(vim.t.term_canvas_winid),
	"float: canvas closes when no separators remain")

terminal.float_toggle()
settle()
local drawer_cfg = vim.api.nvim_win_get_config(vim.t.term_winid)
eq(drawer_cfg.relative, "", "float_toggle returns to drawer mode")

--------------------------------------------------------------------------------
-- Wincmd ops smoke (drawer): navigate / rotate / exchange / splitmove
--------------------------------------------------------------------------------

local panes = require("terminal.panes")
local float_layout = require("terminal.float_layout")

-- fresh tab shaped row[A, col[B, C]]
terminal.new()
settle()
local A = vim.api.nvim_get_current_buf()
terminal.vsplit()
settle()
local B = vim.api.nvim_get_current_buf()
terminal.hsplit()
settle()
local C = vim.api.nvim_get_current_buf()
local ops_tab = vim.t.term_tab_idx

panes.navigate("k")
settle()
eq(vim.api.nvim_get_current_buf(), B, "navigate k moves from C up to B")
panes.navigate("h")
settle()
eq(vim.api.nvim_get_current_buf(), A, "navigate h crosses into A")

-- rotate next to a split sibling is refused (E443), layout unchanged
panes.rotate(1)
settle()
eq(tab_bufs(ops_tab), { A, B, C }, "rotate next to a split is refused (E443)")

-- rotate within the col: B and C trade slots, focus follows B
panes.navigate("l")
settle()
eq(vim.api.nvim_get_current_buf(), B, "navigate l returns into the col")
panes.rotate(1)
settle()
eq(tab_bufs(ops_tab), { A, C, B }, "rotate swaps the stacked panes")
eq(vim.api.nvim_get_current_buf(), B, "rotate keeps focus on the same buffer")

-- exchange with the sibling: focus stays in the slot (now showing C)
panes.exchange()
settle()
eq(tab_bufs(ops_tab), { A, B, C }, "exchange swaps the col siblings back")
eq(vim.api.nvim_get_current_buf(), C, "exchange focus stays in the same slot")

-- splitmove C to the bottom: full width, layout reshapes to col[row[A,B], C]
panes.splitmove("bottom")
settle()
do
	local t = tabs()[ops_tab]
	eq(t.layout.t, "col", "splitmove reshapes the root to a col")
	eq(tab_bufs(ops_tab), { A, B, C }, "splitmove keeps DFS order")
	local wins = vim.t.term_winids
	local wa = vim.api.nvim_win_get_width(wins[1])
	local wc = vim.api.nvim_win_get_width(wins[3])
	ok(wc > wa, "moved pane spans the full drawer width")
	eq(vim.api.nvim_get_current_buf(), C, "splitmove keeps focus on the moved pane")
end

-- equalize runs the proportional distribution without errors
float_layout.equalize_panes()
settle()
do
	local t = tabs()[ops_tab]
	local row = t.layout.children[1]
	eq(row.t, "row", "layout still col[row[A,B], C] after equalize")
	ok(math.abs(row.children[1].w - row.children[2].w) <= 1, "equalize balances the row widths")
end

-- winbar tab title follows the focused pane, not the first pane
do
	vim.b[A].term_title = "first-pane-title"
	vim.b[C].term_title = "focused-pane-title"
	eq(vim.api.nvim_get_current_buf(), C, "title test: focus is on pane C")
	require("terminal.winbar").update()
	local wb_buf = vim.api.nvim_win_get_buf(vim.t.term_winbar_winid)
	local line = table.concat(vim.api.nvim_buf_get_lines(wb_buf, 0, -1, false), "")
	ok(line:find("focused-pane-title", 1, true) ~= nil, "winbar shows the focused pane's title")
	ok(line:find("first-pane-title", 1, true) == nil, "winbar ignores the first pane's title")

	-- background tabs use their saved focus
	local bg_idx
	for i in ipairs(tabs()) do
		if i ~= ops_tab then
			bg_idx = i
			break
		end
	end
	if bg_idx then
		terminal.go_to(bg_idx)
		settle()
		require("terminal.winbar").update()
		local line2 = table.concat(
			vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(vim.t.term_winbar_winid), 0, -1, false),
			""
		)
		ok(line2:find("focused-pane-title", 1, true) ~= nil, "background tab title uses its saved focus")
	end
end

--------------------------------------------------------------------------------
-- Mouse handlers: statusline pass-through (drawer) and horizontal canvas
-- separator drag (float). Driven directly with synthetic mouse positions —
-- headless -l scripts have no UI input loop for real mouse events.
--------------------------------------------------------------------------------

terminal.go_to(ops_tab)
settle()
do
	-- layout: col[row[A,B], C]; A's statusline row sits between the row and C.
	-- The handlers must PASS the events through (they used to swallow them),
	-- so vim's native statusline drag can resize the stacked panes.
	local wins = vim.t.term_winids
	local posA = vim.api.nvim_win_get_position(wins[1])
	local hA = vim.api.nvim_win_get_height(wins[1])
	local stl = { winid = wins[1], line = 0, column = 3, screenrow = posA[1] + hA + 1, screencol = 4 }

	eq(float_layout.on_left_mouse(stl), "<LeftMouse>", "statusline press passes through to native drag")
	stl.screenrow = stl.screenrow - 2
	eq(float_layout.on_left_drag(stl), "<LeftDrag>", "statusline drag passes through to native drag")
	eq(float_layout.on_left_release(stl), "<LeftRelease>", "statusline release passes through")
	settle()
end

terminal.float_toggle()
settle()
do
	-- same tab in float mode: drag the horizontal canvas separator above C
	local window = require("terminal.window")
	local frame2 = require("terminal.frame")
	local wins = vim.t.term_winids
	local cA = vim.api.nvim_win_get_config(wins[1])
	local cC = vim.api.nvim_win_get_config(wins[3])
	local hA, hC = cA.height, cC.height

	local base = window.get_float_win_config()
	local origin_row, origin_col = float_layout.content_origin(base)
	local entry = tabs()[vim.t.term_tab_idx]
	local hsep
	for _, sep in ipairs(select(2, frame2.rects(entry.layout, 0, 0))) do
		if sep.axis == "h" then
			hsep = sep
		end
	end
	ok(hsep ~= nil, "float: layout has a horizontal separator")

	local m = {
		winid = wins[1],
		line = 1,
		column = 1,
		screenrow = origin_row + hsep.row + 1,
		screencol = origin_col + hsep.col + 3,
	}
	eq(float_layout.on_left_mouse(m), "", "float: press on the separator starts a drag")
	m.screenrow = m.screenrow - 2
	eq(float_layout.on_left_drag(m), "", "float: drag is consumed")
	settle()
	eq(float_layout.on_left_release(m), "", "float: release is consumed")
	settle()

	local cA2 = vim.api.nvim_win_get_config(wins[1])
	local cC2 = vim.api.nvim_win_get_config(wins[3])
	eq(cA2.height, hA - 2, "float: horizontal separator drag shrinks the pane above")
	eq(cC2.height, hC + 2, "float: horizontal separator drag grows the pane below")
	eq(cC2.row, cC.row - 2, "float: the pane below moves up with the separator")
end

--------------------------------------------------------------------------------
-- z{height}<CR> in normal mode
--------------------------------------------------------------------------------

terminal.float_toggle() -- back to drawer mode
settle()
terminal.new()
settle()
vim.cmd("stopinsert")
vim.api.nvim_feedkeys("z6\r", "mx", false)
settle()
eq(state.drawer_span(), 6, "z{height}<CR> on a full-height pane sets the drawer height")
eq(vim.t.term_height, 6, "z{height}<CR> records the new drawer height")

terminal.hsplit()
settle()
vim.cmd("stopinsert")
vim.api.nvim_feedkeys("z2\r", "mx", false)
settle()
eq(vim.api.nvim_win_get_height(vim.t.term_winid), 2, "z{height}<CR> resizes a stacked pane")
eq(state.drawer_span(), 6, "stacked-pane z{height}<CR> keeps the drawer height")

--------------------------------------------------------------------------------
-- regression: toggling closed after pane-to-pane navigation must not leave
-- the winbar overlay stranded (WinEnter during close used to recreate it
-- anchored to a closing pane, leaving it at the top of the screen)
--------------------------------------------------------------------------------

panes.navigate("k") -- prev window is now the other pane
settle()
terminal.toggle()
settle()
do
	local strays = 0
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local cfg = vim.api.nvim_win_get_config(w)
		if cfg.relative and cfg.relative ~= "" then
			strays = strays + 1
		end
	end
	eq(strays, 0, "no stray floats after toggling the drawer closed")
	ok(vim.t.term_winbar_winid == nil, "winbar overlay is destroyed on close")
end

--------------------------------------------------------------------------------

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	os.exit(1)
end
os.exit(0)
