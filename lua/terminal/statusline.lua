-- terminal.nvim: float statusline overlays

local M = {}

local state = require("terminal.state")

local stl_ns = vim.api.nvim_create_namespace("terminal_stl")
local _stl_cache = {} -- [tabpage] = { [pane_win] = { stl_win, stl_buf } }

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

local function cleanup_invalid_tab_caches()
	for tabpage in pairs(_stl_cache) do
		if not vim.api.nvim_tabpage_is_valid(tabpage) then
			_stl_cache[tabpage] = nil
		end
	end
end

function M.close(tabpage)
	tabpage = tabpage or vim.api.nvim_get_current_tabpage()

	local cache = _stl_cache[tabpage]
	if cache then
		for _, entry in pairs(cache) do
			if vim.api.nvim_win_is_valid(entry.stl_win) then
				pcall(vim.api.nvim_win_close, entry.stl_win, true)
			end
		end
		_stl_cache[tabpage] = nil
	end

	-- Catch any orphaned stl windows not tracked by the cache.
	if vim.api.nvim_tabpage_is_valid(tabpage) then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
			if ok and vim.b[buf].terminal_stl then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end
	end

	cleanup_invalid_tab_caches()
end

function M.is_stl_window(winid)
	local ok, buf = pcall(vim.api.nvim_win_get_buf, winid)
	return ok and vim.b[buf].terminal_stl or false
end

function M.update()
	cleanup_invalid_tab_caches()

	local tabpage = vim.api.nvim_get_current_tabpage()
	if not vim.t.term_zoom then
		M.close(tabpage)
		return
	end

	local wins = vim.t.term_winids or {}
	if #wins == 0 then
		M.close(tabpage)
		return
	end

	local current_win = vim.api.nvim_get_current_win()
	local cache = _stl_cache[tabpage] or {}
	local new_cache = {}

	for idx, win in ipairs(wins) do
		if not state.win_valid(win) then
			goto continue
		end

		local cfg = vim.api.nvim_win_get_config(win)
		if not cfg.relative or cfg.relative == "" then
			goto continue
		end

		local width = vim.api.nvim_win_get_width(win)
		local stl_row = cfg.row + cfg.height
		local has_right = idx < #wins
		local stl_col = cfg.col + ((idx > 1 and #wins > 1) and 1 or 0)
		local stl_width = width + (has_right and 1 or 0)
		local hl = (win == current_win) and "Normal:StatusLine" or "Normal:StatusLineNC"

		local entry = cache[win]
		local stl_win, stl_buf

		if entry
			and vim.api.nvim_win_is_valid(entry.stl_win)
			and vim.api.nvim_buf_is_valid(entry.stl_buf)
		then
			stl_win = entry.stl_win
			stl_buf = entry.stl_buf
			vim.api.nvim_win_set_config(stl_win, {
				relative = "editor",
				row = stl_row,
				col = stl_col,
				width = stl_width,
				height = 1,
			})
		else
			stl_buf = vim.api.nvim_create_buf(false, true)
			vim.bo[stl_buf].bufhidden = "wipe"
			vim.bo[stl_buf].buftype = "nofile"
			vim.b[stl_buf].terminal_stl = true
			vim.b[stl_buf].terminal_stl_pane = win
			stl_win = vim.api.nvim_open_win(stl_buf, false, {
				relative = "editor",
				row = stl_row,
				col = stl_col,
				width = stl_width,
				height = 1,
				style = "minimal",
				border = "none",
				zindex = 41,
				focusable = true,
			})
			vim.wo[stl_win].winblend = 0
			vim.wo[stl_win].cursorline = false
		end

		render_stl_overlay(stl_buf, win, width, has_right)
		vim.wo[stl_win].winhighlight = hl
		new_cache[win] = { stl_win = stl_win, stl_buf = stl_buf }

		::continue::
	end

	for pane_win, entry in pairs(cache) do
		if not new_cache[pane_win] and vim.api.nvim_win_is_valid(entry.stl_win) then
			pcall(vim.api.nvim_win_close, entry.stl_win, true)
		end
	end

	_stl_cache[tabpage] = new_cache
end

return M
