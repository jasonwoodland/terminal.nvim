-- terminal.nvim: terminal-mode tracking and restoration
--
-- Each terminal buffer remembers whether the user last interacted with it in
-- terminal-insert mode ("t") or normal mode ("n") via b:term_mode. Everything
-- that moves focus between panes/tabs funnels through this module so the mode
-- the user left a terminal in is the mode they come back to.

local M = {}

local state = require("terminal.state")

local function term_bufnr_of_win(winid)
	if not state.win_valid(winid) then
		return nil
	end
	local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
	if not ok or not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "terminal" then
		return nil
	end
	return bufnr
end

-- Record the current buffer's mode in b:term_mode. Returns the recorded mode,
-- or nil when the current buffer is not a terminal.
function M.record()
	local bufnr = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "terminal" then
		return nil
	end

	local mode = vim.api.nvim_get_mode().mode == "t" and "t" or "n"
	vim.b[bufnr].term_mode = mode
	return mode
end

-- b:term_mode of the terminal buffer shown in winid, or nil.
function M.of_win(winid)
	local bufnr = term_bufnr_of_win(winid)
	if not bufnr then
		return nil
	end
	return vim.b[bufnr].term_mode
end

-- Enter/leave terminal-insert for an already-focused window. nil counts as
-- "t" (a terminal the user never left insert in).
function M.apply(mode)
	if mode == "t" or mode == nil then
		vim.cmd("startinsert")
	else
		vim.cmd("stopinsert")
	end
end

-- Restore `mode` (default: the buffer's saved b:term_mode) in winid, which is
-- expected to be the current window. No-op for non-terminal windows.
function M.restore(winid, mode)
	local bufnr = term_bufnr_of_win(winid)
	if not bufnr then
		return
	end

	local restore_mode = mode or vim.b[bufnr].term_mode
	if restore_mode == "t" or restore_mode == nil then
		vim.b[bufnr].term_mode = "t"
		vim.cmd("startinsert")
	else
		vim.b[bufnr].term_mode = "n"
		vim.cmd("stopinsert")
	end
end

-- Like restore(), but startinsert is deferred a tick and re-validated, for
-- callers running inside autocmds where focus may still move (e.g. overlay
-- refocus handlers).
function M.restore_scheduled(winid, mode)
	local bufnr = term_bufnr_of_win(winid)
	if not bufnr then
		return
	end

	local restore_mode = mode or vim.b[bufnr].term_mode
	if restore_mode == "t" or restore_mode == nil then
		vim.b[bufnr].term_mode = "t"
		vim.schedule(function()
			if not state.win_valid(winid) or vim.api.nvim_get_current_win() ~= winid then
				return
			end

			local ok_current, current_buf = pcall(vim.api.nvim_win_get_buf, winid)
			if ok_current and current_buf == bufnr then
				vim.cmd("startinsert")
			end
		end)
	else
		vim.b[bufnr].term_mode = "n"
		vim.cmd("stopinsert")
	end
end

-- Restore the current buffer's saved mode; leaves insert when focus landed on
-- a non-terminal buffer.
function M.restore_current()
	if vim.bo.buftype ~= "terminal" then
		vim.cmd("stopinsert")
	elseif vim.b.term_mode == "t" or vim.b.term_mode == nil then
		vim.cmd("startinsert")
	else
		vim.cmd("stopinsert")
	end
end

return M
