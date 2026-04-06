-- terminal.nvim: window management

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local winbar = require("terminal.winbar")
local statusline = require("terminal.statusline")

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
		border = "rounded",
	}

	if type(config.config.float) == "table" then
		float_config = vim.tbl_extend("force", float_config, config.config.float)
	end

	local col = float_config.padding.x
	local row = float_config.padding.y
	local border_width = float_config.border == "none" and 0 or 2
	local width = math.floor(vim.o.columns - float_config.padding.x * 2 - border_width)
	local height = math.floor(vim.o.lines - float_config.padding.y * 2 - border_width - 2)

	return {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = float_config.border,
		title = " Terminal ",
		title_pos = "center",
	}
end

local function open_window(win_config)
	local scratch = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(scratch, true, win_config)
	return win, scratch
end

-- Open a terminal in a temporary window so the PTY starts with correct
-- dimensions instead of the tiny aucmd window used by nvim_buf_call.
-- num_panes: how many panes will share the row/float (for width calculation)
function M.termopen_with_size(bufnr, num_panes)
	num_panes = math.max(num_panes or 1, 1)
	local width = 80
	local height = math.floor(vim.o.lines * 0.5)

	if config.is_float_mode() then
		local cfg = M.get_float_win_config()
		width = cfg.width
		if num_panes > 1 then
			-- Subtract separator columns, then divide evenly
			width = math.floor((width - (num_panes - 1)) / num_panes)
		end
		height = cfg.height
		if config.config.winbar then
			height = height - 1
		end
	else
		local h = vim.t.term_height or config.get_term_height()
		height = h
		if config.config.winbar then
			height = height - 1
		end
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
	vim.fn.termopen(vim.env.SHELL)
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
		widths = prev_state.widths,
		focus = 1,
		modes = {},
	}

	local current_win = vim.fn.win_getid()
	for i, win in ipairs(wins) do
		if state.win_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			st.modes[i] = vim.b[buf].term_mode or "t"
			if win == current_win then
				st.focus = i
			end
		end
	end

	state.set_tab_state(tab_idx, st)
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

	local wins = vim.t.term_winids or {}
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			local cfg = vim.api.nvim_win_get_config(win)
			if cfg.relative and cfg.relative ~= "" then
				vim.api.nvim_win_close(win, true)
			else
				if vim.fn.win_getid() == win then
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

