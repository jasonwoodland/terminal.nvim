-- terminal.nvim: window management

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local winbar = require("terminal.winbar")
local statusline = require("terminal.statusline")
local overlay = require("terminal.overlay")

local closing_pane_windows = false

local string_borders = {
	rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
	single  = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
	double  = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
	solid   = { " ", " ", " ", " ", " ", " ", " ", " " },
	none    = { "", "", "", "", "", "", "", "" },
	shadow  = { "", "", "", "", "", "", "", "" },
}

local function resolve_border(b)
	if type(b) == "string" then
		return string_borders[b] or string_borders.none
	end
	if type(b) == "table" then
		return b
	end
	return string_borders.none
end

-- Build an 8-element border for a pane in a multi-pane row, combining the
-- configured outer border with vertical separators between adjacent panes.
local function build_pane_border(base_border, has_left, has_right, fillchar)
	local outer = resolve_border(base_border)
	local sep = { fillchar, "WinSeparator" }
	return {
		(not has_left) and outer[1] or "",
		outer[2],
		(not has_right) and outer[3] or "",
		has_right and sep or outer[4],
		(not has_right) and outer[5] or "",
		outer[6],
		(not has_left) and outer[7] or "",
		has_left and sep or outer[8],
	}
end

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
		border = false,
	}

	if type(config.config.float) == "table" then
		float_config = vim.tbl_extend("force", float_config, config.config.float)
	end

	local has_border = float_config.border and float_config.border ~= "none"
	local border = has_border and float_config.border or "none"
	local col = float_config.padding.x
	local row = float_config.padding.y
	local border_width = has_border and 2 or 0
	local width = math.floor(vim.o.columns - float_config.padding.x * 2 - border_width)
	local height = math.floor(vim.o.lines - float_config.padding.y * 2 - border_width - 2)

	return {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = border,
		title = " Terminal ",
		title_pos = "center",
	}
end

local function open_window(win_config)
	local scratch = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(scratch, true, win_config)
	return win, scratch
end

-- Whether the current screen is large enough to host a float-mode rebuild.
-- In float zoom mode the pane window needs one content row plus any visible
-- native winbar slot, and 1 row for the statusline overlay. If the screen is
-- smaller than that, skip the rebuild and let Neovim's auto-clamp keep the
-- existing floats alive.
function M.can_rebuild_float()
	if not config.is_float_mode() then
		return true
	end
	local cfg = M.get_float_win_config()
	local tab_count = #state.get_tabs()
	local min_pane_height = config.get_winbar_height(tab_count) + 1
	local stl_height = vim.t.term_zoom and 1 or 0
	if cfg.height - stl_height < min_pane_height then
		return false
	end
	if cfg.width < 1 then
		return false
	end
	return true
end

