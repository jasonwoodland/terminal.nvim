-- terminal.nvim: pane operations (navigate, cycle, resize, move, rotate)

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local frame = require("terminal.frame")
local mode = require("terminal.mode")
local window = require("terminal.window")
local float_layout = require("terminal.float_layout")
local statusline = require("terminal.statusline")

-- Run a native :wincmd while preserving the terminal mode on both sides.
function M.native_wincmd(cmd, count)
	mode.record()
	vim.cmd((count or "") .. "wincmd " .. cmd)
	mode.restore_current()
	statusline.update()
end

local function focus_pane_win(win)
	mode.record()
	vim.api.nvim_set_current_win(win)
	mode.restore_current()
	statusline.update()
end

-- Focus the pane window showing buf (DFS index into term_winids).
local function focus_pane_buf(entry, buf)
	local wins = vim.t.term_winids or {}
	for i, b in ipairs(entry.bufs) do
		if b == buf then
			if wins[i] and state.win_valid(wins[i]) then
				focus_pane_win(wins[i])
			end
			return
		end
	end
end

-- Directional navigation (CTRL-W h/j/k/l). dir is the letter. Drawer mode
-- delegates to the native wincmd (vim-exact, may leave the drawer); float
-- mode runs vim's win_vert/horz_neighbor walk over the layout tree.
function M.navigate(dir, count)
	if not config.is_float_mode() then
		M.native_wincmd(dir, count)
		return
	end

	local tab, tab_idx = state.get_current_tab()
	if not tab then
		return
	end
	local bufnr = vim.api.nvim_get_current_buf()

	window.save_layout_sizes()
	local entry = state.get_term_order()[tab_idx]
	if not entry then
		return
	end
	local rects = frame.rects(entry.layout, 0, 0)
	local rect = rects[bufnr]
	if not rect then
		return
	end

	-- vim descends into neighboring frames toward the cursor's screen cell
	local cursor = {
		row = rect.row + vim.fn.winline() - 1,
		col = rect.col + vim.fn.wincol() - 1,
	}
	local target = frame.navigate(entry.layout, bufnr, dir, count or 1, cursor)
	if target and target ~= bufnr then
		focus_pane_buf(entry, target)
	end
end

