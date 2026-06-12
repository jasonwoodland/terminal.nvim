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
	return win ~= nil and vim.api.nvim_win_is_valid(win)
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
	if vim.t.term_bufnr ~= nil and vim.t.term_prev_height == nil and not vim.t.term_zoom then
		local wins = vim.t.term_winids or {}
		if #wins > 0 and M.win_valid(wins[1]) then
			local height = vim.api.nvim_win_get_height(wins[1])
			if height > 0 then
				vim.t.term_height = height
			end
		elseif vim.t.term_bufnr then
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_get_buf(win) == vim.t.term_bufnr then
					local height = vim.api.nvim_win_get_height(win)
					if height > 0 then
						vim.t.term_height = height
					end
					break
				end
			end
		end
	end
end

function M.is_in_term_window()
	local wins = vim.t.term_winids or {}
	local current = vim.api.nvim_get_current_win()
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
-- term_order: list of tab entries, each owning its panes and saved state:
--   { bufs = {buf1, buf2}, focus = 1, widths = {80, 40}, modes = {"t","n"},
--     activity = true }
-- Because state lives inside the entry, reordering or removing tabs carries
-- widths/focus/modes/activity along automatically -- there is no index-keyed
-- side table to remap.
--
-- term_tab_idx: 1-based index of the active tab
-- term_winids: list of window IDs for panes in the current tab
-- term_winbar_winid: window ID of the floating winbar overlay
-------------------------------------------------------------------------------

-- Upgrade older persisted formats:
--   v1: {buf1, buf2}            (one buffer per tab)
--   v2: {{buf1, buf2}, {buf3}}  (buffer lists, state in side tables)
--   v3: {{bufs = {...}, ...}}   (entries owning their state)
function M.migrate_term_order(order)
	if #order == 0 then
		return order
	end
	local first = order[1]
	if type(first) == "table" and first.bufs then
		return order
	end
	local new_order = {}
	if type(first) == "number" then
		for _, buf in ipairs(order) do
			table.insert(new_order, { bufs = { buf } })
		end
	else
		for _, bufs in ipairs(order) do
			table.insert(new_order, { bufs = bufs })
		end
	end
	return new_order
end

function M.get_term_order()
	local order = vim.t.term_order or {}
	return M.migrate_term_order(order)
end

