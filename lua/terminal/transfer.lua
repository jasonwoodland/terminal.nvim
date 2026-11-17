-- Move terminal tabs transactionally between Vim tabs.
local M = {}
local state = require("terminal.state")
local window = require("terminal.window")
local mode = require("terminal.mode")
local context = require("terminal.context")

local saved_keys = { "term_tab_idx", "term_prev_tab_id", "term_bufnr", "term_height", "term_prev_height",
	"term_zoom", "term_float_enabled", "term_float_size", "term_drawer_size", "prev_winid" }

local function snapshot(tabpage)
	return vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(tabpage), function()
		window.save_tab_state()
		local saved = { tab = tabpage, order = state.get_term_order(), open = state.is_term_open(), focus = context.capture(), vars = {} }
		if saved.focus.managed then saved.focus.mode = mode.of_win(saved.focus.win) or "t" end
		for _, key in ipairs(saved_keys) do saved.vars[key] = vim.t[key] end
		return saved
	end)
end

local function rollback(source, target, caller, reason)
	local errors = {}
	for _, saved in ipairs({ source, target }) do
		if vim.api.nvim_tabpage_is_valid(saved.tab) then
			local ok, err = pcall(vim.api.nvim_win_call, vim.api.nvim_tabpage_get_win(saved.tab), function()
				state.set_toggling()
				window.close_pane_windows()
			end)
			if not ok then errors[#errors + 1] = tostring(err) end
		end
	end
	for _, saved in ipairs({ source, target }) do
		if vim.api.nvim_tabpage_is_valid(saved.tab) then
			for _, entry in ipairs(saved.order) do
				for _, buf in ipairs(entry.bufs) do vim.b[buf].term_owner_tab = saved.tab end
			end
			state.set_term_order(saved.order, saved.tab)
			for _, key in ipairs(saved_keys) do vim.t[saved.tab][key] = saved.vars[key] end
		end
	end
	for _, saved in ipairs({ source, target }) do
		if vim.api.nvim_tabpage_is_valid(saved.tab) then
			local ok, err = pcall(vim.api.nvim_win_call, vim.api.nvim_tabpage_get_win(saved.tab), function()
				if saved.open then assert(window.reopen_current_tab(), "terminal layout could not be restored") end
				context.restore(saved.focus)
			end)
			if not ok then errors[#errors + 1] = tostring(err) end
		else errors[#errors + 1] = "Vim tab was closed during transfer" end
	end
	context.restore(caller)
	state.sync_zoom_options()
	if #errors > 0 then reason = reason .. "; rollback failed: " .. table.concat(errors, "; ") end
	return false, reason
end

function M.move(direction)
	if not state.is_in_term_window() then
		return false, "Current window is not a managed terminal pane"
	end

	local tabs = vim.api.nvim_list_tabpages()
	if #tabs < 2 then
		return false, "No adjacent Vim tab"
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
		return false, "No terminal tab is selected"
	end
	-- Check both resulting views before detaching jobs or changing ownership.
	local source_order = state.get_tabs()
	local remaining_idx = math.min(tab_idx, #source_order - 1)
	if #source_order > 1 then
		local remaining = source_order[tab_idx + 1] or source_order[tab_idx - 1]
		if not window.can_open_tab(remaining, #source_order - 1) then
			return false, "Remaining terminal layout does not fit"
		end
	end
	local fits = vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(target_tab), function()
		return window.can_open_tab(tab, #state.get_tabs() + 1)
	end)
	if not fits then return false, "Destination terminal layout does not fit" end

	mode.record()
	window.save_tab_state()
	local caller = context.capture()
	local source, destination = snapshot(current_tab), snapshot(target_tab)
	local ok, result = pcall(function()
		window.close_pane_windows()

		-- Remove the entry AFTER save_tab_state so it carries up-to-date
		-- focus/modes (and widths/activity) into the target Vim tab.
		local order = state.get_term_order()
		local entry = table.remove(order, tab_idx)
		state.set_term_order(order)

		-- Register the entry and its ownership before opening the remaining tabs.
		local target_order = state.get_term_order(target_tab)
		table.insert(target_order, entry)
		state.set_term_order(target_order, target_tab)
		for _, buf in ipairs(entry.bufs) do
			vim.b[buf].term_owner_tab = target_tab
		end

		local new_idx2 = state.clamp(remaining_idx, 1, math.max(#order, 1))
		vim.t.term_tab_idx = new_idx2

		state.set_toggling()
		local remaining_tabs = state.get_tabs()
		if #remaining_tabs > 0 and new_idx2 >= 1 and new_idx2 <= #remaining_tabs then
			assert(window.open_tab_windows(remaining_tabs[new_idx2], new_idx2), "Remaining terminal workspace could not be opened")
		else
			vim.t.term_winid = nil
			vim.t.term_winids = {}
			vim.t.term_bufnr = nil
		end

		-- Switch to target tab
		mode.record()
		vim.api.nvim_set_current_tabpage(target_tab)
		state.setup_vars()

		state.remember_current_tab()
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
		assert(window.open_tab_windows(target_tabs[target_tab_idx], target_tab_idx), "Destination terminal workspace could not be opened")
		return true
	end)
	if not ok then return rollback(source, destination, caller, tostring(result)) end
	return result
end

return M
