-- terminal.nvim: window management

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local frame = require("terminal.frame")
local mode = require("terminal.mode")
local winbar = require("terminal.winbar")
local statusline = require("terminal.statusline")
local overlay = require("terminal.overlay")
local float_layout = require("terminal.float_layout")
local activity = require("terminal.activity")

local closing_pane_windows = false

function M.get_float_win_config()
	if vim.t.term_zoom then
		local tabline_height = 0
		if
			config.config.float_zoom_show_tabline and vim.o.showtabline == 2
			or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
		then
			tabline_height = 1
		end
		return {
			relative = "editor",
			width = vim.o.columns,
			height = vim.o.lines - vim.o.cmdheight - tabline_height,
			row = tabline_height,
			col = 0,
			border = "none",
		}
	end

	local float_config = {
		padding = { x = 24, y = 4 },
		border = false,
	}

	if type(config.config.float) == "table" then
		float_config = vim.tbl_extend("force", float_config, config.config.float)
	end

	local has_border = float_config.border and float_config.border ~= "none"
	local border = has_border and float_config.border or "none"
	local col = float_config.padding.x
	local row = float_config.padding.y
	local border_width = has_border and 2 or 0
	local width = math.floor(vim.o.columns - float_config.padding.x * 2 - border_width)
	local height = math.floor(vim.o.lines - float_config.padding.y * 2 - border_width - 2)

	return {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = border,
		title = " Terminal ",
		title_pos = "center",
	}
end

local function open_window(win_config)
	local scratch = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(scratch, true, win_config)
	return win, scratch
end

-- Setting vim.wo[win].winbar requires the window to have >= 2 lines (1 for
-- winbar, 1 for content); otherwise Neovim raises E36 "Not enough room".
-- This matters when the user shrinks the app window to a very small size in
-- float zoom mode.
local function can_set_winbar(win, show_winbar)
	return show_winbar and state.win_valid(win) and vim.api.nvim_win_get_height(win) >= 2
end

-- Window options that must hold on every pane window. nvim_win_set_buf calls
-- get_winopts() which restores the buffer's saved w_onebuf_opt, so these are
-- applied both before and after attaching terminal buffers; when they match,
-- the terminal sees no dimension change at attachment time.
local function apply_pane_winopts(win, float_winblend, show_winbar)
	-- Guard the drawer/editor boundary: with every pane fixed, external
	-- resize pressure (equalize, editor splits) can't change the drawer
	-- height. Set here — after the split build — because vim's win_split
	-- grows a winfixheight window instead of halving it, which would push
	-- the drawer into the editor area.
	vim.wo[win].winfixheight = true
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].scrolloff = 0
	vim.wo[win].sidescrolloff = 0
	vim.wo[win].winblend = float_winblend
	if can_set_winbar(win, show_winbar) then
		vim.wo[win].winbar = " "
	else
		vim.wo[win].winbar = ""
	end
end

-- Only panes on the layout's top row reserve a winbar slot: the floating
-- winbar overlay covers exactly that screen row. A stacked (lower) pane
-- reserving the row would show it as a blank line under the separator.
local function top_row_wins(wins)
	local min_row = math.huge
	local rows = {}
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			rows[win] = vim.api.nvim_win_get_position(win)[1]
			min_row = math.min(min_row, rows[win])
		end
	end
	local top = {}
	for win, row in pairs(rows) do
		top[win] = row == min_row
	end
	return top
end

-- Force correct PTY dimensions in zoom mode once window options are
-- finalized. nvim_win_set_buf may report stale dimensions to the PTY before
-- winbar/signcolumn/etc. are re-applied.
local function resize_zoom_ptys(wins, bufs, show_winbar, top)
	if not vim.t.term_zoom then
		return
	end
	for i, win in ipairs(wins) do
		if state.win_valid(win) then
			local job_id = vim.b[bufs[i]].terminal_job_id
			if job_id then
				local rows = vim.api.nvim_win_get_height(win)
				if can_set_winbar(win, show_winbar and top[win]) then
					rows = rows - 1
				end
				pcall(vim.fn.jobresize, job_id, vim.api.nvim_win_get_width(win), math.max(rows, 1))
			end
		end
	end
