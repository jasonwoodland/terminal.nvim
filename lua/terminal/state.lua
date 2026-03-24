-- terminal.nvim: state and data model

local M = {}

local config = require("terminal.config")

local saved_cmdheight = nil
local saved_ruler = nil
local last_notification_bufnr = nil

function M.clamp(val, min, max)
	if val < min then return min end
	if val > max then return max end
	return val
end

function M.win_valid(win)
	return win and vim.fn.win_id2win(win) > 0
end

function M.set_toggling()
	vim.t.term_toggling = true
	local gen = (vim.t.term_toggling_gen or 0) + 1
	vim.t.term_toggling_gen = gen
	local tabnr = vim.api.nvim_get_current_tabpage()
	vim.defer_fn(function()
		if vim.api.nvim_tabpage_is_valid(tabnr) then
			local ok, cur_gen = pcall(vim.api.nvim_tabpage_get_var, tabnr, "term_toggling_gen")
			if ok and cur_gen == gen then
				vim.api.nvim_tabpage_set_var(tabnr, "term_toggling", false)
			end
		end
	end, 100)
end

function M.is_term_open()
	local wins = vim.t.term_winids or {}
	for _, win in ipairs(wins) do
		if M.win_valid(win) then
			return true
		end
	end
	return false
end

function M.is_term_related_window(win)
	local wins = vim.t.term_winids or {}
	for _, w in ipairs(wins) do
		if w == win then return true end
	end
	if win == vim.t.term_winbar_winid then return true end
	local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
	if ok and vim.b[buf].terminal_stl then return true end
	return false
end

function M.compute_equal_widths(total, count)
	local base_w = math.floor(total / count)
	local extra = total - base_w * count
	local widths = {}
	for i = 1, count do
		widths[i] = base_w + (i <= extra and 1 or 0)
	end
	return widths
end

function M.set_zoom_cmdheight()
	if not config.config.float_zoom_hide_cmdline then
		return
	end
	if saved_cmdheight == nil then
		saved_cmdheight = vim.o.cmdheight
	end
	vim.o.cmdheight = 0
end

function M.restore_cmdheight()
	if saved_cmdheight ~= nil then
		vim.o.cmdheight = saved_cmdheight
		saved_cmdheight = nil
	end
end

function M.set_zoom_ruler()
	if saved_ruler == nil then
		saved_ruler = vim.o.ruler
	end
	vim.o.ruler = false
end

function M.restore_ruler()
	if saved_ruler ~= nil then
		vim.o.ruler = saved_ruler
		saved_ruler = nil
	end
end

function M.save_term_height()
	if vim.fn.exists("t:term_bufnr") ~= 0 and vim.t.term_prev_height == nil and not vim.t.term_zoom then
		local wins = vim.t.term_winids or {}
		if #wins > 0 and M.win_valid(wins[1]) then
			local height = vim.api.nvim_win_get_height(wins[1])
			if height > 0 then
				vim.t.term_height = height
			end
		elseif vim.t.term_bufnr then
			local height = vim.fn.winheight(vim.fn.bufwinnr(vim.t.term_bufnr))
			if height > 0 then
				vim.t.term_height = height
			end
		end
	end
end

function M.is_in_term_window()
	local wins = vim.t.term_winids or {}
	local current = vim.fn.win_getid()
	for _, win in ipairs(wins) do
		if win == current then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Data Model: Tabs
--
-- term_order: {{buf1, buf2}, {buf3}, {buf4}} -- list of tabs
-- term_tab_idx: 1-based index of the active tab
-- term_tab_state: saved state per tab {[idx_str] = {widths, focus, views, modes}}
-- term_winids: list of window IDs for panes in the current tab
-- term_winbar_winid: window ID of the floating winbar overlay
-------------------------------------------------------------------------------

function M.migrate_term_order(order)
	if #order == 0 then
		return order
	end
	if type(order[1]) == "number" then
		local new_order = {}
		for _, buf in ipairs(order) do
			table.insert(new_order, { buf })
		end
		return new_order
	end
	return order
end

function M.get_term_order()
	local order = vim.t.term_order or {}
	return M.migrate_term_order(order)
end