function M.get_tabs()
	local order = M.get_term_order()

	local valid_order = {}
	local changed = false
	for _, entry in ipairs(order) do
		local valid_bufs = {}
		for _, buf in ipairs(entry.bufs) do
			if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
				table.insert(valid_bufs, buf)
			end
		end
		if #valid_bufs ~= #entry.bufs then
			changed = true
			entry.bufs = valid_bufs
		end
		if #valid_bufs > 0 then
			table.insert(valid_order, entry)
		end
	end

	if changed then
		vim.t.term_order = valid_order
	end

	local new_idx = M.clamp(vim.t.term_tab_idx or 1, 1, math.max(#valid_order, 1))
	if (vim.t.term_tab_idx or 1) ~= new_idx then
		vim.t.term_tab_idx = new_idx
	end

	return valid_order
end

function M.find_buf_tab(bufnr)
	local tabs = M.get_tabs()
	for gi, entry in ipairs(tabs) do
		for pi, buf in ipairs(entry.bufs) do
			if buf == bufnr then
				return gi, pi
			end
		end
	end
	return nil, nil
end

function M.add_term_to_order(bufnr, after_bufnr)
	local order = M.get_term_order()

	for _, entry in ipairs(order) do
		for _, buf in ipairs(entry.bufs) do
			if buf == bufnr then
				return
			end
		end
	end

	if after_bufnr then
		for i, entry in ipairs(order) do
			for _, buf in ipairs(entry.bufs) do
				if buf == after_bufnr then
					table.insert(order, i + 1, { bufs = { bufnr } })
					vim.t.term_order = order
					return
				end
			end
		end
	end

	table.insert(order, { bufs = { bufnr } })
	vim.t.term_order = order
end

function M.remove_term_from_order(bufnr)
	local order = M.get_term_order()

	local new_order = {}
	for _, entry in ipairs(order) do
		local new_bufs = {}
		for _, buf in ipairs(entry.bufs) do
			if buf ~= bufnr then
				table.insert(new_bufs, buf)
			end
		end
		if #new_bufs > 0 then
			entry.bufs = new_bufs
			table.insert(new_order, entry)
		end
	end

	vim.t.term_order = new_order
	vim.t.term_tab_idx = M.clamp(vim.t.term_tab_idx or 1, 1, math.max(#new_order, 1))
end

function M.add_buf_to_tab(bufnr, tab_idx, after_pane_idx)
	local order = M.get_term_order()

	local entry = order[tab_idx]
	if not entry then
		return
	end

	for _, buf in ipairs(entry.bufs) do
		if buf == bufnr then
			return
		end
	end

	local insert_pos = after_pane_idx and (after_pane_idx + 1) or (#entry.bufs + 1)
	table.insert(entry.bufs, insert_pos, bufnr)
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

function M.adopt_current_terminal()
	local bufnr = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "terminal" then
		return false
	end

	local owner_tab = vim.b[bufnr].term_owner_tab
	if owner_tab and vim.api.nvim_tabpage_is_valid(owner_tab) then
		return false
	end

	M.add_term_to_order(bufnr)
	vim.b[bufnr].term_owner_tab = vim.api.nvim_get_current_tabpage()
	return true
end

function M.adopt_orphaned_terminals()
	local orphans = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
			local owner_tab = vim.b[buf].term_owner_tab
			if not owner_tab or not vim.api.nvim_tabpage_is_valid(owner_tab) then
				table.insert(orphans, buf)
			end
		end
	end
	if #orphans == 0 then
		return
	end

	local owned = {}
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local order = vim.t[tab].term_order
		if order then
			order = M.migrate_term_order(order)
			for _, entry in ipairs(order) do
				for _, buf in ipairs(entry.bufs) do
					owned[buf] = true
				end
			end
		end
	end

	local current_tab = vim.api.nvim_get_current_tabpage()
	for _, buf in ipairs(orphans) do
		if not owned[buf] then
			M.add_term_to_order(buf)
			vim.b[buf].term_owner_tab = current_tab
		end
	end
end

-------------------------------------------------------------------------------
-- Tab State Helpers
-------------------------------------------------------------------------------

-- Saved view state (widths/focus/modes) lives on the tab entry itself; these
-- accessors keep a stable read-modify-write interface over it.
function M.get_tab_state(tab_idx)
	local order = M.get_term_order()
	local entry = order[tab_idx]
	if not entry then
		return {}
	end
	return { widths = entry.widths, focus = entry.focus, modes = entry.modes }
end

function M.set_tab_state(tab_idx, st)
	local order = M.get_term_order()
	local entry = order[tab_idx]
	if not entry then
		return
	end
	entry.widths = st.widths
	entry.focus = st.focus
	entry.modes = st.modes
	vim.t.term_order = order
end

-- Set/clear the activity flag on a tab entry. Returns true when the flag
-- actually changed.
function M.set_activity(tab_idx, active)
	local order = M.get_term_order()
	local entry = order[tab_idx]
	if not entry then
		return false
	end
	local val = active and true or nil
	if entry.activity == val then
		return false
	end
	entry.activity = val
	vim.t.term_order = order
	-- Drop the per-buffer fast-path flag used by the on_lines activity watcher
	if not val then
		for _, buf in ipairs(entry.bufs) do
			if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].term_activity_flagged then
				vim.b[buf].term_activity_flagged = nil
			end
		end
	end
	return true
end

function M.setup_vars()
	vim.t.term_winid = vim.t.term_winid or 0
	vim.t.term_winids = vim.t.term_winids or {}
	vim.t.term_height = vim.t.term_height or config.get_term_height()
	vim.t.term_tab_idx = vim.t.term_tab_idx or 1
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