end

-- 1-based DFS index of the saved focus buffer, defaulting to 1.
local function focus_index(st, bufs)
	for i, buf in ipairs(bufs) do
		if buf == st.focus then
			return i
		end
	end
	return 1
end

-- Common tail for open/swap: focus the saved pane, publish the tab-scoped
-- window/buffer variables, clear the activity flag, and restore the mode the
-- user left the focused terminal in.
local function finalize_tab(wins, bufs, tab_idx, st)
	local focus_idx = state.clamp(focus_index(st, bufs), 1, #wins)

	if wins[focus_idx] and state.win_valid(wins[focus_idx]) then
		vim.api.nvim_set_current_win(wins[focus_idx])
	end

	vim.t.term_winids = wins
	vim.t.term_winid = wins[focus_idx] or wins[1]
	vim.t.term_bufnr = bufs[focus_idx] or bufs[1]
	vim.t.term_tab_idx = tab_idx

	state.set_activity(tab_idx, false)
	activity.sync()

	mode.apply(st.modes and bufs[focus_idx] and st.modes[tostring(bufs[focus_idx])])

	statusline.update()
	winbar.update()
end

-- Whether the current screen is large enough to host a float-mode rebuild.
-- In float zoom mode the pane window needs one content row plus any visible
-- native winbar slot, and 1 row for the statusline overlay. If the screen is
-- smaller than that, skip the rebuild and let Neovim's auto-clamp keep the
-- existing floats alive.
function M.can_rebuild_float()
	if not config.is_float_mode() then
		return true
	end
	local cfg = M.get_float_win_config()
	local tab_count = #state.get_tabs()
	local min_pane_height = config.get_winbar_height(tab_count) + 1
	local stl_height = vim.t.term_zoom and 1 or 0
	if cfg.height - stl_height < min_pane_height then
		return false
	end
	if cfg.width < 1 then
		return false
	end
	return true
end

-- Open a terminal in a temporary window so the PTY starts with correct
-- dimensions instead of the tiny aucmd window used by nvim_buf_call.
-- num_panes: how many panes will share the row/float (for width calculation)
-- tab_count: how many terminal tabs will exist once this terminal opens
function M.termopen_with_size(bufnr, num_panes, tab_count)
	num_panes = math.max(num_panes or 1, 1)
	local width = 80
	local height = math.floor(vim.o.lines * 0.5)
	local winbar_height = config.get_winbar_height(tab_count)

	if config.is_float_mode() then
		local cfg = M.get_float_win_config()
		width = cfg.width
		if num_panes > 1 then
			-- Subtract separator columns, then divide evenly
			width = math.floor((width - (num_panes - 1)) / num_panes)
		end
		height = cfg.height - winbar_height
	else
		local h = vim.t.term_height or config.get_term_height()
		height = h - winbar_height
		width = math.floor(vim.o.columns / num_panes)
	end

	local tmp_win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = math.max(width, 1),
		height = math.max(height, 1),
		row = 0,
		col = 0,
		noautocmd = true,
	})
	vim.fn.termopen(vim.env.SHELL or vim.o.shell)
	vim.api.nvim_win_close(tmp_win, true)
end

function M.save_tab_state()
	local _, tab_idx = state.get_current_tab()
	if not tab_idx then
		return
	end

	local wins = winbar.get_term_windows()
	if #wins == 0 then
		return
	end

	local prev_state = state.get_tab_state(tab_idx)

	local st = {
		layout = prev_state.layout,
		focus = prev_state.focus,
		modes = {},
	}

	local current_win = vim.api.nvim_get_current_win()
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			st.modes[tostring(buf)] = vim.b[buf].term_mode or "t"
			if win == current_win then
				st.focus = buf
			end
		end
	end

	state.set_tab_state(tab_idx, st)
end

