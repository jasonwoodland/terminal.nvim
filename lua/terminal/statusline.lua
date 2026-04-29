-- terminal.nvim: float statusline overlays

local M = {}

local state = require("terminal.state")

local stl_ns = vim.api.nvim_create_namespace("terminal_stl")

local function render_stl_overlay(stl_buf, win, width, pad_right)
	local stl = vim.wo[win].statusline
	if stl == "" then
		stl = vim.o.statusline
	end
	if stl == "" then
		stl = "%f"
	end

	local ok, result = pcall(vim.api.nvim_eval_statusline, stl, {
		winid = win,
		maxwidth = width,
		highlights = true,
	})
	if not ok or not result then
		return
	end

	local line = result.str
	if pad_right then
		line = line .. " "
	end

	vim.api.nvim_buf_clear_namespace(stl_buf, stl_ns, 0, -1)
	vim.api.nvim_buf_set_lines(stl_buf, 0, -1, false, { line })

	for i, hl in ipairs(result.highlights) do
		local end_pos = (result.highlights[i + 1] and result.highlights[i + 1].start) or #result.str
		if hl.group and hl.group ~= "" then
			vim.api.nvim_buf_set_extmark(stl_buf, stl_ns, 0, hl.start, {
		hl_group = hl.group,
		end_col = end_pos,
	})
		end
	end
end

function M.close()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
		if ok and vim.b[buf].terminal_stl then
			vim.api.nvim_win_close(win, true)
		end
	end
end

function M.is_stl_window(winid)
	local ok, buf = pcall(vim.api.nvim_win_get_buf, winid)
	return ok and vim.b[buf].terminal_stl or false
end

function M.update()
	if not vim.t.term_zoom then
		M.close()
		return
	end
	local wins = vim.t.term_winids or {}
	if #wins == 0 then
		M.close()
		return
	end

	M.close()

	local current_win = vim.api.nvim_get_current_win()

	for _, win in ipairs(wins) do
		if not state.win_valid(win) then
			goto continue
		end

		local cfg = vim.api.nvim_win_get_config(win)
		if not cfg.relative or cfg.relative == "" then
			goto continue
		end

		local width = vim.api.nvim_win_get_width(win)
		local stl_row = cfg.row + cfg.height
		local idx
		for j, w in ipairs(wins) do
			if w == win then
				idx = j
				break
			end
		end
		local has_right = idx and idx < #wins
		local stl_col = cfg.col + ((idx and idx > 1 and #wins > 1) and 1 or 0)
		local stl_width = width + (has_right and 1 or 0)
		local hl = (win == current_win) and "Normal:StatusLine" or "Normal:StatusLineNC"

		local stl_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[stl_buf].bufhidden = "wipe"
		vim.bo[stl_buf].buftype = "nofile"
		vim.b[stl_buf].terminal_stl = true
		vim.b[stl_buf].terminal_stl_pane = win
		render_stl_overlay(stl_buf, win, width, has_right)
		local stl_win = vim.api.nvim_open_win(stl_buf, false, {
			relative = "editor",
			row = stl_row,
			col = stl_col,
			width = stl_width,
			height = 1,
			style = "minimal",
			border = "none",
			zindex = 61,
			focusable = true,
		})
		vim.wo[stl_win].winhighlight = hl
		vim.wo[stl_win].winblend = 0
		vim.wo[stl_win].cursorline = false

		::continue::
	end
end

return M