function M.open_tab_windows(tab, tab_idx)
	if not tab or #tab == 0 then
		return
	end

	if vim.t.term_zoom then
		state.set_zoom_cmdheight()
		state.set_zoom_ruler()
	end

	local st = state.get_tab_state(tab_idx)

	local wins = {}
	local scratches = {}
	local height = vim.t.term_height or config.get_term_height()

	local has_stl = false
	local focus_idx = state.clamp(st.focus or 1, 1, #tab)

	if config.is_float_mode() then
		local base_config = M.get_float_win_config()
		local num_panes = #tab
		local total_width = base_config.width

		-- Calculate pane widths
		local pane_widths = {}
		local content_available = total_width - (num_panes - 1)
		if st.widths and #st.widths == num_panes then
			local sum = 0
			for i = 1, num_panes do
				sum = sum + (st.widths[i] or 1)
			end
			if sum == content_available then
				for i = 1, num_panes do
					pane_widths[i] = st.widths[i]
				end
			else
				local allocated = 0
				for i = 1, num_panes - 1 do
					pane_widths[i] = math.max(3, math.floor((st.widths[i] or 1) * content_available / sum))
					allocated = allocated + pane_widths[i]
				end
				pane_widths[num_panes] = math.max(3, content_available - allocated)
			end
		else
			local base_w = math.floor(content_available / num_panes)
			local extra = content_available - base_w * num_panes
			for i = 1, num_panes do
				pane_widths[i] = base_w + (i <= extra and 1 or 0)
			end
		end

		-- Create pane windows
		has_stl = vim.t.term_zoom and true or false
		local stl_height = has_stl and 1 or 0
		local col_offset = 0
		local fillchar = vim.opt.fillchars:get().vert or "\xe2\x94\x82"
		for i in ipairs(tab) do
			local has_left = (i > 1)
			local has_right = (i < num_panes)
			local border = "none"
			if has_left or has_right then
				border = {
					"",
					"",
					"",
					has_right and { fillchar, "WinSeparator" } or "",
					"",
					"",
					"",
					has_left and { fillchar, "WinSeparator" } or "",
				}
			end

			local win_cfg = vim.tbl_extend("force", {}, base_config)
			win_cfg.width = pane_widths[i]
			win_cfg.height = base_config.height - stl_height
			win_cfg.row = base_config.row
			win_cfg.col = base_config.col + col_offset
			win_cfg.border = border
			win_cfg.zindex = (i == focus_idx) and 51 or 50

			-- Advance col_offset past this pane
			if i == 1 then
				col_offset = col_offset + pane_widths[i]
			else
				col_offset = col_offset + 1 + pane_widths[i]
			end

			local win, scratch = open_window(win_cfg)
			table.insert(wins, win)
			table.insert(scratches, scratch)
		end
	else
		local first_win, first_scratch = open_window({
			split = "below",
			win = -1,
			height = height,
		})
		vim.cmd("set wfh")
		table.insert(wins, first_win)
		table.insert(scratches, first_scratch)

		for i = 2, #tab do
			local prev_win = wins[i - 1]
			local win, scratch = open_window({
				split = "right",
				win = prev_win,
			})
			table.insert(wins, win)
			table.insert(scratches, scratch)
		end

		if #wins > 1 then
			local widths
			if st.widths and #st.widths == #wins then
				widths = st.widths
			else
				local total = 0
				for _, win in ipairs(wins) do
					total = total + vim.api.nvim_win_get_width(win)
				end
				widths = state.compute_equal_widths(total, #wins)
			end
			for i, win in ipairs(wins) do
				if widths[i] and state.win_valid(win) then
					vim.api.nvim_win_set_width(win, widths[i])
				end
			end
		end
	end

	-- Set window options on the scratch windows BEFORE attaching terminal
	-- buffers. nvim_win_set_buf calls get_winopts() which restores the
	-- buffer's saved w_onebuf_opt. If those match what we set here, the
	-- terminal sees no dimension change at attachment time.
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			vim.wo[win].signcolumn = "no"
			vim.wo[win].foldcolumn = "0"
			vim.wo[win].number = false
			vim.wo[win].relativenumber = false
			vim.wo[win].scrolloff = 0
			vim.wo[win].sidescrolloff = 0
			vim.wo[win].winblend = 0
			vim.wo[win].cursorline = false
			vim.wo[win].cursorcolumn = false
			vim.wo[win].spell = false
			vim.wo[win].list = false
			vim.wo[win].colorcolumn = ""
			vim.wo[win].statuscolumn = ""
			vim.wo[win].fillchars = "eob: "
			vim.wo[win].winhighlight = "EndOfBuffer:"
			if config.config.winbar then
				vim.wo[win].winbar = " "
			end
		end
	end

	-- Attach terminal buffers. get_winopts() may overwrite some options
	-- from the buffer's WinInfo, so re-set them afterward.
	local old_eventignore = vim.o.eventignore
	vim.o.eventignore = "BufEnter,BufLeave,BufWinEnter"
	for i, win in ipairs(wins) do
		if state.win_valid(win) then
			vim.api.nvim_win_set_buf(win, tab[i])
			vim.wo[win].signcolumn = "no"
			vim.wo[win].foldcolumn = "0"
			vim.wo[win].number = false
			vim.wo[win].relativenumber = false
			vim.wo[win].scrolloff = 0
			vim.wo[win].sidescrolloff = 0
			if config.config.winbar then
				vim.wo[win].winbar = " "
			end
		end
	end
	vim.o.eventignore = old_eventignore

	-- Force correct PTY dimensions after all window options are finalized.
	-- nvim_win_set_buf may report stale dimensions to the PTY before
	-- winbar/signcolumn/etc. are re-applied.
	if vim.t.term_zoom then
		for i, win in ipairs(wins) do
			if state.win_valid(win) then
				local job_id = vim.b[tab[i]].terminal_job_id
				if job_id then
					pcall(vim.fn.jobresize, job_id, vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win))
				end
			end
		end
	end

	for _, scratch in ipairs(scratches) do
		if vim.api.nvim_buf_is_valid(scratch) then
			vim.api.nvim_buf_delete(scratch, { force = true })
		end
	end

	focus_idx = state.clamp(focus_idx, 1, #wins)

	if wins[focus_idx] and state.win_valid(wins[focus_idx]) then
		vim.api.nvim_set_current_win(wins[focus_idx])
	end

	vim.t.term_winids = wins
	vim.t.term_winid = wins[focus_idx] or wins[1]
	vim.t.term_bufnr = tab[focus_idx] or tab[1]
	vim.t.term_tab_idx = tab_idx

	-- Clear activity flag now that term_tab_idx is set
	local activity = vim.t.term_tab_activity or {}
	activity[tostring(tab_idx)] = nil
	vim.t.term_tab_activity = activity

	local mode_to_restore = "t"
	if st.modes and st.modes[focus_idx] then
		mode_to_restore = st.modes[focus_idx]
	end
	if mode_to_restore ~= "n" then
		vim.cmd("startinsert")
	else
		vim.cmd("stopinsert")
	end

	statusline.update()
	winbar.update()
end

function M.reopen_current_tab(target_idx)
	local tabs = state.get_tabs()
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

function M.rebuild_tab(target_idx)
	M.save_tab_state()
	M.close_pane_windows()
	M.reopen_current_tab(target_idx)
end

function M.switch_to_tab(target_idx)
	state.set_toggling()
	M.rebuild_tab(target_idx)
end

return M