-- Apply the layout tree's leaf sizes to the real drawer windows (DFS order).
-- Heights first so vim redistributes columns within settled rows.
-- winfixheight is lifted while redistributing: the tree preserves the total,
-- so the cascade stays between panes, but fixed siblings would make vim take
-- the rows from the editor instead.
function M.apply_drawer_sizes(entry)
	local wins = vim.t.term_winids or {}
	local leaves = frame.leaf_nodes(entry.layout)
	if #wins ~= #leaves then
		return
	end
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			vim.wo[win].winfixheight = false
		end
	end
	for pass = 1, 2 do
		for i, win in ipairs(wins) do
			if state.win_valid(win) then
				if pass == 1 then
					vim.api.nvim_win_set_height(win, leaves[i].h)
				else
					vim.api.nvim_win_set_width(win, leaves[i].w)
				end
			end
		end
	end
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			vim.wo[win].winfixheight = true
		end
	end
end

-- Set the drawer's total height (rows spanned by all panes). Single panes
-- resize in place; stacked layouts rebuild so the tree rescales
-- proportionally into the new height.
function M.set_drawer_height(target)
	vim.t.term_height = target
	if config.is_float_mode() then
		return
	end
	local wins = vim.t.term_winids or {}
	if #wins == 0 then
		return
	end
	if #wins == 1 then
		if state.win_valid(wins[1]) then
			vim.api.nvim_win_call(wins[1], function()
				vim.api.nvim_win_set_height(0, target)
			end)
			M.save_layout_sizes()
		end
	else
		state.set_toggling()
		M.rebuild_tab()
	end
	-- vim clamps oversized heights; record what we actually got
	local span = state.drawer_span()
	if span and span > 0 then
		vim.t.term_height = span
	end
end

-- Persist the current on-screen pane sizes into the tab's layout tree.
-- Windows and layout leaves correspond by DFS order.
function M.save_layout_sizes()
	local _, tab_idx = state.get_current_tab()
	if not tab_idx then
		return
	end
	local wins = vim.t.term_winids or {}
	if #wins == 0 then
		return
	end
	local order = state.get_term_order()
	local entry = order[tab_idx]
	if not entry or not entry.layout or #wins ~= #entry.bufs then
		return
	end
	local sizes = {}
	for i, win in ipairs(wins) do
		if not state.win_valid(win) then
			return
		end
		sizes[i] = { w = vim.api.nvim_win_get_width(win), h = vim.api.nvim_win_get_height(win) }
	end
	frame.set_leaf_sizes(entry.layout, sizes)
	vim.t.term_order = order
end

function M.close_pane_windows()
	if closing_pane_windows then
		return
	end
	closing_pane_windows = true

	state.restore_cmdheight()
	state.restore_ruler()
	winbar.destroy()
	statusline.close()
	overlay.destroy()
	float_layout.close_canvas()

	local wins = vim.t.term_winids or {}
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			local cfg = vim.api.nvim_win_get_config(win)
			if cfg.relative and cfg.relative ~= "" then
				vim.api.nvim_win_close(win, true)
			else
				if vim.api.nvim_get_current_win() == win then
					vim.cmd("wincmd p")
				end
				local winnr = vim.fn.win_id2win(win)
				if winnr > 0 then
					vim.cmd(winnr .. "close")
				end
			end
		end
	end

	vim.t.term_winids = {}
	vim.t.term_winid = nil
	closing_pane_windows = false
end

