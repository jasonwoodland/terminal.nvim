-- terminal.nvim: state and data model

local M = {}

local config = require("terminal.config")
local frame = require("terminal.frame")

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
	if win == vim.t.term_canvas_winid then return true end
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

-- Total screen rows spanned by the open drawer panes: bounding box over the
-- pane windows, so stacked panes (and the statusline rows between them) count
-- toward the drawer height. nil when no pane window is open.
function M.drawer_span()
	local wins = vim.t.term_winids or {}
	local top, bot = math.huge, 0
	for _, win in ipairs(wins) do
		if M.win_valid(win) then
			local pos = vim.api.nvim_win_get_position(win)
			top = math.min(top, pos[1])
			bot = math.max(bot, pos[1] + vim.api.nvim_win_get_height(win))
		end
	end
	if bot == 0 then
		return nil
	end
	return bot - top
end

function M.save_term_height()
	if vim.t.term_bufnr ~= nil and vim.t.term_prev_height == nil and not vim.t.term_zoom then
		local span = M.drawer_span()
		if span and span > 0 then
			vim.t.term_height = span
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
--   {
--     layout = <frame tree>,   -- source of truth for pane structure/sizes
--                              -- (see frame.lua; sizes rescaled on reopen)
--     bufs = {buf1, buf2},     -- DERIVED: DFS leaf order of layout; kept in
--                              -- sync via sync_bufs() after tree surgery
--     focus = <bufnr>,         -- last focused pane buffer
--     modes = { ["<bufnr>"] = "t"|"n" },  -- string keys (vim.t dicts)
--     activity = true,
--   }
-- Because state lives inside the entry, reordering or removing tabs carries
-- everything along automatically -- there is no index-keyed side table.
--
-- term_tab_idx: 1-based index of the active tab
-- term_winids: pane window IDs of the current tab, in DFS (bufs) order
-- term_winbar_winid: window ID of the floating winbar overlay
-------------------------------------------------------------------------------

-- Recompute the derived DFS buffer list from the layout tree.
function M.sync_bufs(entry)
	entry.bufs = frame.leaves(entry.layout)
	return entry
end

-- Fresh single-pane entry. Sizes are placeholders; rendering rescales the
-- tree to the real terminal geometry.
function M.new_entry(bufnr)
	return {
		layout = { t = "leaf", buf = bufnr, w = 1, h = 1 },
		bufs = { bufnr },
		focus = bufnr,
	}
end

-- Upgrade older persisted formats:
--   v1: {buf1, buf2}            (one buffer per tab)
--   v2: {{buf1, buf2}, {buf3}}  (buffer lists, state in side tables)
--   v3: {{bufs = {...}, widths = {...}, focus = <idx>, modes = {"t",...}}}
--   v4: {{layout = <tree>, bufs = {...}, focus = <bufnr>, modes = {map}}}
function M.migrate_term_order(order)
	if #order == 0 then
		return order
	end
	local first = order[1]
	if type(first) == "table" and first.layout then
		return order
	end

	-- v1/v2 -> v3 shape first
	local v3 = {}
	if type(first) == "number" then
		for _, buf in ipairs(order) do
			table.insert(v3, { bufs = { buf } })
		end
	elseif not first.bufs then
		for _, bufs in ipairs(order) do
			table.insert(v3, { bufs = bufs })
		end
	else
		v3 = order
	end

	-- v3 -> v4: flat bufs + widths become a row layout; positional focus and
	-- modes become buf-keyed.
	for _, entry in ipairs(v3) do
		local total = #entry.bufs - 1
		if entry.widths and #entry.widths == #entry.bufs then
			for _, w in ipairs(entry.widths) do
				total = total + w
			end
		else
			total = total + #entry.bufs
			entry.widths = nil
		end
		entry.layout = frame.from_bufs(entry.bufs, entry.widths, total, 1)

		local focus_idx = M.clamp(entry.focus or 1, 1, #entry.bufs)
		entry.focus = entry.bufs[focus_idx]

		local modes = nil
		if type(entry.modes) == "table" then
			modes = {}
			for i, buf in ipairs(entry.bufs) do
				if entry.modes[i] then
					modes[tostring(buf)] = entry.modes[i]
				end
			end
		end
		entry.modes = modes
		entry.widths = nil
	end
	return v3
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
		local entry_changed = false
		for _, buf in ipairs(entry.bufs) do
			if not (vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal") then
				entry_changed = true
				if entry.layout then
					entry.layout = select(1, frame.remove(entry.layout, buf))
				end
			end
		end
		if entry_changed then
			changed = true
			if entry.layout then
				M.sync_bufs(entry)
			end
		end
		if entry.layout and #entry.bufs > 0 then
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
					table.insert(order, i + 1, M.new_entry(bufnr))
					vim.t.term_order = order
					return
				end
			end
		end
	end

	table.insert(order, M.new_entry(bufnr))
	vim.t.term_order = order
end

-- Remove a buffer from whichever entry holds it, applying vim's close-space
-- rule to the entry's layout. Returns the buf of the absorbing pane (nil when
-- the whole entry went away).
function M.remove_term_from_order(bufnr)
	local order = M.get_term_order()
	local absorb_buf = nil

	local new_order = {}
	for _, entry in ipairs(order) do
		local keep = true
		for _, buf in ipairs(entry.bufs) do
			if buf == bufnr then
				local root, absorbed = frame.remove(entry.layout, bufnr)
				entry.layout = root
				absorb_buf = absorbed
				if root == nil then
					keep = false
				else
					M.sync_bufs(entry)
					if entry.focus == bufnr then
						entry.focus = absorbed
					end
					if entry.modes then
						entry.modes[tostring(bufnr)] = nil
					end
				end
				break
			end
		end
		if keep then
			table.insert(new_order, entry)
		end
	end

	vim.t.term_order = new_order
	vim.t.term_tab_idx = M.clamp(vim.t.term_tab_idx or 1, 1, math.max(#new_order, 1))
	return absorb_buf
end

-- Split the pane holding at_bufnr in a tab, inserting bufnr as the new pane.
-- dir is "row" (vsplit) or "col" (split). Falls back to appending at the top
-- level when at_bufnr isn't in the entry.
function M.split_buf_in_tab(bufnr, tab_idx, at_bufnr, dir)
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

	local at = at_bufnr
	local found = false
	for _, buf in ipairs(entry.bufs) do
		if buf == at then
			found = true
			break
		end
	end
	if not found then
		at = entry.bufs[#entry.bufs]
	end

	local root, err = frame.split(entry.layout, at, dir, bufnr)
	if err then
		-- Not enough room in the saved sizes: equalize at a generous virtual
		-- size and retry; rendering rescales to the real geometry anyway.
		frame.equalize(entry.layout, math.max(entry.layout.w, 200), math.max(entry.layout.h, 100))
		root, err = frame.split(entry.layout, at, dir, bufnr)
		if err then
			return
		end
	end
	entry.layout = root
	M.sync_bufs(entry)
	entry.focus = bufnr
	vim.t.term_order = order
	return true
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

-- Saved view state (layout/focus/modes) lives on the tab entry itself; these
-- accessors keep a stable read-modify-write interface over it.
function M.get_tab_state(tab_idx)
	local order = M.get_term_order()
	local entry = order[tab_idx]
	if not entry then
		return {}
	end
	return { layout = entry.layout, focus = entry.focus, modes = entry.modes }
end

function M.set_tab_state(tab_idx, st)
	local order = M.get_term_order()
	local entry = order[tab_idx]
	if not entry then
		return
	end
	if st.layout then
		entry.layout = st.layout
		M.sync_bufs(entry)
	end
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