-- Open a terminal in a temporary window so the PTY starts with correct
-- dimensions instead of the tiny aucmd window used by nvim_buf_call.
-- num_panes: how many panes will share the row/float (for width calculation)
-- tab_count: how many terminal tabs will exist once this terminal opens
function M.termopen_with_size(bufnr, num_panes, tab_count)
	num_panes = math.max(num_panes or 1, 1)
	local width = 80
	local height = math.floor(vim.o.lines * 0.5)
	local winbar_height = config.get_winbar_height(tab_count)

	if config.is_float_mode() then
		local cfg = M.get_float_win_config()
		width = cfg.width
		if num_panes > 1 then
			-- Subtract separator columns, then divide evenly
			width = math.floor((width - (num_panes - 1)) / num_panes)
		end
		height = cfg.height - winbar_height
	else
		local h = vim.t.term_height or config.get_term_height()
		height = h - winbar_height
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

	local current_win = vim.api.nvim_get_current_win()
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
	overlay.destroy()

	local wins = vim.t.term_winids or {}
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			local cfg = vim.api.nvim_win_get_config(win)
			if cfg.relative and cfg.relative ~= "" then
				vim.api.nvim_win_close(win, true)
			else
				if vim.api.nvim_get_current_win() == win then
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
	local tab_count = #state.get_tabs()
	local show_winbar = config.should_show_winbar(tab_count)

	local wins = {}
	local scratches = {}
	local height = vim.t.term_height or config.get_term_height()

	local has_stl = false
	local focus_idx = state.clamp(st.focus or 1, 1, #tab)

	if config.is_float_mode() then
		overlay.update()
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
			local border
			if has_left or has_right then
				border = build_pane_border(base_config.border, has_left, has_right, fillchar)
			else
				border = base_config.border
			end

			local win_cfg = vim.tbl_extend("force", {}, base_config)
			win_cfg.width = pane_widths[i]
			win_cfg.height = base_config.height - stl_height
			win_cfg.row = base_config.row
			win_cfg.col = base_config.col + col_offset
			win_cfg.border = border
			win_cfg.zindex = (i == focus_idx) and 31 or 30
			if num_panes > 1 then
				win_cfg.title = nil
				win_cfg.title_pos = nil
			end

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
		vim.wo[first_win].winfixheight = true
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

	-- Setting vim.wo[win].winbar requires the window to have >= 2 lines
	-- (1 for winbar, 1 for content); otherwise Neovim raises E36 "Not enough
	-- room". This matters when the user shrinks the app window to a very
	-- small size in float zoom mode.
	local function can_set_winbar(win)
		return show_winbar and vim.api.nvim_win_get_height(win) >= 2
	end

	local function apply_winbar(win)
		if can_set_winbar(win) then
			vim.wo[win].winbar = " "
		else
			vim.wo[win].winbar = ""
		end
	end

	-- Set window options on the scratch windows BEFORE attaching terminal
	-- buffers. nvim_win_set_buf calls get_winopts() which restores the
	-- buffer's saved w_onebuf_opt. If those match what we set here, the
	-- terminal sees no dimension change at attachment time.
	local float_winblend = config.get_float_winblend()
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			vim.wo[win].signcolumn = "no"
			vim.wo[win].foldcolumn = "0"
			vim.wo[win].number = false
			vim.wo[win].relativenumber = false
			vim.wo[win].scrolloff = 0
			vim.wo[win].sidescrolloff = 0
			vim.wo[win].winblend = float_winblend
			vim.wo[win].cursorline = false
			vim.wo[win].cursorcolumn = false
			vim.wo[win].spell = false
			vim.wo[win].list = false
			vim.wo[win].colorcolumn = ""
			vim.wo[win].statuscolumn = ""
			vim.wo[win].fillchars = "eob: "
			vim.wo[win].winhighlight = "EndOfBuffer:"
			apply_winbar(win)
		end
	end

	-- Attach terminal buffers. get_winopts() may overwrite some options
	-- from the buffer's WinInfo, so re-set them afterward.
	--
	-- Wrap in pcall so that if any operation raises (e.g. the app window is
	-- too small), eventignore is always restored. Otherwise a stuck
	-- eventignore silences Buf* events and makes Neovim appear frozen.
	local old_eventignore = vim.o.eventignore
	vim.o.eventignore = "BufEnter,BufLeave,BufWinEnter"
	local attach_ok, attach_err = pcall(function()
		for i, win in ipairs(wins) do
			if state.win_valid(win) then
				vim.api.nvim_win_set_buf(win, tab[i])
				vim.wo[win].signcolumn = "no"
				vim.wo[win].foldcolumn = "0"
				vim.wo[win].number = false
				vim.wo[win].relativenumber = false
				vim.wo[win].scrolloff = 0
				vim.wo[win].sidescrolloff = 0
				vim.wo[win].winblend = float_winblend
				apply_winbar(win)
			end
		end
	end)
	vim.o.eventignore = old_eventignore
	if not attach_ok then
		error(attach_err)
	end

	-- Force correct PTY dimensions after all window options are finalized.
	-- nvim_win_set_buf may report stale dimensions to the PTY before
	-- winbar/signcolumn/etc. are re-applied.
	if vim.t.term_zoom then
		for i, win in ipairs(wins) do
			if state.win_valid(win) then
				local job_id = vim.b[tab[i]].terminal_job_id
				if job_id then
					local rows = vim.api.nvim_win_get_height(win)
					if can_set_winbar(win) then
						rows = rows - 1
					end
					pcall(vim.fn.jobresize, job_id, vim.api.nvim_win_get_width(win), math.max(rows, 1))
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

function M.reopen_current_tab(target_idx, tabs)
	tabs = tabs or state.get_tabs()
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

function M.rebuild_tab(target_idx, tabs)
	M.save_tab_state()
	M.close_pane_windows()
	M.reopen_current_tab(target_idx, tabs)
end

function M.swap_tab_buffers(target_tab, target_idx)
	-- Fast-path buffer swap: reuse existing pane windows.
	-- Called only when pane counts match (checked by caller).
	-- Mirrors the buffer-attach logic in open_tab_windows().
	local wins = vim.t.term_winids or {}
	local target_st = state.get_tab_state(target_idx)
	local tab_count = #state.get_tabs()
	local show_winbar = config.should_show_winbar(tab_count)
	local float_winblend = config.get_float_winblend()
	local is_float = config.is_float_mode()

	local function can_set_winbar(win)
		return show_winbar and state.win_valid(win) and vim.api.nvim_win_get_height(win) >= 2
	end

	local focus_idx = state.clamp(target_st.focus or 1, 1, #wins)

	-- Pre-validation: abort to rebuild_tab if the open windows don't match the
	-- target tab's panes, or if any window or buffer is invalid. The caller
	-- compares pane counts in the data model (term_order), but term_winids can
	-- briefly disagree with it (e.g. TermClose shrinks term_order synchronously
	-- while the rebuild is deferred via vim.schedule).
	if #wins ~= #target_tab then
		return false
	end
	for i, win in ipairs(wins) do
		if not state.win_valid(win) then
			return false
		end
		if not vim.api.nvim_buf_is_valid(target_tab[i]) then
			return false
		end
	end

	-- Swap buffers in all pane windows (single eventignore/pcall block)
	local old_eventignore = vim.o.eventignore
	vim.o.eventignore = "BufEnter,BufLeave,BufWinEnter"
	local swap_ok, swap_err = pcall(function()
		for i, win in ipairs(wins) do
			vim.api.nvim_win_set_buf(win, target_tab[i])
			-- Re-apply window options (nvim_win_set_buf restores buffer's saved WinInfo)
			vim.wo[win].signcolumn = "no"
			vim.wo[win].foldcolumn = "0"
			vim.wo[win].number = false
			vim.wo[win].relativenumber = false
			vim.wo[win].scrolloff = 0
			vim.wo[win].sidescrolloff = 0
			vim.wo[win].winblend = float_winblend
			-- Apply/clear native winbar on terminal window
			if can_set_winbar(win) then
				vim.wo[win].winbar = " "
			else
				vim.wo[win].winbar = ""
			end
			-- Update z-index in float mode if focus changed
			if is_float then
				vim.api.nvim_win_set_config(win, { zindex = (i == focus_idx) and 31 or 30 })
			end
		end
	end)
	vim.o.eventignore = old_eventignore

	if not swap_ok then
		return false
	end

	-- Force PTY dimensions in zoom mode (mirrors open_tab_windows)
	if vim.t.term_zoom then
		for i, win in ipairs(wins) do
			if state.win_valid(win) then
				local job_id = vim.b[target_tab[i]].terminal_job_id
				if job_id then
					local rows = vim.api.nvim_win_get_height(win)
					if can_set_winbar(win) then
						rows = rows - 1
					end
					pcall(vim.fn.jobresize, job_id, vim.api.nvim_win_get_width(win), math.max(rows, 1))
				end
			end
		end
	end

	-- Set focus to target tab's focus pane
	if wins[focus_idx] and state.win_valid(wins[focus_idx]) then
		vim.api.nvim_set_current_win(wins[focus_idx])
	end

	-- Update state variables
	vim.t.term_winids = wins
	vim.t.term_winid = wins[focus_idx] or wins[1]
	vim.t.term_bufnr = target_tab[focus_idx] or target_tab[1]
	vim.t.term_tab_idx = target_idx

	-- Clear activity flag
	local activity = vim.t.term_tab_activity or {}
	activity[tostring(target_idx)] = nil
	vim.t.term_tab_activity = activity

	-- Restore terminal mode from TARGET tab's saved state
	local mode_to_restore = "t"
	if target_st.modes and target_st.modes[focus_idx] then
		mode_to_restore = target_st.modes[focus_idx]
	end
	if mode_to_restore ~= "n" then
		vim.cmd("startinsert")
	else
		vim.cmd("stopinsert")
	end

	statusline.update()
	winbar.update()
	return true
end

function M.switch_to_tab(target_idx)
	local current_idx = vim.t.term_tab_idx
	if current_idx and current_idx ~= target_idx then
		vim.t.term_prev_tab_idx = current_idx
	end

	-- Fast path: swap buffers in place when pane counts match
	local tabs = state.get_tabs()
	local current_tab = tabs[current_idx or 1]
	local target_tab = tabs[target_idx]
	if current_tab and target_tab and #current_tab == #target_tab then
		M.save_tab_state()
		state.set_toggling()
		if M.swap_tab_buffers(target_tab, target_idx) then
			return
		end
		-- Fast path failed (invalid window/buffer or pcall error), fall back to rebuild
	end

	state.set_toggling()
	M.rebuild_tab(target_idx, tabs)
end

return M