function M.open_tab_windows(entry, tab_idx)
	if not entry or not entry.bufs or #entry.bufs == 0 then
		return
	end

	if vim.t.term_zoom then
		state.set_zoom_cmdheight()
		state.set_zoom_ruler()
	end

	local bufs = entry.bufs
	local st = entry
	local tab_count = #state.get_tabs()
	local show_winbar = config.should_show_winbar(tab_count)

	local wins = {}
	local scratches = {}
	local height = vim.t.term_height or config.get_term_height()

	local has_stl = false
	local focus_idx = state.clamp(focus_index(st, bufs), 1, #bufs)

	if config.is_float_mode() then
		overlay.update()
		local base_config = M.get_float_win_config()

		-- Panes are borderless floats positioned by the layout tree's rects;
		-- the canvas float below them draws the border and all separators.
		has_stl = vim.t.term_zoom and true or false
		local stl_height = has_stl and 1 or 0
		local origin_row, origin_col = float_layout.content_origin(base_config)

		local layout = vim.deepcopy(st.layout)
		frame.rescale(layout, base_config.width, base_config.height - stl_height)
		local rects = frame.rects(layout, 0, 0)

		float_layout.update_canvas(layout, base_config)

		for i, buf in ipairs(bufs) do
			local rect = rects[buf]
			local win_cfg = {
				relative = "editor",
				row = origin_row + rect.row,
				col = origin_col + rect.col,
				width = rect.w,
				height = rect.h,
				border = "none",
				zindex = (i == focus_idx) and 31 or 30,
			}
			local win, scratch = open_window(win_cfg)
			table.insert(wins, win)
			table.insert(scratches, scratch)
		end
	else
		-- Drawer: one full-width bottom split, then real splits following the
		-- layout tree. Recursion order yields windows in DFS (bufs) order.
		-- winfixheight is applied later (apply_pane_winopts): splitting a
		-- fixed-height window makes vim grow it into the editor area.
		local first_win, first_scratch = open_window({
			split = "below",
			win = -1,
			height = height,
		})
		table.insert(scratches, first_scratch)

		local layout = vim.deepcopy(st.layout)
		frame.rescale(layout, vim.api.nvim_win_get_width(first_win), vim.api.nvim_win_get_height(first_win))

		-- Every split is created at its exact size: an explicit width/height
		-- in the nvim_open_win split config bypasses 'equalalways', which
		-- would otherwise re-equalize the whole tabpage column (editor
		-- included) and grow the drawer.
		local function build(node, win)
			if node.t == "leaf" then
				table.insert(wins, win)
				return
			end
			local n = #node.children
			local dim = node.t == "row" and "w" or "h"
			-- tail[i]: span of children i..n (their sizes plus separators);
			-- splitting the previous window at tail[i] leaves it exactly its
			-- own child's size
			local tail = { [n] = node.children[n][dim] }
			for i = n - 1, 2, -1 do
				tail[i] = tail[i + 1] + node.children[i][dim] + 1
			end
			local child_wins = { win }
			for i = 2, n do
				local cfg = {
					split = node.t == "row" and "right" or "below",
					win = child_wins[i - 1],
				}
				if node.t == "row" then
					cfg.width = tail[i]
				else
					cfg.height = tail[i]
				end
				local w, scratch = open_window(cfg)
				table.insert(scratches, scratch)
				child_wins[i] = w
			end
			for i, child in ipairs(node.children) do
				build(child, child_wins[i])
			end
		end
		build(layout, first_win)
	end

	-- Set window options on the scratch windows BEFORE attaching terminal
	-- buffers, so the terminal sees no dimension change at attachment time.
	local float_winblend = config.get_float_winblend()
	local top = top_row_wins(wins)
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			apply_pane_winopts(win, float_winblend, show_winbar and top[win])
			vim.wo[win].cursorline = false
			vim.wo[win].cursorcolumn = false
			vim.wo[win].spell = false
			vim.wo[win].list = false
			vim.wo[win].colorcolumn = ""
			vim.wo[win].statuscolumn = ""
			vim.wo[win].fillchars = "eob: "
			vim.wo[win].winhighlight = "EndOfBuffer:"
		end
	end

	-- Attach terminal buffers. get_winopts() may overwrite some options
	-- from the buffer's WinInfo, so re-set them afterward.
	--
	-- Wrap in pcall so that if any operation raises (e.g. the app window is
	-- too small), eventignore is always restored. Otherwise a stuck
	-- eventignore silences Buf* events and makes Neovim appear frozen.
	local old_eventignore = vim.o.eventignore
	vim.o.eventignore = "BufEnter,BufLeave,BufWinEnter"
	local attach_ok, attach_err = pcall(function()
		for i, win in ipairs(wins) do
			if state.win_valid(win) then
				vim.api.nvim_win_set_buf(win, bufs[i])
				apply_pane_winopts(win, float_winblend, show_winbar and top[win])
			end
		end
	end)
	vim.o.eventignore = old_eventignore
	if not attach_ok then
		error(attach_err)
	end

	resize_zoom_ptys(wins, bufs, show_winbar, top)

	for _, scratch in ipairs(scratches) do
		if vim.api.nvim_buf_is_valid(scratch) then
			vim.api.nvim_buf_delete(scratch, { force = true })
		end
	end

	finalize_tab(wins, bufs, tab_idx, st)
end

function M.reopen_current_tab(target_idx, tabs)
	tabs = tabs or state.get_tabs()
	if #tabs == 0 then
		vim.t.term_winid = nil
		vim.t.term_winids = {}
		vim.t.term_bufnr = nil
		return
	end
	target_idx = target_idx or vim.t.term_tab_idx or 1
	target_idx = state.clamp(target_idx, 1, #tabs)
	M.open_tab_windows(tabs[target_idx], target_idx)
end

function M.rebuild_tab(target_idx, tabs)
	M.save_tab_state()
	M.close_pane_windows()
	M.reopen_current_tab(target_idx, tabs)
end

function M.swap_tab_buffers(target_entry, target_idx)
	-- Fast-path buffer swap: reuse existing pane windows.
	-- Called only when pane counts match (checked by caller).
	-- Mirrors the buffer-attach logic in open_tab_windows().
	local wins = vim.t.term_winids or {}
	local target_bufs = target_entry.bufs
	local target_st = target_entry
	local tab_count = #state.get_tabs()
	local show_winbar = config.should_show_winbar(tab_count)
	local float_winblend = config.get_float_winblend()
	local is_float = config.is_float_mode()

	local focus_idx = state.clamp(focus_index(target_st, target_bufs), 1, #wins)

	-- Pre-validation: abort to rebuild_tab if the open windows don't match the
	-- target tab's panes, or if any window or buffer is invalid. The caller
	-- compares pane counts in the data model (term_order), but term_winids can
	-- briefly disagree with it (e.g. TermClose shrinks term_order synchronously
	-- while the rebuild is deferred via vim.schedule).
	if #wins ~= #target_bufs then
		return false
	end
	for i, win in ipairs(wins) do
		if not state.win_valid(win) then
			return false
		end
		if not vim.api.nvim_buf_is_valid(target_bufs[i]) then
			return false
		end
	end

	-- Swap buffers in all pane windows (single eventignore/pcall block)
	local top = top_row_wins(wins)
	local old_eventignore = vim.o.eventignore
	vim.o.eventignore = "BufEnter,BufLeave,BufWinEnter"
	local swap_ok = pcall(function()
		for i, win in ipairs(wins) do
			vim.api.nvim_win_set_buf(win, target_bufs[i])
			-- Re-apply window options (nvim_win_set_buf restores buffer's saved WinInfo)
			apply_pane_winopts(win, float_winblend, show_winbar and top[win])
			-- Update z-index in float mode if focus changed
			if is_float then
				vim.api.nvim_win_set_config(win, { zindex = (i == focus_idx) and 31 or 30 })
			end
		end
	end)
	vim.o.eventignore = old_eventignore

	if not swap_ok then
		return false
	end

	resize_zoom_ptys(wins, target_bufs, show_winbar, top)

	finalize_tab(wins, target_bufs, target_idx, target_st)
	return true
end

function M.switch_to_tab(target_idx)
	local current_idx = vim.t.term_tab_idx
	if current_idx and current_idx ~= target_idx then
		vim.t.term_prev_tab_idx = current_idx
	end

	-- Fast path: swap buffers in place when the layout shapes match
	local tabs = state.get_tabs()
	local current_tab = tabs[current_idx or 1]
	local target_tab = tabs[target_idx]
	if
		current_tab
		and target_tab
		and current_tab.layout
		and target_tab.layout
		and frame.same_shape(current_tab.layout, target_tab.layout)
	then
		M.save_tab_state()
		state.set_toggling()
		if M.swap_tab_buffers(target_tab, target_idx) then
			return
		end
		-- Fast path failed (invalid window/buffer or pcall error), fall back to rebuild
	end

	state.set_toggling()
	M.rebuild_tab(target_idx, tabs)
end

return M
