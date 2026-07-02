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

-- Resize the current pane in one dimension via vim's frame cascade.
-- dim: "w" (CTRL-W < >) or "h" (CTRL-W + -).
-- Width resize in drawer mode stays native (vim-exact, cannot move the
-- drawer boundary). Height resize always goes through the tree: the total is
-- preserved, so the drawer keeps its height instead of growing into the
-- editor area.
function M.resize(delta, dim)
	dim = dim or "w"

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
	vim.t.term_order = order

	float_layout.apply_layout(entry)
end

-- Set the current pane to an absolute size (CTRL-W _ / |). size nil means
-- maximize within the terminal area (vim's behavior scoped to the drawer or
-- float, not the whole screen).
function M.set_size(dim, size)
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
	vim.t.term_order = order

	if config.is_float_mode() then
		float_layout.apply_layout(entry)
	else
		window.apply_drawer_sizes(entry)
	end
end

-- vim's z{height}<CR>: set the current pane's height. A pane spanning the
-- full drawer height (or a single pane) moves the drawer boundary — what vim
-- would do to the window; a stacked pane redistributes within the drawer.
function M.set_height(n)
	if n < 1 then
		return
	end
	if config.is_float_mode() then
		M.set_size("h", n)
		return
	end
	local tab = state.get_current_tab()
	local span = state.drawer_span()
	local cur = vim.api.nvim_win_get_height(0)
	if not tab or #tab.bufs < 2 or (span and cur >= span) then
		window.set_drawer_height(n)
	else
		M.set_size("h", n)
	end
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

	state.set_toggling()
	window.save_tab_state()
	window.save_layout_sizes()
	window.close_pane_windows()

	local order = state.get_term_order()
	local entry = order[tab_idx]
	fn(entry, bufnr, false)
	state.sync_bufs(entry)
	vim.t.term_order = order

	window.reopen_current_tab(tab_idx)
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
-- Focus stays in the same screen slot, which now shows the other buffer.
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
		entry.focus = bufnr
		return true
	end)
end

return M
