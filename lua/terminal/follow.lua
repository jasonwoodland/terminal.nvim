-- Keep inactive Terminal-mode panes on the live screen without changing focus.
local M = {}
local pending = false
local attached = {}

function M.schedule()
	if pending then return end
	pending = true
	vim.schedule(function()
		pending = false
		local current = vim.api.nvim_get_current_win()
		for _, win in ipairs(vim.t.term_winids or {}) do
			if win ~= current and vim.api.nvim_win_is_valid(win) then
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].buftype == "terminal" and vim.b[buf].term_mode == "t" then
					-- The terminal screen is the final window-height lines of the
					-- buffer, including blank rows below the application's cursor.
					-- Keep the buffer cursor within that screen without forcing it
					-- to the last row: its position also guides native pane navigation.
					local last = vim.api.nvim_buf_line_count(buf)
					-- Window height includes the row reserved for the winbar.
					local height = vim.api.nvim_win_get_height(win) - (vim.wo[win].winbar ~= "" and 1 or 0)
					local top = math.max(1, last - height + 1)
					local cursor = vim.api.nvim_win_get_cursor(win)
					if cursor[1] < top then
						vim.api.nvim_win_set_cursor(win, { top, cursor[2] })
					end
					vim.api.nvim_win_call(win, function()
						vim.fn.winrestview({ topline = top, leftcol = 0 })
					end)
				end
			end
		end
	end)
end

function M.attach(buf)
	if attached[buf] then return end
	attached[buf] = vim.api.nvim_buf_attach(buf, false, {
		on_lines = function() M.schedule() end,
		on_detach = function() attached[buf] = nil end,
	}) or nil
end

return M
