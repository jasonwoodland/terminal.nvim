-- terminal.nvim

local M = {}

local loaded = false

local config = require("terminal.config")
local state = require("terminal.state")
local window = require("terminal.window")
local winbar = require("terminal.winbar")
local statusline = require("terminal.statusline")

M.config = config.config

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.toggle(opts)
	state.set_toggling()

	local height = vim.v.count1

	if #vim.api.nvim_tabpage_list_wins(0) == 1 and not config.is_float_mode() then
		vim.t.term_winid = nil
		vim.t.term_winids = {}
	end

	local is_open = state.is_term_open()
	if not is_open and vim.t.term_winid and vim.t.term_winid ~= 0 and state.win_valid(vim.t.term_winid) then
		is_open = true
	end
	-- In non-float mode with only 1 window total, terminal is not meaningfully open
	if is_open and not config.is_float_mode() then
		local tab_wins = vim.api.nvim_tabpage_list_wins(0)
		-- Exclude winbar overlay from count
		local real_wins = 0
		for _, w in ipairs(tab_wins) do
			if w ~= vim.t.term_winbar_winid then
				real_wins = real_wins + 1
			end
		end
		if real_wins <= 1 then
			is_open = false
		end
	end

	if opts and opts.open == true and is_open then
		return
	end
	if opts and opts.open == false and not is_open then
		return
	end

	if is_open then
		-- Close
		window.save_tab_state()
		if state.win_valid(vim.t.term_winid) then
			vim.t.term_bufnr = vim.api.nvim_win_get_buf(vim.t.term_winid)
			vim.t.term_mode = vim.fn.mode()
			vim.b[vim.t.term_bufnr].term_view = vim.fn.winsaveview()
		end
		window.close_pane_windows()
	else
		-- Open
		vim.t.prev_winid = vim.fn.win_getid()

		local tab, tab_idx = state.get_current_tab()

		if tab and #tab > 0 then
			if height > 1 then
				vim.t.term_height = height
			end
			window.open_tab_windows(tab, tab_idx)
		else
			-- Create a new terminal and open it via open_tab_windows
			local bufnr = vim.api.nvim_create_buf(false, true)
			local order = state.get_term_order()
			table.insert(order, { bufnr })
			vim.t.term_order = order
			vim.t.term_tab_idx = #order
			window.termopen_with_size(bufnr)
			window.reopen_current_tab()
		end
	end
end

function M.zoom()
	state.set_toggling()

	if config.config.float then
		vim.t.term_zoom = not vim.t.term_zoom
		window.rebuild_tab()
		return
	end

	if config.config.float_zoom then
		if not state.is_term_open() then
			return
		end

		window.save_tab_state()

		if not vim.t.term_zoom then
			state.save_term_height()
			vim.t.term_zoom = true
		else
			vim.t.term_zoom = nil
		end

		window.close_pane_windows()
		window.reopen_current_tab()
		return
	end

	-- Non-float, non-float_zoom: old height toggle behavior
	local wins2 = vim.t.term_winids or {}
	if #wins2 == 0 or not state.win_valid(wins2[1]) then
		return
	end
	if vim.t.term_prev_height == nil then
		vim.t.term_prev_height = vim.t.term_height
		vim.api.nvim_win_call(wins2[1], function()
			vim.cmd("resize")
		end)
		vim.t.term_height = vim.api.nvim_win_get_height(wins2[1])
	else
		vim.t.term_height = vim.t.term_prev_height
		vim.t.term_prev_height = nil
	end
	vim.api.nvim_win_call(wins2[1], function()
		vim.cmd("resize " .. vim.t.term_height)
	end)
end

function M.reset_height()
	if vim.t.term_prev_height ~= nil or vim.t.term_zoom then
		return
	end
	vim.t.term_height = config.get_term_height()
	local wins = vim.t.term_winids or {}
	if #wins > 0 and state.win_valid(wins[1]) then
		vim.api.nvim_win_call(wins[1], function()
			vim.cmd("resize " .. vim.t.term_height)
		end)
	end
end

--------------------------------------------------------------------------------
-- Buffer switching
--------------------------------------------------------------------------------