-- CTRL-W w / W. A count is an absolute window number (vim), otherwise step
-- to the next/previous pane in DFS order, wrapping.
function M.cycle(count, backwards)
	if not config.is_float_mode() then
		M.native_wincmd(backwards and "W" or "w", count)
		return
	end

	local wins = vim.t.term_winids or {}
	if #wins < 2 then
		return
	end

	local target
	if count then
		target = state.clamp(count, 1, #wins)
	else
		local current = vim.api.nvim_get_current_win()
		for i, win in ipairs(wins) do
			if win == current then
				local step = backwards and -1 or 1
				target = ((i - 1 + step) % #wins) + 1
				break
			end
		end
	end
	if target and state.win_valid(wins[target]) then
		focus_pane_win(wins[target])
	end
end

-- CTRL-W t / b: native window order in drawers, layout order in floats.
function M.goto_edge(bottom)
	if not config.is_float_mode() then
		M.native_wincmd(bottom and "b" or "t")
		return
	end
	local wins = vim.t.term_winids or {}
	local win = wins[bottom and #wins or 1]
	if state.win_valid(win) then
		focus_pane_win(win)
	end
end

-- Jump to the previously focused pane window.
function M.goto_last()
	local prev = vim.t.term_prev_pane_winid
	if prev and state.win_valid(prev) then
		focus_pane_win(prev)
	end
end

-- wincmd-p behavior: native jump in drawer mode, last-pane jump in float mode.
function M.goto_previous()
	if not config.is_float_mode() then
		M.native_wincmd("p")
	else
		M.goto_last()
	end
end

-- Borrow from neighbouring panes first, then move the drawer boundary only
-- for the portion that cannot fit inside the existing workspace.
local function set_drawer_pane_height(height)
	local tab, tab_idx = state.get_current_tab()
	local bufnr = vim.api.nvim_get_current_buf()
	if not tab or not state.find_buf_tab(bufnr) or not state.is_term_open() then return end
	mode.record()
	window.save_tab_state()
	local entry = state.get_term_order()[tab_idx]
	local layout = entry.layout
	local _, available = require("terminal.size").available(false)
	frame.set_size(layout, bufnr, "h", height)
	if not frame.set_size_outer(layout, bufnr, "h", height, available) then return end
	local previous_height = vim.t.term_height
	vim.t.term_height = layout.h
	if not window.can_open_tab(entry) then vim.t.term_height = previous_height; return end
	state.set_toggling()
	window.close_pane_windows()
	local order = state.get_term_order()
	order[tab_idx].layout = layout
	state.set_term_order(order)
	vim.t.term_drawer_size = nil
	window.reopen_current_tab(tab_idx)
	vim.t.term_height = state.drawer_span() or layout.h
end

-- Resize the current pane in one dimension via vim's frame cascade.
-- dim: "w" (CTRL-W < >) or "h" (CTRL-W + -).
-- Width resize in drawer mode stays native (vim-exact, cannot move the
-- drawer boundary). Heights redistribute first; drawers grow only when the
-- remaining panes cannot give up more space. Floats retain their outer size.
function M.resize(delta, dim)
	dim = dim or "w"
	if not config.is_float_mode() and dim == "h" then
		set_drawer_pane_height(vim.api.nvim_win_get_height(0) + delta)
		return
	end

	if not config.is_float_mode() and dim == "w" then
		local amount = math.abs(delta)
		vim.cmd(amount .. "wincmd " .. (delta > 0 and ">" or "<"))
		return
	end

	local tab, tab_idx = state.get_current_tab()
	if not tab or #tab.bufs < 2 then
		return
	end
	local bufnr = vim.api.nvim_get_current_buf()
	if not state.find_buf_tab(bufnr) then
		return
	end

	window.save_layout_sizes()
	local order = state.get_term_order()
	local entry = order[tab_idx]
	local path = frame.find(entry.layout, bufnr)
	if not path then
		return
	end
	local cur = path[#path].node[dim]
	frame.set_size(entry.layout, bufnr, dim, cur + delta)
	state.set_term_order(order)

	float_layout.apply_layout(entry)
end

-- Set the current pane to an absolute size (CTRL-W _ / |). size nil means
-- maximize within the terminal area (vim's behavior scoped to the drawer or
-- float, not the whole screen).
function M.set_size(dim, size)
	if dim == "h" and size and not config.is_float_mode() then
		set_drawer_pane_height(size)
		return
	end
	local tab, tab_idx = state.get_current_tab()
	if not tab or #tab.bufs < 2 then
		return
	end
	local bufnr = vim.api.nvim_get_current_buf()
	if not state.find_buf_tab(bufnr) then
		return
	end

	window.save_layout_sizes()
	local order = state.get_term_order()
	local entry = order[tab_idx]
	if not size then
		size = entry.layout[dim] -- clamped by the cascade to what's available
	end
	frame.set_size(entry.layout, bufnr, dim, size)
	state.set_term_order(order)

	if config.is_float_mode() then
		float_layout.apply_layout(entry)
	else
		window.apply_drawer_sizes(entry)
	end
end

-- Both the terminal prefix's {height}<CR> and Vim's z{height}<CR> size the
-- focused pane. Drawers grow on overflow; floats retain their outer size.
function M.set_height(n)
	if n < 1 then
		return
	end
	M.set_size("h", n)
end

-- Shared prologue/epilogue for structural tree operations that rebuild the
-- pane windows (rotate, exchange, splitmove).
local function structural_op(fn)
	local tab, tab_idx = state.get_current_tab()
	if not tab or #tab.bufs < 2 then
		return
	end
	local bufnr = vim.api.nvim_get_current_buf()
	if not state.find_buf_tab(bufnr) then
		return
	end

	-- Probe on a throwaway copy so errors (E443) surface before any windows
	-- are touched.
	local probe = state.get_term_order()[tab_idx]
	local probe_ok, probe_err = fn(probe, bufnr, true)
	if not probe_ok then
		if probe_err then
			-- Shown as an error like vim's E443; a low-key notify is easy to
			-- miss under the float (or with the cmdline hidden in zoom)
			vim.notify(probe_err, vim.log.levels.ERROR)
		end
		return
	end

	if not window.check_size(probe) then return end
	state.set_toggling()
	window.save_tab_state()
	local order = state.get_term_order()
	local previous = vim.deepcopy(order)
	window.close_pane_windows()

	local entry = order[tab_idx]
	fn(entry, bufnr, false)
	state.sync_bufs(entry)
	state.set_term_order(order)

	local ok, result = pcall(window.reopen_current_tab, tab_idx)
	if not ok or not result then
		state.set_term_order(previous)
		local reason = ok and "Terminal layout could not be opened" or tostring(result)
		vim.notify(window.recover_tab(reason), vim.log.levels.ERROR)
	end
end

-- CTRL-W r / R: rotate the sibling slots of the current pane's parent frame.
-- Buffers move through fixed slots; focus follows the current buffer (vim).
function M.rotate(direction, count)
	structural_op(function(entry, bufnr)
		local root, err = frame.rotate(entry.layout, bufnr, direction < 0, count or 1)
		if err then
			return false, err:match("E443") and err or nil
		end
		entry.layout = root
		entry.focus = bufnr
		return true
	end)
end

-- CTRL-W x: exchange the current pane with the count'th (or next) sibling.
-- Focus stays in the same fixed-size slot, which now shows the other buffer.
function M.exchange(count)
	structural_op(function(entry, bufnr)
		local root, other = frame.exchange(entry.layout, bufnr, count)
		if not other then
			return false
		end
		entry.layout = root
		entry.focus = other
		return true
	end)
end

-- CTRL-W H/J/K/L: move the current pane to an edge of the layout as a
-- full-height (left/right) or full-width (top/bottom) pane.
function M.splitmove(edge)
	structural_op(function(entry, bufnr)
		entry.layout = frame.splitmove(entry.layout, bufnr, edge)
		-- Edge moves change the split topology; distribute the existing
		-- workspace evenly instead of preserving the moved pane's old size.
		local layout = entry.layout
		if frame.fits(layout, layout.w, layout.h) then
			frame.equalize(layout, layout.w, layout.h)
		end
		entry.focus = bufnr
		return true
	end)
end

return M
