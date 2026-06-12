-- terminal.nvim: pane operations (navigate, cycle, resize, move, rotate)

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
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

function M.navigate(delta, count)
	if not config.is_float_mode() then
		M.native_wincmd(delta < 0 and "h" or "l", count)
		return
	end

	local wins = vim.t.term_winids or {}
	local current = vim.api.nvim_get_current_win()
	for i, win in ipairs(wins) do
		if win == current then
			local target = i + delta
			if target >= 1 and target <= #wins and state.win_valid(wins[target]) then
				focus_pane_win(wins[target])
			end
			return
		end
	end
end

function M.cycle(count)
	if not config.is_float_mode() then
		M.native_wincmd("w", count)
		return
	end

	local wins = vim.t.term_winids or {}
	if #wins < 2 then
		return
	end
	local current = vim.api.nvim_get_current_win()
	for i, win in ipairs(wins) do
		if win == current then
			local target = (i % #wins) + 1
			if state.win_valid(wins[target]) then
				focus_pane_win(wins[target])
			end
			return
		end
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

function M.resize(delta)
	local wins = vim.t.term_winids or {}
	local current = vim.api.nvim_get_current_win()

	if not config.is_float_mode() then
		if delta > 0 then
			vim.cmd(delta .. "wincmd >")
		else
			vim.cmd((-delta) .. "wincmd <")
		end
		return
	end

	local pane_idx
	for i, win in ipairs(wins) do
		if win == current then
			pane_idx = i
			break
		end
	end
	if not pane_idx or #wins < 2 then
		return
	end

	local widths = {}
	for i, win in ipairs(wins) do
		if state.win_valid(win) then
			widths[i] = vim.api.nvim_win_get_width(win)
		else
			return
		end
	end

	local new_widths = float_layout.calc_resized_widths(widths, pane_idx, delta)
	float_layout.apply_float_pane_layout(new_widths)
	float_layout.save_pane_widths()
end

function M.move_to(target_pos)
	local tab, tab_idx = state.get_current_tab()
	if not tab or #tab.bufs < 2 then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local _, pane_idx = state.find_buf_tab(bufnr)
	if not pane_idx then
		return
	end
	if target_pos == 1 and pane_idx == 1 then
		return
	end
	if target_pos == #tab.bufs and pane_idx == #tab.bufs then
		return
	end

	state.set_toggling()
	window.save_tab_state()
	window.close_pane_windows()

	local order = state.get_term_order()
	local entry = order[tab_idx]
	table.remove(entry.bufs, pane_idx)
	table.insert(entry.bufs, target_pos, bufnr)
	entry.widths = nil
	entry.focus = target_pos
	vim.t.term_order = order

	window.reopen_current_tab(tab_idx)
end

function M.rotate(direction)
	local tab, tab_idx = state.get_current_tab()
	if not tab or #tab.bufs < 2 then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local _, pane_idx = state.find_buf_tab(bufnr)
	if not pane_idx then
		return
	end

	state.set_toggling()

	window.save_tab_state()
	window.close_pane_windows()

	local order = state.get_term_order()
	local entry = order[tab_idx]
	local bufs = entry.bufs
	if direction > 0 then
		local last = table.remove(bufs)
		table.insert(bufs, 1, last)
	else
		local first = table.remove(bufs, 1)
		table.insert(bufs, first)
	end

	local new_pane_idx
	for i, buf in ipairs(bufs) do
		if buf == bufnr then
			new_pane_idx = i
			break
		end
	end

	entry.widths = nil
	entry.focus = new_pane_idx or 1
	vim.t.term_order = order

	window.reopen_current_tab(tab_idx)
end

return M