function M.get_tabs()
	local order = M.get_term_order()

	local valid_order = {}
	local removed = {}
	for gi, tab in ipairs(order) do
		local valid_tab = {}
		for _, buf in ipairs(tab) do
			if vim.fn.bufexists(buf) == 1 and vim.fn.getbufvar(buf, "&buftype") == "terminal" then
				table.insert(valid_tab, buf)
			end
		end
		if #valid_tab > 0 then
			table.insert(valid_order, valid_tab)
		else
			table.insert(removed, gi)
		end
	end

	-- Remap activity keys when tabs are removed by filtering
	if #removed > 0 then
		local old = vim.t.term_tab_activity or {}
		local new = {}
		local offset = 0
		for i = 1, #order do
			if removed[offset + 1] == i then
				offset = offset + 1
			elseif old[tostring(i)] then
				new[tostring(i - offset)] = true
			end
		end
		vim.t.term_tab_activity = new
	end

	vim.t.term_order = valid_order

	vim.t.term_tab_idx = M.clamp(vim.t.term_tab_idx or 1, 1, math.max(#valid_order, 1))

	return valid_order
end

function M.find_buf_tab(bufnr)
	local tabs = M.get_tabs()
	for gi, tab in ipairs(tabs) do
		for pi, buf in ipairs(tab) do
			if buf == bufnr then
				return gi, pi
			end
		end
	end
	return nil, nil
end

function M.swap_activity(idx1, idx2)
	local activity = vim.t.term_tab_activity or {}
	local k1, k2 = tostring(idx1), tostring(idx2)
	activity[k1], activity[k2] = activity[k2], activity[k1]
	vim.t.term_tab_activity = activity
end

function M.shift_activity_after_remove(removed_idx, total_before)
	local old = vim.t.term_tab_activity or {}
	local new = {}
	for i = 1, total_before do
		if i < removed_idx then
			if old[tostring(i)] then
				new[tostring(i)] = true
			end
		elseif i > removed_idx then
			if old[tostring(i)] then
				new[tostring(i - 1)] = true
			end
		end
	end
	vim.t.term_tab_activity = new
end

function M.add_term_to_order(bufnr, after_bufnr)
	local order = M.get_term_order()

	for _, tab in ipairs(order) do
		for _, buf in ipairs(tab) do
			if buf == bufnr then
				return
			end
		end
	end

	if after_bufnr then
		for i, tab in ipairs(order) do
			for _, buf in ipairs(tab) do
				if buf == after_bufnr then
					table.insert(order, i + 1, { bufnr })
					vim.t.term_order = order
					return
				end
			end
		end
	end

	table.insert(order, { bufnr })
	vim.t.term_order = order
end

function M.remove_term_from_order(bufnr)
	local order = M.get_term_order()
	local total_before = #order

	local removed_tab_idx = nil
	local new_order = {}
	for gi, tab in ipairs(order) do
		local new_tab = {}
		for _, buf in ipairs(tab) do
			if buf ~= bufnr then
				table.insert(new_tab, buf)
			end
		end
		if #new_tab > 0 then
			table.insert(new_order, new_tab)
		elseif not removed_tab_idx then
			removed_tab_idx = gi
		end
	end

	vim.t.term_order = new_order
	vim.t.term_tab_idx = M.clamp(vim.t.term_tab_idx or 1, 1, math.max(#new_order, 1))

	if removed_tab_idx then
		M.shift_activity_after_remove(removed_tab_idx, total_before)
	end
end

function M.add_buf_to_tab(bufnr, tab_idx, after_pane_idx)
	local order = M.get_term_order()

	if not order[tab_idx] then
		return
	end

	local tab = order[tab_idx]

	for _, buf in ipairs(tab) do
		if buf == bufnr then
			return
		end
	end

	local insert_pos = after_pane_idx and (after_pane_idx + 1) or (#tab + 1)
	table.insert(tab, insert_pos, bufnr)
	vim.t.term_order = order
end

function M.get_current_tab()
	local tabs = M.get_tabs()
	local idx = vim.t.term_tab_idx or 1
	if idx < 1 or idx > #tabs then
		return nil, idx
	end
	return tabs[idx], idx
end

function M.adopt_orphaned_terminals()
	local owned = {}
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local ok, order = pcall(vim.api.nvim_tabpage_get_var, tab, "term_order")
		if ok and order then
			order = M.migrate_term_order(order)
			for _, grp in ipairs(order) do
				for _, buf in ipairs(grp) do
					owned[buf] = true
				end
			end
		end
	end

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" and not owned[buf] then
			M.add_term_to_order(buf)
		end
	end
end

-------------------------------------------------------------------------------
-- Tab State Helpers
-------------------------------------------------------------------------------

function M.get_tab_state(tab_idx)
	local tab_state = vim.t.term_tab_state or {}
	return tab_state[tostring(tab_idx)] or {}
end

function M.set_tab_state(tab_idx, st)
	local tab_state = vim.t.term_tab_state or {}
	tab_state[tostring(tab_idx)] = st
	vim.t.term_tab_state = tab_state
end

function M.setup_vars()
	vim.t.term_winid = vim.t.term_winid or 0
	vim.t.term_winids = vim.t.term_winids or {}
	vim.t.term_height = vim.t.term_height or config.get_term_height()
	vim.t.term_tab_idx = vim.t.term_tab_idx or 1
	vim.t.term_tab_state = vim.t.term_tab_state or {}
end

-------------------------------------------------------------------------------
-- Shared state accessors
-------------------------------------------------------------------------------

function M.get_last_notification_bufnr()
	return last_notification_bufnr
end

function M.set_last_notification_bufnr(bufnr)
	last_notification_bufnr = bufnr
end

return M