function M.switch(delta, clamp_range)
	local tabs = state.get_tabs()
	if #tabs == 0 then
		return
	end

	if not state.is_term_open() then
		return
	end

	local current_idx = vim.t.term_tab_idx or 1
	local target_idx

	if clamp_range then
		target_idx = math.max(1, math.min(#tabs, current_idx + delta))
	else
		target_idx = ((current_idx + delta - 1) % #tabs) + 1
	end

	if target_idx == current_idx then
		return
	end

	window.switch_to_tab(target_idx)
end

function M.go_to(index)
	local tabs = state.get_tabs()
	if index < 1 or index > #tabs then
		return
	end

	local current_idx = vim.t.term_tab_idx or 1
	if index == current_idx then
		return
	end

	if not state.is_term_open() then
		return
	end

	window.switch_to_tab(index)
end

function M.move(direction)
	local tabs = state.get_tabs()
	if #tabs < 2 then
		return
	end

	local current_idx = vim.t.term_tab_idx or 1
	local new_idx = ((current_idx + direction - 1) % #tabs) + 1

	local order = state.get_term_order()

	order[current_idx], order[new_idx] = order[new_idx], order[current_idx]
	vim.t.term_order = order

	local s1, s2 = state.get_tab_state(current_idx), state.get_tab_state(new_idx)
	state.set_tab_state(current_idx, s2)
	state.set_tab_state(new_idx, s1)

	state.swap_activity(current_idx, new_idx)

	vim.t.term_tab_idx = new_idx

	winbar.update()
end

function M.move_to_vim_tab(direction)
	if not state.is_in_term_window() then
		return
	end

	local tabs = vim.api.nvim_list_tabpages()
	if #tabs < 2 then
		return
	end

	local current_tab = vim.api.nvim_get_current_tabpage()
	local idx
	for i, tab in ipairs(tabs) do
		if tab == current_tab then
			idx = i
			break
		end
	end

	local target_idx = ((idx + direction - 1) % #tabs) + 1
	local target_tab = tabs[target_idx]

	local tab, tab_idx = state.get_current_tab()
	if not tab then
		return
	end

	window.save_tab_state()
	window.close_pane_windows()

	-- Remove tab from current tab
	local order = state.get_term_order()
	local total_before = #order
	table.remove(order, tab_idx)
	vim.t.term_order = order

	state.shift_activity_after_remove(tab_idx, total_before)

	-- Add tab to target tab before opening remaining tabs, so
	-- adopt_orphaned_terminals() (triggered by WinEnter) doesn't re-adopt
	-- the moved buffers into the source tab.
	local ok, target_order = pcall(vim.api.nvim_tabpage_get_var, target_tab, "term_order")
	if not ok then
		target_order = {}
	end
	target_order = state.migrate_term_order(target_order)
	table.insert(target_order, tab)
	vim.api.nvim_tabpage_set_var(target_tab, "term_order", target_order)

	local new_idx2 = state.clamp(vim.t.term_tab_idx or 1, 1, math.max(#order, 1))
	vim.t.term_tab_idx = new_idx2

	state.set_toggling()
	local remaining_tabs = state.get_tabs()
	if #remaining_tabs > 0 and new_idx2 >= 1 and new_idx2 <= #remaining_tabs then
		window.open_tab_windows(remaining_tabs[new_idx2], new_idx2)
	else
		vim.t.term_winid = nil
		vim.t.term_winids = {}
		vim.t.term_bufnr = nil
	end

	-- Switch to target tab
	vim.api.nvim_set_current_tabpage(target_tab)
	state.setup_vars()

	local target_tabs = state.get_tabs()
	local target_tab_idx = #target_tabs

	local target_open = false
	local target_wins = vim.t.term_winids or {}
	for _, win in ipairs(target_wins) do
		if state.win_valid(win) then
			target_open = true
			break
		end
	end

	if target_open then
		window.save_tab_state()
		window.close_pane_windows()
	end

	vim.t.term_tab_idx = target_tab_idx
	window.open_tab_windows(target_tabs[target_tab_idx], target_tab_idx)
end

function M.go_to_notification()
	local last_bufnr = state.get_last_notification_bufnr()
	if not last_bufnr or not vim.api.nvim_buf_is_valid(last_bufnr) then
		vim.notify("No recent notification", vim.log.levels.WARN)
		return
	end

	local bufnr = last_bufnr

	-- Find which tab owns this buffer
	local target_tab = nil
	for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
		local ok, order = pcall(vim.api.nvim_tabpage_get_var, tp, "term_order")
		if ok and order then
			order = state.migrate_term_order(order)
			for _, grp in ipairs(order) do
				for _, buf in ipairs(grp) do
					if buf == bufnr then
						target_tab = tp
						break
					end
				end
				if target_tab then break end
			end
		end
		if target_tab then break end
	end

	if not target_tab then
		vim.notify("Notification terminal no longer exists", vim.log.levels.WARN)
		state.set_last_notification_bufnr(nil)
		return
	end

	state.set_toggling()

	-- Switch to the target tab if needed
	if target_tab ~= vim.api.nvim_get_current_tabpage() then
		vim.api.nvim_set_current_tabpage(target_tab)
		state.setup_vars()
	end

	-- Open terminal if not already open
	if not state.is_term_open() then
		M.toggle({ open = true })
	end

	-- Find the tab/pane index now (after tabs are validated)
	local tab_idx, pane_idx = state.find_buf_tab(bufnr)
	if not tab_idx then
		return
	end

	local current_idx = vim.t.term_tab_idx or 1
	if tab_idx ~= current_idx then
		window.save_tab_state()
		window.close_pane_windows()

		local st = state.get_tab_state(tab_idx)
		st.focus = pane_idx
		state.set_tab_state(tab_idx, st)

		window.reopen_current_tab(tab_idx)
	else
		-- Already on the right tab, just focus the pane
		local wins = vim.t.term_winids or {}
		if pane_idx and pane_idx <= #wins and state.win_valid(wins[pane_idx]) then
			vim.api.nvim_set_current_win(wins[pane_idx])
			local mode = vim.b[bufnr].term_mode
			if mode == "t" or mode == nil then
				vim.cmd("startinsert")
			else
				vim.cmd("stopinsert")
			end
			statusline.update()
		end
	end
end

local function term_has_foreground_process(bufnr)
	local job_id = vim.b[bufnr].terminal_job_id
	if not job_id then
		return false
	end
	local ok, pid = pcall(vim.fn.jobpid, job_id)
	if not ok or not pid then
		return false
	end
	local result = vim.fn.system("pgrep -P " .. pid)
	return vim.v.shell_error == 0 and result ~= ""
end

function M.delete()
	state.set_toggling()

	if vim.bo.buftype ~= "terminal" then
		return
	end

	local bufnr = vim.fn.bufnr()

	if term_has_foreground_process(bufnr) then
		if vim.fn.confirm("Terminal has a running process. Close anyway?", "&Yes\n&No", 2) ~= 1 then
			return
		end
	end

	local tab_idx, _ = state.find_buf_tab(bufnr)
	if not tab_idx then
		return
	end

	local tabs = state.get_tabs()
	local tab = tabs[tab_idx]

	if #tab == 1 then
		window.save_tab_state()
		window.close_pane_windows()
		state.remove_term_from_order(bufnr)
		vim.api.nvim_buf_delete(bufnr, { force = true })
		window.reopen_current_tab()
	else
		window.save_tab_state()
		window.close_pane_windows()

		local order = state.get_term_order()
		local g = order[tab_idx]
		local new_g = {}
		for _, buf in ipairs(g) do
			if buf ~= bufnr then
				table.insert(new_g, buf)
			end
		end
		order[tab_idx] = new_g
		vim.t.term_order = order

		local st = state.get_tab_state(tab_idx)
		st.widths = nil
		if st.focus and st.focus > #new_g then
			st.focus = #new_g
		end
		state.set_tab_state(tab_idx, st)

		vim.api.nvim_buf_delete(bufnr, { force = true })
		window.reopen_current_tab(tab_idx)
	end
end

function M.new()
	state.set_toggling()

	local _, current_idx = state.get_current_tab()

	window.save_tab_state()
	window.close_pane_windows()

	local bufnr = vim.api.nvim_create_buf(false, true)

	-- Add to order before termopen so TermOpen autocmd doesn't double-add
	local order = state.get_term_order()
	local insert_idx = (current_idx or #order) + 1
	table.insert(order, insert_idx, { bufnr })
	vim.t.term_order = order
	vim.t.term_tab_idx = insert_idx

	window.termopen_with_size(bufnr)

	window.open_tab_windows({ bufnr }, insert_idx)
end

function M.vsplit()
	state.set_toggling()

	local tab, tab_idx = state.get_current_tab()
	if not tab then
		M.toggle({ open = true })
		return
	end

	-- Find current pane index before closing windows
	local current_bufnr = vim.fn.bufnr()
	local _, current_pane_idx = state.find_buf_tab(current_bufnr)

	window.save_tab_state()
	window.close_pane_windows()

	local bufnr = vim.api.nvim_create_buf(false, true)

	-- Add to tab after current pane, before termopen so TermOpen autocmd doesn't double-add
	state.add_buf_to_tab(bufnr, tab_idx, current_pane_idx)

	window.termopen_with_size(bufnr, #tab + 1)

	local insert_pos = (current_pane_idx or #tab) + 1
	local st = state.get_tab_state(tab_idx)
	st.widths = nil
	st.focus = insert_pos
	state.set_tab_state(tab_idx, st)

	window.reopen_current_tab(tab_idx)

	local wins = vim.t.term_winids or {}
	if current_pane_idx and wins[current_pane_idx] then
		vim.t.term_prev_pane_winid = wins[current_pane_idx]
	end
end

function M.next()
	M.switch(1)
end

function M.prev()
	M.switch(-1)
end

function M.send(text)
	local winid = vim.t.term_winid
	if not winid or winid == 0 then
		return
	end
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local job = vim.b[bufnr].terminal_job_id
	if not job then
		return
	end
	vim.api.nvim_chan_send(job, text)
end

function M.setup(user_config)
	config.setup(user_config)
	M.config = config.config

	if loaded then
		return
	end

	state.setup_vars()

	local setup = require("terminal.setup")
	setup.setup_autocmd(M)
	setup.setup_winbar_autocmds()
	setup.setup_osc_notifications()
	setup.setup_keymap(M)
	setup.setup_command(M)
	setup.setup_alias()

	require("terminal.job").setup()
	require("terminal.fugitive").setup()

	loaded = true
end

return M
