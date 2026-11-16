-- Capture caller focus and recover it after pane windows are replaced.
local M = {}
local state = require("terminal.state")
local mode = require("terminal.mode")

function M.capture()
	return {
		tab = vim.api.nvim_get_current_tabpage(), win = vim.api.nvim_get_current_win(),
		buf = vim.api.nvim_get_current_buf(), mode = vim.api.nvim_get_mode().mode,
		managed = state.is_managed(),
	}
end

function M.restore(saved, deferred)
	if not vim.api.nvim_tabpage_is_valid(saved.tab) then return false end
	local win = saved.win
	if not state.win_valid(win) or vim.api.nvim_win_get_buf(win) ~= saved.buf then
		win = nil
		for _, candidate in ipairs(vim.t[saved.tab].term_winids or {}) do
			if state.win_valid(candidate) and vim.api.nvim_win_get_buf(candidate) == saved.buf then win = candidate; break end
		end
	end
	if not win then
		if vim.api.nvim_get_current_tabpage() ~= saved.tab then vim.api.nvim_set_current_tabpage(saved.tab) end
		return false
	end
	vim.api.nvim_set_current_win(win)
	if state.is_managed() then
		local saved_mode = saved.mode == "t" and "t" or "n"
		if deferred then mode.restore_scheduled(win, saved_mode) else mode.restore(win, saved_mode) end
	else
		vim.cmd((saved.mode == "t" or saved.mode:sub(1, 1) == "i") and "startinsert" or "stopinsert")
	end
	return true
end

return M
