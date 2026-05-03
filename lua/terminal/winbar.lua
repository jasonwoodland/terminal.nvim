-- terminal.nvim: floating winbar overlay

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")

local winbar_bufnr = nil
local winbar_ns = vim.api.nvim_create_namespace("terminal_winbar")
local winbar_click_ranges = {}

vim.api.nvim_set_hl(0, "TerminalWinBarNoSearch", {})

function M.get_click_ranges()
	return winbar_click_ranges
end

local function get_winbar_title(tab)
	local buf = tab[1]
	local title = vim.b[buf].term_title or vim.api.nvim_buf_get_name(buf)
	title = vim.fn.substitute(title, "\\v([^/~ ]+)/", "\\=strpart(submatch(1), 0, 1) . '/'", "g")
	return title
end

local function render_winbar_content()
	if not winbar_bufnr or not vim.api.nvim_buf_is_valid(winbar_bufnr) then
		return
	end

	local tabs = state.get_tabs()
	local current_idx = vim.t.term_tab_idx or 1

	-- Always clear activity for the current tab
	local activity = vim.t.term_tab_activity or {}
	activity[tostring(current_idx)] = nil
	vim.t.term_tab_activity = activity

	vim.api.nvim_buf_clear_namespace(winbar_bufnr, winbar_ns, 0, -1)
	winbar_click_ranges = {}

	local parts = {}
	local byte_offset = 0

	for i, tab in ipairs(tabs) do
		local title = get_winbar_title(tab)
		local tab_activity = vim.t.term_tab_activity or {}
		local has_activity = i ~= current_idx and tab_activity[tostring(i)] or false
		local label = " " .. i .. ":" .. title .. (has_activity and "*" or "") .. " "
		if #tab > 1 then
			label = label .. "[" .. #tab .. "] "
		end

		local start_col = byte_offset
		local end_col = byte_offset + #label

		table.insert(parts, label)
		table.insert(winbar_click_ranges, { tab_idx = i, start_col = start_col, end_col = end_col })

		byte_offset = end_col
	end

	local line = table.concat(parts)
	vim.api.nvim_buf_set_lines(winbar_bufnr, 0, -1, false, { line })

	for _, range in ipairs(winbar_click_ranges) do
		local hl = range.tab_idx == current_idx and "WinBarActive" or "WinBar"
		vim.api.nvim_buf_set_extmark(winbar_bufnr, winbar_ns, 0, range.start_col, {
		hl_group = hl,
		end_col = range.end_col,
	})
	end
end

function M.get_term_windows()
	local tab = state.get_current_tab()
	if not tab then
		return {}
	end

	local tab_bufs = {}
	for _, buf in ipairs(tab) do
		tab_bufs[buf] = true
	end

	local wins = {}
	local float_mode = config.is_float_mode()

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if tab_bufs[buf] then
				local win_config = vim.api.nvim_win_get_config(win)
				local is_float = win_config.relative and win_config.relative ~= ""
				if (float_mode and is_float) or (not float_mode and not is_float) then
					if win ~= vim.t.term_winbar_winid then
						table.insert(wins, win)
					end
				end
			end
		end
	end

	table.sort(wins, function(a, b)
		local pos_a = vim.api.nvim_win_get_position(a)
		local pos_b = vim.api.nvim_win_get_position(b)
		return pos_a[2] < pos_b[2]
	end)

	return wins
end

local function get_winbar_overlay_config()
	local wins = vim.t.term_winids or {}
	if #wins == 0 then
		return nil
	end

	local first_win = nil
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			first_win = win
			break
		end
	end
	if not first_win then
		return nil
	end

	local pos = vim.api.nvim_win_get_position(first_win)
	local row = pos[1]
	local col = pos[2]

	local total_width = 0
	local valid_count = 0
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			total_width = total_width + vim.api.nvim_win_get_width(win)
			valid_count = valid_count + 1
		end
	end
	if valid_count > 1 then
		total_width = total_width + (valid_count - 1)
	end

	if total_width <= 0 then
		return nil
	end

	if config.is_float_mode() then
		return {
			relative = "editor",
			row = row,
			col = col,
			width = total_width,
			height = 1,
			style = "minimal",
			border = "none",
			zindex = 40,
			focusable = true,
		}
	else
		return {
			relative = "win",
			win = first_win,
			row = -1,
			col = 0,
			width = total_width,
			height = 1,
			style = "minimal",
			border = "none",
			zindex = 1,
			focusable = true,
		}
	end
end

function M.update()
	if not config.config.winbar then
		return
	end

	local tabs = state.get_tabs()
	if #tabs == 0 then
		M.destroy()
		return
	end

	local wins = vim.t.term_winids or {}
	local any_open = false
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			any_open = true
			break
		end
	end
	if not any_open then
		M.destroy()
		return
	end

	if not winbar_bufnr or not vim.api.nvim_buf_is_valid(winbar_bufnr) then
		winbar_bufnr = vim.api.nvim_create_buf(false, true)
		vim.bo[winbar_bufnr].bufhidden = "hide"
		vim.bo[winbar_bufnr].buftype = "nofile"
	end

	render_winbar_content()

	local cfg = get_winbar_overlay_config()
	if not cfg then
		M.destroy()
		return
	end

	local winbar_winid = vim.t.term_winbar_winid
	if state.win_valid(winbar_winid) then
		vim.api.nvim_win_set_config(winbar_winid, cfg)
		vim.api.nvim_win_set_buf(winbar_winid, winbar_bufnr)
	else
		winbar_winid = vim.api.nvim_open_win(winbar_bufnr, false, cfg)
		vim.t.term_winbar_winid = winbar_winid
	end
	vim.wo[winbar_winid].winhighlight =
		"Normal:WinBar,Search:TerminalWinBarNoSearch,IncSearch:TerminalWinBarNoSearch,CurSearch:TerminalWinBarNoSearch"
	vim.wo[winbar_winid].winblend = 0
	vim.wo[winbar_winid].cursorline = false
	vim.wo[winbar_winid].number = false
	vim.wo[winbar_winid].relativenumber = false
	vim.wo[winbar_winid].signcolumn = "no"
end

function M.destroy()
	local winbar_winid = vim.t.term_winbar_winid
	if winbar_winid and vim.api.nvim_win_is_valid(winbar_winid) then
		vim.api.nvim_win_close(winbar_winid, true)
	end
	vim.t.term_winbar_winid = nil
end

return M
