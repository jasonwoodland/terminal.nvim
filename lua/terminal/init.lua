-- terminal.nvim

local M = {}

local loaded = false

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

M.config = {
	height = 0.5,
	winbar = true,
	float = false,
	float_zoom = true,
	float_zoom_show_tabline = true,
	float_zoom_hide_cmdline = false,
	osc_notifications = true,
	keys = {
		toggle = "<C-S-Space>",
		normal_mode = "<C-S-n>",
		zoom = "<C-S-z>",
		new = "<C-S-t>",
		wincmd = "<C-S-w>",
		delete = "<C-S-c>",
		prev = "<C-S-[>",
		next = "<C-S-]>",
		move_prev = "<C-S-M-[>",
		move_next = "<C-S-M-]>",
		paste_register = "<C-S-r>",
		reset_height = "<C-S-=>",
		tab_next = "<C-PageDown>",
		tab_prev = "<C-PageUp>",
		move_to_tab_prev = "<C-M-PageUp>",
		move_to_tab_next = "<C-M-PageDown>",
		last_notification = "<C-S-a>",
	},
}

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------

local utils = require("terminal.utils")

local function get_term_height()
	if M.config.height < 1 then
		return math.floor(vim.o.lines * M.config.height)
	end
	return M.config.height
end

local function is_float_mode()
	return M.config.float or (M.config.float_zoom and vim.t.term_zoom)
end

local toggling = false
local toggling_gen = 0
local saved_cmdheight = nil
local saved_ruler = nil
local drag_state = nil
local out_tty = vim.loop.new_tty(1, true)
local last_notification_bufnr = nil

local function clamp(val, min, max)
	if val < min then return min end
	if val > max then return max end
	return val
end

local function win_valid(win)
	return win and vim.fn.win_id2win(win) > 0
end

local function set_toggling()
	toggling = true
	toggling_gen = toggling_gen + 1
	local gen = toggling_gen
	vim.defer_fn(function()
		if toggling_gen == gen then
			toggling = false
		end
	end, 100)
end

local function is_term_open()
	local wins = vim.t.term_winids or {}
	for _, win in ipairs(wins) do
		if win_valid(win) then
			return true
		end
	end
	return false
end

local function is_term_related_window(win)
	local wins = vim.t.term_winids or {}
	for _, w in ipairs(wins) do
		if w == win then return true end
	end
	if win == vim.t.term_winbar_winid then return true end
	return false
end

local function compute_equal_widths(total, count)
	local base_w = math.floor(total / count)
	local extra = total - base_w * count
	local widths = {}
	for i = 1, count do
		widths[i] = base_w + (i <= extra and 1 or 0)
	end
	return widths
end

local function set_zoom_cmdheight()
	if not M.config.float_zoom_hide_cmdline then
		return
	end
	if saved_cmdheight == nil then
		saved_cmdheight = vim.o.cmdheight
	end
	vim.o.cmdheight = 0
end

local function restore_cmdheight()
	if saved_cmdheight ~= nil then
		vim.o.cmdheight = saved_cmdheight
		saved_cmdheight = nil
	end
end

local function set_zoom_ruler()
	if saved_ruler == nil then
		saved_ruler = vim.o.ruler
	end
	vim.o.ruler = false
end

local function restore_ruler()
	if saved_ruler ~= nil then
		vim.o.ruler = saved_ruler
		saved_ruler = nil
	end
end

local function save_term_height()
	if vim.fn.exists("t:term_bufnr") ~= 0 and vim.t.term_prev_height == nil and not vim.t.term_zoom then
		local wins = vim.t.term_winids or {}
		if #wins > 0 and win_valid(wins[1]) then
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

-------------------------------------------------------------------------------
-- Data Model: Groups
--
-- term_order: {{buf1, buf2}, {buf3}, {buf4}} — list of groups
-- term_group_idx: 1-based index of the active group
-- term_group_state: saved state per group {[idx_str] = {widths, focus, views, modes}}
-- term_winids: list of window IDs for panes in the current group
-- term_winbar_winid: window ID of the floating winbar overlay
-------------------------------------------------------------------------------

local function migrate_term_order(order)
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

local function get_term_order()
	local order = vim.t.term_order or {}
	return migrate_term_order(order)
end

local function get_groups()
	local order = get_term_order()

	local valid_order = {}
	local removed = {}
	for gi, group in ipairs(order) do
		local valid_group = {}
		for _, buf in ipairs(group) do
			if vim.fn.bufexists(buf) == 1 and vim.fn.getbufvar(buf, "&buftype") == "terminal" then
				table.insert(valid_group, buf)
			end
		end
		if #valid_group > 0 then
			table.insert(valid_order, valid_group)
		else
			table.insert(removed, gi)
		end
	end

	-- Remap activity keys when groups are removed by filtering
	if #removed > 0 then
		local old = vim.t.term_group_activity or {}
		local new = {}
		local offset = 0
		for i = 1, #order do
			if removed[offset + 1] == i then
				offset = offset + 1
			elseif old[tostring(i)] then
				new[tostring(i - offset)] = true
			end
		end
		vim.t.term_group_activity = new
	end

	vim.t.term_order = valid_order

	vim.t.term_group_idx = clamp(vim.t.term_group_idx or 1, 1, math.max(#valid_order, 1))

	return valid_order
end

local function find_buf_group(bufnr)
	local groups = get_groups()
	for gi, group in ipairs(groups) do
		for pi, buf in ipairs(group) do
			if buf == bufnr then
				return gi, pi
			end
		end
	end
	return nil, nil
end

local function swap_activity(idx1, idx2)
	local activity = vim.t.term_group_activity or {}
	local k1, k2 = tostring(idx1), tostring(idx2)
	activity[k1], activity[k2] = activity[k2], activity[k1]
	vim.t.term_group_activity = activity
end

local function shift_activity_after_remove(removed_idx, total_before)
	local old = vim.t.term_group_activity or {}
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
	vim.t.term_group_activity = new
end

local function add_term_to_order(bufnr, after_bufnr)
	local order = get_term_order()

	for _, group in ipairs(order) do
		for _, buf in ipairs(group) do
			if buf == bufnr then
				return
			end
		end
	end

	if after_bufnr then
		for i, group in ipairs(order) do
			for _, buf in ipairs(group) do
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

local function remove_term_from_order(bufnr)
	local order = get_term_order()
	local total_before = #order

	local removed_group_idx = nil
	local new_order = {}
	for gi, group in ipairs(order) do
		local new_group = {}
		for _, buf in ipairs(group) do
			if buf ~= bufnr then
				table.insert(new_group, buf)
			end
		end
		if #new_group > 0 then
			table.insert(new_order, new_group)
		elseif not removed_group_idx then
			removed_group_idx = gi
		end
	end

	vim.t.term_order = new_order
	vim.t.term_group_idx = clamp(vim.t.term_group_idx or 1, 1, math.max(#new_order, 1))

	if removed_group_idx then
		shift_activity_after_remove(removed_group_idx, total_before)
	end
end

local function add_buf_to_group(bufnr, group_idx, after_pane_idx)
	local order = get_term_order()

	if not order[group_idx] then
		return
	end

	local group = order[group_idx]

	for _, buf in ipairs(group) do
		if buf == bufnr then
			return
		end
	end

	local insert_pos = after_pane_idx and (after_pane_idx + 1) or (#group + 1)
	table.insert(group, insert_pos, bufnr)
	vim.t.term_order = order
end

local function get_current_group()
	local groups = get_groups()
	local idx = vim.t.term_group_idx or 1
	if idx < 1 or idx > #groups then
		return nil, idx
	end
	return groups[idx], idx
end

local function adopt_orphaned_terminals()
	local owned = {}
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local ok, order = pcall(vim.api.nvim_tabpage_get_var, tab, "term_order")
		if ok and order then
			order = migrate_term_order(order)
			for _, group in ipairs(order) do
				for _, buf in ipairs(group) do
					owned[buf] = true
				end
			end
		end
	end

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" and not owned[buf] then
			add_term_to_order(buf)
		end
	end
end

-- Forward declarations
local update_winbar_overlay
local destroy_winbar_overlay
local setup_vars

-------------------------------------------------------------------------------
-- Group State Helpers
-------------------------------------------------------------------------------

local function get_group_state(group_idx)
	local group_state = vim.t.term_group_state or {}
	return group_state[tostring(group_idx)] or {}
end

local function set_group_state(group_idx, st)
	local group_state = vim.t.term_group_state or {}
	group_state[tostring(group_idx)] = st
	vim.t.term_group_state = group_state
end

--------------------------------------------------------------------------------
-- Floating Winbar Overlay
--------------------------------------------------------------------------------

local winbar_bufnr = nil
local winbar_ns = vim.api.nvim_create_namespace("terminal_winbar")
local winbar_click_ranges = {}

local function get_winbar_title(group)
	local buf = group[1]
	local title = vim.b[buf].term_title or vim.api.nvim_buf_get_name(buf)
	title = vim.fn.substitute(title, "\\v([^/~ ]+)/", "\\=strpart(submatch(1), 0, 1) . '/'", "g")
	return title
end

local function render_winbar_content()
	if not winbar_bufnr or not vim.api.nvim_buf_is_valid(winbar_bufnr) then
		return
	end

	local groups = get_groups()
	local current_idx = vim.t.term_group_idx or 1

	-- Always clear activity for the current group
	local activity = vim.t.term_group_activity or {}
	activity[tostring(current_idx)] = nil
	vim.t.term_group_activity = activity

	vim.api.nvim_buf_clear_namespace(winbar_bufnr, winbar_ns, 0, -1)
	winbar_click_ranges = {}

	local parts = {}
	local byte_offset = 0

	for i, group in ipairs(groups) do
		local title = get_winbar_title(group)
		local group_activity = vim.t.term_group_activity or {}
		local has_activity = i ~= current_idx and group_activity[tostring(i)] or false
		local label = " " .. i .. ":" .. title .. (has_activity and "*" or "") .. " "
		if #group > 1 then
			label = label .. "[" .. #group .. "] "
		end

		local start_col = byte_offset
		local end_col = byte_offset + #label

		table.insert(parts, label)
		table.insert(winbar_click_ranges, { group_idx = i, start_col = start_col, end_col = end_col })

		byte_offset = end_col
	end

	local line = table.concat(parts)
	vim.api.nvim_buf_set_lines(winbar_bufnr, 0, -1, false, { line })

	for _, range in ipairs(winbar_click_ranges) do
		local hl = range.group_idx == current_idx and "WinBarActive" or "WinBar"
		vim.api.nvim_buf_add_highlight(winbar_bufnr, winbar_ns, hl, 0, range.start_col, range.end_col)
	end
end

local function get_term_windows()
	local group = get_current_group()
	if not group then
		return {}
	end

	local group_bufs = {}
	for _, buf in ipairs(group) do
		group_bufs[buf] = true
	end

	local wins = {}
	local float_mode = is_float_mode()

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if group_bufs[buf] then
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

local function is_in_term_window()
	local wins = vim.t.term_winids or {}
	local current = vim.fn.win_getid()
	for _, win in ipairs(wins) do
		if win == current then
			return true
		end
	end
	return false
end

local function get_winbar_overlay_config()
	local wins = vim.t.term_winids or {}
	if #wins == 0 then
		return nil
	end

	local first_win = nil
	for _, win in ipairs(wins) do
		if win_valid(win) then
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
		if win_valid(win) then
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

	if is_float_mode() then
		return {
			relative = "editor",
			row = row,
			col = col,
			width = total_width,
			height = 1,
			style = "minimal",
			border = "none",
			zindex = 60,
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

update_winbar_overlay = function()
	if not M.config.winbar then
		return
	end

	local groups = get_groups()
	if #groups == 0 then
		destroy_winbar_overlay()
		return
	end

	local wins = vim.t.term_winids or {}
	local any_open = false
	for _, win in ipairs(wins) do
		if win_valid(win) then
			any_open = true
			break
		end
	end
	if not any_open then
		destroy_winbar_overlay()
		return
	end

	if not winbar_bufnr or not vim.api.nvim_buf_is_valid(winbar_bufnr) then
		winbar_bufnr = vim.api.nvim_create_buf(false, true)
		vim.bo[winbar_bufnr].bufhidden = "hide"
		vim.bo[winbar_bufnr].buftype = "nofile"
	end

	render_winbar_content()

	local config = get_winbar_overlay_config()
	if not config then
		destroy_winbar_overlay()
		return
	end

	local winbar_winid = vim.t.term_winbar_winid
	if win_valid(winbar_winid) then
		vim.api.nvim_win_set_config(winbar_winid, config)
		vim.api.nvim_win_set_buf(winbar_winid, winbar_bufnr)
	else
		winbar_winid = vim.api.nvim_open_win(winbar_bufnr, false, config)
		vim.t.term_winbar_winid = winbar_winid
		vim.wo[winbar_winid].winhighlight = "Normal:WinBar"
		vim.wo[winbar_winid].winblend = 0
		vim.wo[winbar_winid].cursorline = false
		vim.wo[winbar_winid].number = false
		vim.wo[winbar_winid].relativenumber = false
		vim.wo[winbar_winid].signcolumn = "no"
	end
end

destroy_winbar_overlay = function()
	local winbar_winid = vim.t.term_winbar_winid
	if winbar_winid and vim.api.nvim_win_is_valid(winbar_winid) then
		vim.api.nvim_win_close(winbar_winid, true)
	end
	vim.t.term_winbar_winid = nil
end

--------------------------------------------------------------------------------
-- Float statusline overlays
--------------------------------------------------------------------------------

local stl_ns = vim.api.nvim_create_namespace("terminal_stl")

local function render_stl_overlay(stl_buf, win, width)
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

	vim.api.nvim_buf_clear_namespace(stl_buf, stl_ns, 0, -1)
	vim.api.nvim_buf_set_lines(stl_buf, 0, -1, false, { result.str })

	for i, hl in ipairs(result.highlights) do
		local end_pos = (result.highlights[i + 1] and result.highlights[i + 1].start) or #result.str
		if hl.group and hl.group ~= "" then
			vim.api.nvim_buf_add_highlight(stl_buf, stl_ns, hl.group, 0, hl.start, end_pos)
		end
	end
end

local function close_stl_windows()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
		if ok and vim.b[buf].terminal_stl then
			vim.api.nvim_win_close(win, true)
		end
	end
end

local function update_float_statuslines()
	if not vim.t.term_zoom then
		close_stl_windows()
		return
	end
	local wins = vim.t.term_winids or {}
	if #wins == 0 then
		close_stl_windows()
		return
	end

	close_stl_windows()

	local current_win = vim.fn.win_getid()

	for _, win in ipairs(wins) do
		if not win_valid(win) then
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
		local stl_col = cfg.col + ((idx and idx > 1 and #wins > 1) and 1 or 0)
		local hl = (win == current_win) and "Normal:StatusLine" or "Normal:StatusLineNC"

		local stl_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[stl_buf].bufhidden = "wipe"
		vim.bo[stl_buf].buftype = "nofile"
		vim.b[stl_buf].terminal_stl = true
		render_stl_overlay(stl_buf, win, width)
		local stl_win = vim.api.nvim_open_win(stl_buf, false, {
			relative = "editor",
			row = stl_row,
			col = stl_col,
			width = width,
			height = 1,
			style = "minimal",
			border = "none",
			zindex = 61,
			focusable = false,
		})
		vim.wo[stl_win].winhighlight = hl
		vim.wo[stl_win].winblend = 0
		vim.wo[stl_win].cursorline = false

		::continue::
	end
end

--------------------------------------------------------------------------------
-- Float pane layout and draggable borders
--------------------------------------------------------------------------------

-- Apply widths to all float pane windows
local function apply_float_pane_layout(widths)
	local wins = vim.t.term_winids or {}
	if #wins == 0 then
		return
	end

	local first_cfg = vim.api.nvim_win_get_config(wins[1])
	local col = first_cfg.col

	for i, win in ipairs(wins) do
		if win_valid(win) then
			local cfg = vim.api.nvim_win_get_config(win)
			cfg.col = col
			cfg.width = widths[i]
			vim.api.nvim_win_set_config(win, cfg)
		end
		-- Advance: pane 1 has no left border; panes 2+ have left border (+1)
		if i == 1 then
			col = col + widths[i]
		else
			col = col + 1 + widths[i]
		end
	end
	update_float_statuslines()
end

local function save_pane_widths()
	local wins = vim.t.term_winids or {}
	if #wins < 2 then
		return
	end
	local _, group_idx = get_current_group()
	if not group_idx then
		return
	end
	local widths = {}
	for i, win in ipairs(wins) do
		if win_valid(win) then
			widths[i] = vim.api.nvim_win_get_width(win)
		end
	end
	local st = get_group_state(group_idx)
	st.widths = widths
	set_group_state(group_idx, st)
end

local function equalize_panes()
	local wins = vim.t.term_winids or {}
	if #wins < 2 then
		return
	end
	local total = 0
	for _, win in ipairs(wins) do
		if win_valid(win) then
			total = total + vim.api.nvim_win_get_width(win)
		end
	end
	local widths = compute_equal_widths(total, #wins)
	if is_float_mode() then
		apply_float_pane_layout(widths)
	else
		for i, win in ipairs(wins) do
			if win_valid(win) then
				vim.api.nvim_win_set_width(win, widths[i])
			end
		end
	end
	save_pane_widths()
end

-- Resize pane_idx by delta, cascading to neighbors when they hit min width
local function calc_resized_widths(widths, pane_idx, delta)
	local new_widths = {}
	for i, w in ipairs(widths) do
		new_widths[i] = w
	end

	if delta > 0 then
		-- Growing: take from right neighbors first, then left
		local remaining = delta
		for i = pane_idx + 1, #new_widths do
			local take = math.min(new_widths[i] - 1, remaining)
			if take > 0 then
				new_widths[i] = new_widths[i] - take
				remaining = remaining - take
			end
			if remaining <= 0 then
				break
			end
		end
		if remaining > 0 then
			for i = pane_idx - 1, 1, -1 do
				local take = math.min(new_widths[i] - 1, remaining)
				if take > 0 then
					new_widths[i] = new_widths[i] - take
					remaining = remaining - take
				end
				if remaining <= 0 then
					break
				end
			end
		end
		new_widths[pane_idx] = new_widths[pane_idx] + (delta - remaining)
	else
		-- Shrinking: take from left neighbors, give to right neighbor
		local remaining = -delta
		for i = pane_idx, 1, -1 do
			local take = math.min(new_widths[i] - 1, remaining)
			if take > 0 then
				new_widths[i] = new_widths[i] - take
				remaining = remaining - take
			end
			if remaining <= 0 then
				break
			end
		end
		local gave = -delta - remaining
		if pane_idx < #new_widths then
			new_widths[pane_idx + 1] = new_widths[pane_idx + 1] + gave
		elseif pane_idx > 1 then
			new_widths[pane_idx - 1] = new_widths[pane_idx - 1] + gave
		end
	end

	return new_widths
end

local function get_sep_screen_col(sep_idx)
	local wins = vim.t.term_winids or {}
	if sep_idx < 1 or sep_idx >= #wins then return nil end
	local win = wins[sep_idx]
	if not win_valid(win) then return nil end
	local cfg = vim.api.nvim_win_get_config(win)
	local width = vim.api.nvim_win_get_width(win)
	-- Right border position: for pane 1 (no left border) it's cfg.col + width
	-- For pane i>1 (has left border) it's cfg.col + 1 + width
	if sep_idx == 1 then
		return cfg.col + width
	else
		return cfg.col + 1 + width
	end
end

local function setup_term_mouse_mappings(bufnr)
	for _, mode in ipairs({ "n", "t" }) do
		vim.api.nvim_buf_set_keymap(bufnr, mode, "<LeftMouse>", "", {
			noremap = true,
			expr = true,
			callback = function()
				local mouse = vim.fn.getmousepos()

				-- Handle winbar click without changing focus/mode
				if mouse.winid == vim.t.term_winbar_winid then
					local col = mouse.column - 1
					for _, range in ipairs(winbar_click_ranges) do
						if col >= range.start_col and col < range.end_col then
							vim.schedule(function()
								M.go_to(range.group_idx)
							end)
							break
						end
					end
					return ""
				end

				if not is_float_mode() or not is_term_open() then
					return vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true)
				end
				local screencol = mouse.screencol - 1
				local wins = vim.t.term_winids or {}
				for i = 1, #wins - 1 do
					local sc = get_sep_screen_col(i)
					if sc and screencol == sc then
						drag_state = { sep_idx = i }
						-- Match Neovim's behaviour of exiting to normal mode when resizing
						vim.schedule(function()
							vim.cmd("stopinsert")
						end)
						return ""
					end
				end
				return vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true)
			end,
		})

		vim.api.nvim_buf_set_keymap(bufnr, mode, "<LeftDrag>", "", {
			noremap = true,
			expr = true,
			callback = function()
				if vim.fn.getmousepos().winid == vim.t.term_winbar_winid then
					return ""
				end
				if not drag_state then
					return vim.api.nvim_replace_termcodes("<LeftDrag>", true, true, true)
				end
				local mouse = vim.fn.getmousepos()
				local mouse_col = mouse.screencol - 1
				local pane_wins = vim.t.term_winids or {}
				if not pane_wins[drag_state.sep_idx] then return "" end
				if not win_valid(pane_wins[drag_state.sep_idx]) then return "" end

				local widths = {}
				for i, win in ipairs(pane_wins) do
					if win_valid(win) then
						widths[i] = vim.api.nvim_win_get_width(win)
					else
						return ""
					end
				end

				local current_sep_col = get_sep_screen_col(drag_state.sep_idx)
				if not current_sep_col then return "" end
				local delta = mouse_col - current_sep_col
				if delta == 0 then return "" end

				local new_widths = calc_resized_widths(widths, drag_state.sep_idx, delta)
				vim.schedule(function()
					apply_float_pane_layout(new_widths)
				end)
				return ""
			end,
		})

		for _, event in ipairs({
			"<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>",
			"<2-LeftRelease>", "<3-LeftRelease>", "<4-LeftRelease>",
			"<2-LeftDrag>", "<3-LeftDrag>", "<4-LeftDrag>",
		}) do
			vim.api.nvim_buf_set_keymap(bufnr, mode, event, "", {
				noremap = true,
				expr = true,
				callback = function()
					if vim.fn.getmousepos().winid == vim.t.term_winbar_winid then
						return ""
					end
					return vim.api.nvim_replace_termcodes(event, true, true, true)
				end,
			})
		end

		vim.api.nvim_buf_set_keymap(bufnr, mode, "<LeftRelease>", "", {
			noremap = true,
			expr = true,
			callback = function()
				if vim.fn.getmousepos().winid == vim.t.term_winbar_winid then
					return ""
				end
				if not drag_state then
					return vim.api.nvim_replace_termcodes("<LeftRelease>", true, true, true)
				end
				vim.schedule(function()
					save_pane_widths()
				end)
				drag_state = nil
				return ""
			end,
		})
	end
end

--------------------------------------------------------------------------------
-- Window management
--------------------------------------------------------------------------------

local function get_float_win_config()
	if vim.t.term_zoom then
		local tabline_height = 0
		if M.config.float_zoom_show_tabline and vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1) then
			tabline_height = 1
		end
		return {
			relative = "editor",
			width = vim.o.columns,
			height = vim.o.lines - vim.o.cmdheight - tabline_height,
			row = tabline_height,
			col = 0,
			style = "minimal",
			border = "none",
		}
	end

	local float_config = {
		padding = { x = 24, y = 4 },
		border = "rounded",
	}

	if type(M.config.float) == "table" then
		float_config = vim.tbl_extend("force", float_config, M.config.float)
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
		style = "minimal",
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

local function save_group_state()
	local _, group_idx = get_current_group()
	if not group_idx then
		return
	end

	local wins = get_term_windows()
	if #wins == 0 then
		return
	end

	local prev_state = get_group_state(group_idx)

	local state = {
		widths = prev_state.widths,
		focus = 1,
		views = {},
		modes = {},
	}

	local current_win = vim.fn.win_getid()
	for i, win in ipairs(wins) do
		if win_valid(win) then
			state.views[i] = vim.api.nvim_win_call(win, function()
				return vim.fn.winsaveview()
			end)
			local buf = vim.api.nvim_win_get_buf(win)
			state.modes[i] = vim.b[buf].term_mode or "t"
			if win == current_win then
				state.focus = i
			end
		end
	end

	set_group_state(group_idx, state)
end

local function close_pane_windows()
	restore_cmdheight()
	restore_ruler()
	destroy_winbar_overlay()
	close_stl_windows()

	local wins = vim.t.term_winids or {}
	for _, win in ipairs(wins) do
		if win_valid(win) then
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
end

local function open_group_windows(group, group_idx)
	if not group or #group == 0 then
		return
	end

	if vim.t.term_zoom then
		set_zoom_cmdheight()
		set_zoom_ruler()
	end

	local state = get_group_state(group_idx)

	local wins = {}
	local scratches = {}
	local height = vim.t.term_height or get_term_height()

	local has_stl = false

	if is_float_mode() then
		local base_config = get_float_win_config()
		local num_panes = #group
		local total_width = base_config.width

		-- Calculate pane widths
		local pane_widths = {}
		local content_available = total_width - (num_panes - 1)
		if state.widths and #state.widths == num_panes then
			local sum = 0
			for i = 1, num_panes do
				sum = sum + (state.widths[i] or 1)
			end
			if sum == content_available then
				for i = 1, num_panes do
					pane_widths[i] = state.widths[i]
				end
			else
				local allocated = 0
				for i = 1, num_panes - 1 do
					pane_widths[i] = math.max(3,
						math.floor((state.widths[i] or 1) * content_available / sum))
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
		local fillchar = vim.opt.fillchars:get().vert or "│"
		for i in ipairs(group) do
			local has_left = (i > 1)
			local has_right = (i < num_panes)
			local border = "none"
			if has_left or has_right then
				border = {
					"", "", "",
					has_right and { fillchar, "WinSeparator" } or "",
					"", "", "",
					has_left and { fillchar, "WinSeparator" } or "",
				}
			end

			local config = vim.tbl_extend("force", {}, base_config)
			config.width = pane_widths[i]
			config.height = base_config.height - stl_height
			config.col = base_config.col + col_offset
			config.border = border
			config.zindex = 50

			-- Advance col_offset past this pane
			if i == 1 then
				col_offset = col_offset + pane_widths[i]
			else
				col_offset = col_offset + 1 + pane_widths[i]
			end

			local win, scratch = open_window(config)
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

		for i = 2, #group do
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
			if state.widths and #state.widths == #wins then
				widths = state.widths
			else
				local total = 0
				for _, win in ipairs(wins) do
					total = total + vim.api.nvim_win_get_width(win)
				end
				widths = compute_equal_widths(total, #wins)
			end
			for i, win in ipairs(wins) do
				if widths[i] and win_valid(win) then
					vim.api.nvim_win_set_width(win, widths[i])
				end
			end
		end
	end

	for _, win in ipairs(wins) do
		if win_valid(win) then
			vim.wo[win].signcolumn = "no"
			vim.wo[win].foldcolumn = "0"
			vim.wo[win].number = false
			vim.wo[win].relativenumber = false
			vim.wo[win].scrolloff = 0
			vim.wo[win].sidescrolloff = 0
			vim.wo[win].winblend = 0
		end
	end

	-- Set terminal buffers after layout is configured to avoid corrupting
	-- the terminal display (e.g. when switching tabs)
	for i, win in ipairs(wins) do
		if win_valid(win) then
			vim.api.nvim_win_set_buf(win, group[i])
			if M.config.winbar then
				vim.wo[win].winbar = " "
			end
		end
	end
	for _, scratch in ipairs(scratches) do
		if vim.api.nvim_buf_is_valid(scratch) then
			vim.api.nvim_buf_delete(scratch, { force = true })
		end
	end

	local focus_idx = state.focus or 1
	if state.views then
		for i, win in ipairs(wins) do
			if win_valid(win) and state.views[i] then
				vim.api.nvim_win_call(win, function()
					vim.fn.winrestview(state.views[i])
				end)
			end
		end
	end

	focus_idx = clamp(focus_idx, 1, #wins)

	if wins[focus_idx] and win_valid(wins[focus_idx]) then
		vim.api.nvim_set_current_win(wins[focus_idx])
	end

	vim.t.term_winids = wins
	vim.t.term_winid = wins[focus_idx] or wins[1]
	vim.t.term_bufnr = group[focus_idx] or group[1]
	vim.t.term_group_idx = group_idx

	-- Clear activity flag now that term_group_idx is set
	local activity = vim.t.term_group_activity or {}
	activity[tostring(group_idx)] = nil
	vim.t.term_group_activity = activity

	-- Raise active pane's z-index
	if is_float_mode() and #wins > 1 then
		for _, win in ipairs(wins) do
			if win_valid(win) then
				local cfg = vim.api.nvim_win_get_config(win)
				if cfg.relative and cfg.relative ~= "" then
					cfg.zindex = (win == vim.t.term_winid) and 51 or 50
					vim.api.nvim_win_set_config(win, cfg)
				end
			end
		end
	end

	local mode_to_restore = "t"
	if state.modes and state.modes[focus_idx] then
		mode_to_restore = state.modes[focus_idx]
	end
	if mode_to_restore ~= "n" then
		vim.cmd("startinsert")
	else
		vim.cmd("stopinsert")
	end

	update_float_statuslines()
	update_winbar_overlay()
end

local function reopen_current_group(target_idx)
	local groups = get_groups()
	if #groups == 0 then
		vim.t.term_winid = nil
		vim.t.term_winids = {}
		vim.t.term_bufnr = nil
		return
	end
	target_idx = target_idx or vim.t.term_group_idx or 1
	target_idx = clamp(target_idx, 1, #groups)
	open_group_windows(groups[target_idx], target_idx)
end

local function rebuild_group(target_idx)
	save_group_state()
	close_pane_windows()
	reopen_current_group(target_idx)
end

local function switch_to_group(target_idx)
	set_toggling()
	rebuild_group(target_idx)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.toggle(opts)
	set_toggling()

	local height = vim.v.count1

	if #vim.api.nvim_tabpage_list_wins(0) == 1 and not is_float_mode() then
		vim.t.term_winid = nil
		vim.t.term_winids = {}
	end

	local is_open = is_term_open()
	if not is_open and vim.t.term_winid and vim.t.term_winid ~= 0 and win_valid(vim.t.term_winid) then
		is_open = true
	end
	-- In non-float mode with only 1 window total, terminal is not meaningfully open
	if is_open and not is_float_mode() then
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
		save_group_state()
		if win_valid(vim.t.term_winid) then
			vim.t.term_bufnr = vim.api.nvim_win_get_buf(vim.t.term_winid)
			vim.t.term_mode = vim.fn.mode()
			vim.b[vim.t.term_bufnr].term_view = vim.fn.winsaveview()
		end
		close_pane_windows()
	else
		-- Open
		vim.t.prev_winid = vim.fn.win_getid()

		local group, group_idx = get_current_group()

		if group and #group > 0 then
			if height > 1 then
				vim.t.term_height = height
			end
			open_group_windows(group, group_idx)
		else
			-- Create a new terminal and open it via open_group_windows
			local bufnr = vim.api.nvim_create_buf(false, true)
			local order = get_term_order()
			table.insert(order, { bufnr })
			vim.t.term_order = order
			vim.t.term_group_idx = #order
			vim.api.nvim_buf_call(bufnr, function()
				vim.fn.termopen(vim.env.SHELL)
			end)
			reopen_current_group()
		end
	end
end

function M.zoom()
	set_toggling()

	if M.config.float then
		vim.t.term_zoom = not vim.t.term_zoom
		rebuild_group()
		return
	end

	if M.config.float_zoom then
		if not is_term_open() then
			return
		end

		save_group_state()

		if not vim.t.term_zoom then
			save_term_height()
			vim.t.term_zoom = true
		else
			vim.t.term_zoom = nil
		end

		close_pane_windows()
		reopen_current_group()
		return
	end

	-- Non-float, non-float_zoom: old height toggle behavior
	if vim.t.term_prev_height == nil then
		vim.t.term_prev_height = vim.t.term_height
		vim.cmd("resize")
		local wins2 = vim.t.term_winids or {}
		if #wins2 > 0 and win_valid(wins2[1]) then
			vim.t.term_height = vim.api.nvim_win_get_height(wins2[1])
		end
	else
		vim.t.term_height = vim.t.term_prev_height
		vim.t.term_prev_height = nil
	end
	local wins2 = vim.t.term_winids or {}
	if #wins2 > 0 and win_valid(wins2[1]) then
		vim.api.nvim_win_call(wins2[1], function()
			vim.cmd("resize " .. vim.t.term_height)
		end)
	end
end

function M.reset_height()
	if vim.t.term_prev_height ~= nil or vim.t.term_zoom then
		return
	end
	vim.t.term_height = get_term_height()
	local wins = vim.t.term_winids or {}
	if #wins > 0 and win_valid(wins[1]) then
		vim.api.nvim_win_call(wins[1], function()
			vim.cmd("resize " .. vim.t.term_height)
		end)
	end
end

--------------------------------------------------------------------------------
-- Buffer switching
--------------------------------------------------------------------------------

function M.switch(delta, clamp_range)
	local groups = get_groups()
	if #groups == 0 then
		return
	end

	if not is_term_open() then
		return
	end

	local current_idx = vim.t.term_group_idx or 1
	local target_idx

	if clamp_range then
		target_idx = math.max(1, math.min(#groups, current_idx + delta))
	else
		target_idx = ((current_idx + delta - 1) % #groups) + 1
	end

	if target_idx == current_idx then
		return
	end

	switch_to_group(target_idx)
end

function M.go_to(index)
	local groups = get_groups()
	if index < 1 or index > #groups then
		return
	end

	local current_idx = vim.t.term_group_idx or 1
	if index == current_idx then
		return
	end

	if not is_term_open() then
		return
	end

	switch_to_group(index)
end

function M.move(direction)
	local groups = get_groups()
	if #groups < 2 then
		return
	end

	local current_idx = vim.t.term_group_idx or 1
	local new_idx = ((current_idx + direction - 1) % #groups) + 1

	local order = get_term_order()

	order[current_idx], order[new_idx] = order[new_idx], order[current_idx]
	vim.t.term_order = order

	local s1, s2 = get_group_state(current_idx), get_group_state(new_idx)
	set_group_state(current_idx, s2)
	set_group_state(new_idx, s1)

	swap_activity(current_idx, new_idx)

	vim.t.term_group_idx = new_idx

	update_winbar_overlay()
end

function M.move_to_tab(direction)
	if not is_in_term_window() then
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

	local group, group_idx = get_current_group()
	if not group then
		return
	end

	save_group_state()
	close_pane_windows()

	-- Remove group from current tab
	local order = get_term_order()
	local total_before = #order
	table.remove(order, group_idx)
	vim.t.term_order = order

	shift_activity_after_remove(group_idx, total_before)

	-- Add group to target tab before opening remaining groups, so
	-- adopt_orphaned_terminals() (triggered by WinEnter) doesn't re-adopt
	-- the moved buffers into the source tab.
	local ok, target_order = pcall(vim.api.nvim_tabpage_get_var, target_tab, "term_order")
	if not ok then
		target_order = {}
	end
	target_order = migrate_term_order(target_order)
	table.insert(target_order, group)
	vim.api.nvim_tabpage_set_var(target_tab, "term_order", target_order)

	local new_idx2 = clamp(vim.t.term_group_idx or 1, 1, math.max(#order, 1))
	vim.t.term_group_idx = new_idx2

	set_toggling()
	local groups = get_groups()
	if #groups > 0 and new_idx2 >= 1 and new_idx2 <= #groups then
		open_group_windows(groups[new_idx2], new_idx2)
	else
		vim.t.term_winid = nil
		vim.t.term_winids = {}
		vim.t.term_bufnr = nil
	end

	-- Switch to target tab
	vim.api.nvim_set_current_tabpage(target_tab)
	setup_vars()

	local target_groups = get_groups()
	local target_group_idx = #target_groups

	local target_open = false
	local target_wins = vim.t.term_winids or {}
	for _, win in ipairs(target_wins) do
		if win_valid(win) then
			target_open = true
			break
		end
	end

	if target_open then
		save_group_state()
		close_pane_windows()
	end

	vim.t.term_group_idx = target_group_idx
	open_group_windows(target_groups[target_group_idx], target_group_idx)
end

function M.go_to_notification()
	if not last_notification_bufnr or not vim.api.nvim_buf_is_valid(last_notification_bufnr) then
		vim.notify("No recent notification", vim.log.levels.WARN)
		return
	end

	local bufnr = last_notification_bufnr

	-- Find which tab owns this buffer
	local target_tab = nil
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local ok, order = pcall(vim.api.nvim_tabpage_get_var, tab, "term_order")
		if ok and order then
			order = migrate_term_order(order)
			for _, group in ipairs(order) do
				for _, buf in ipairs(group) do
					if buf == bufnr then
						target_tab = tab
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
		last_notification_bufnr = nil
		return
	end

	set_toggling()

	-- Switch to the target tab if needed
	if target_tab ~= vim.api.nvim_get_current_tabpage() then
		vim.api.nvim_set_current_tabpage(target_tab)
		setup_vars()
	end

	-- Open terminal if not already open
	if not is_term_open() then
		M.toggle({ open = true })
	end

	-- Find the group/pane index now (after groups are validated)
	local group_idx, pane_idx = find_buf_group(bufnr)
	if not group_idx then
		return
	end

	local current_idx = vim.t.term_group_idx or 1
	if group_idx ~= current_idx then
		save_group_state()
		close_pane_windows()

		local st = get_group_state(group_idx)
		st.focus = pane_idx
		set_group_state(group_idx, st)

		reopen_current_group(group_idx)
	else
		-- Already on the right group, just focus the pane
		local wins = vim.t.term_winids or {}
		if pane_idx and pane_idx <= #wins and win_valid(wins[pane_idx]) then
			vim.api.nvim_set_current_win(wins[pane_idx])
			local mode = vim.b[bufnr].term_mode
			if mode == "t" or mode == nil then
				vim.cmd("startinsert")
			else
				vim.cmd("stopinsert")
			end
			update_float_statuslines()
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
	set_toggling()

	if vim.bo.buftype ~= "terminal" then
		return
	end

	local bufnr = vim.fn.bufnr()

	if term_has_foreground_process(bufnr) then
		if vim.fn.confirm("Terminal has a running process. Close anyway?", "&Yes\n&No", 2) ~= 1 then
			return
		end
	end

	local group_idx, _ = find_buf_group(bufnr)
	if not group_idx then
		return
	end

	local groups = get_groups()
	local group = groups[group_idx]

	if #group == 1 then
		save_group_state()
		close_pane_windows()
		remove_term_from_order(bufnr)
		vim.api.nvim_buf_delete(bufnr, { force = true })
		reopen_current_group()
	else
		save_group_state()
		close_pane_windows()

		local order = get_term_order()
		local g = order[group_idx]
		local new_g = {}
		for _, buf in ipairs(g) do
			if buf ~= bufnr then
				table.insert(new_g, buf)
			end
		end
		order[group_idx] = new_g
		vim.t.term_order = order

		local st = get_group_state(group_idx)
		st.widths = nil
		if st.focus and st.focus > #new_g then
			st.focus = #new_g
		end
		set_group_state(group_idx, st)

		vim.api.nvim_buf_delete(bufnr, { force = true })
		reopen_current_group(group_idx)
	end
end

function M.new()
	set_toggling()

	local _, current_idx = get_current_group()

	save_group_state()
	close_pane_windows()

	local bufnr = vim.api.nvim_create_buf(false, true)

	-- Add to order before termopen so TermOpen autocmd doesn't double-add
	local order = get_term_order()
	local insert_idx = (current_idx or #order) + 1
	table.insert(order, insert_idx, { bufnr })
	vim.t.term_order = order
	vim.t.term_group_idx = insert_idx

	vim.api.nvim_buf_call(bufnr, function()
		vim.fn.termopen(vim.env.SHELL)
	end)

	open_group_windows({ bufnr }, insert_idx)
end

function M.vsplit()
	set_toggling()

	local group, group_idx = get_current_group()
	if not group then
		M.toggle({ open = true })
		return
	end

	-- Find current pane index before closing windows
	local current_bufnr = vim.fn.bufnr()
	local _, current_pane_idx = find_buf_group(current_bufnr)

	save_group_state()
	close_pane_windows()

	local bufnr = vim.api.nvim_create_buf(false, true)

	-- Add to group after current pane, before termopen so TermOpen autocmd doesn't double-add
	add_buf_to_group(bufnr, group_idx, current_pane_idx)

	vim.api.nvim_buf_call(bufnr, function()
		vim.fn.termopen(vim.env.SHELL)
	end)

	local insert_pos = (current_pane_idx or #group) + 1
	local st = get_group_state(group_idx)
	st.widths = nil
	st.focus = insert_pos
	set_group_state(group_idx, st)

	reopen_current_group(group_idx)
end

function M.next()
	M.switch(1)
end

function M.prev()
	M.switch(-1)
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

setup_vars = function()
	vim.t.term_winid = vim.t.term_winid or 0
	vim.t.term_winids = vim.t.term_winids or {}
	vim.t.term_height = vim.t.term_height or get_term_height()
	vim.t.term_group_idx = vim.t.term_group_idx or 1
	vim.t.term_group_state = vim.t.term_group_state or {}
end

local function setup_autocmd()
	vim.api.nvim_create_augroup("Term", {})
	pcall(vim.api.nvim_clear_autocmds, { group = "nvim.terminal", event = "TermClose" })
	vim.api.nvim_create_autocmd("TermOpen", {
		pattern = "*",
		group = "Term",
		callback = function()
			vim.opt_local.signcolumn = "no"
			vim.opt_local.number = false
			vim.opt_local.relativenumber = false
			vim.opt_local.scrolloff = 0
			vim.opt_local.sidescrolloff = 0
			vim.opt_local.winblend = 0
			local bufnr = vim.fn.bufnr()
			if not find_buf_group(bufnr) then
				add_term_to_order(bufnr)
			end
			vim.b.term_mode = "t"
			setup_term_mouse_mappings(bufnr)
			vim.api.nvim_buf_attach(bufnr, false, {
				on_lines = function(_, buf)
					if toggling then
						return
					end
					if not vim.api.nvim_buf_is_valid(buf) then
						return true
					end
					-- Skip if buffer is displayed in a current terminal window
					local wins = vim.t.term_winids or {}
					for _, win in ipairs(wins) do
						if win_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
							return
						end
					end
					local gi = find_buf_group(buf)
					if not gi or gi == (vim.t.term_group_idx or 1) then
						return
					end
					local activity = vim.t.term_group_activity or {}
					if activity[tostring(gi)] then
						return
					end
					activity[tostring(gi)] = true
					vim.t.term_group_activity = activity
					vim.schedule(function()
						update_winbar_overlay()
					end)
				end,
			})
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		pattern = "*:t",
		group = "Term",
		callback = function()
			if vim.bo.buftype == "terminal" then
				vim.b.term_mode = "t"
			end
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		pattern = { "t:nt", "t:n" },
		group = "Term",
		callback = function()
			local bufnr = vim.fn.bufnr()
			local winid = vim.fn.win_getid()
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end
				if vim.fn.win_getid() ~= winid then
					return
				end
				if vim.bo[bufnr].buftype == "terminal" then
					vim.b[bufnr].term_mode = "n"
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("WinResized", {
		pattern = "*",
		group = "Term",
		callback = function()
			if toggling then
				return
			end
			if vim.t.term_bufnr == nil then
				return
			end
			if vim.t.term_prev_height ~= nil or vim.t.term_zoom then
				return
			end
			local wins = vim.t.term_winids or {}
			if #wins > 0 and win_valid(wins[1]) then
				local height = vim.api.nvim_win_get_height(wins[1])
				if height > 0 then
					vim.t.term_height = height
				end
			end
			-- Save pane widths when user explicitly resizes (2+ panes)
			if #wins >= 2 then
				local _, group_idx = get_current_group()
				if group_idx then
					local widths = {}
					local all_valid = true
					for i, win in ipairs(wins) do
						if win_valid(win) then
							widths[i] = vim.api.nvim_win_get_width(win)
						else
							all_valid = false
							break
						end
					end
					if all_valid then
						local st = get_group_state(group_idx)
						st.widths = widths
						set_group_state(group_idx, st)
					end
				end
			end
			update_winbar_overlay()
		end,
	})
	vim.api.nvim_create_autocmd("WinEnter", {
		pattern = "*",
		group = "Term",
		callback = function()
			adopt_orphaned_terminals()

			-- Track focus within pane windows
			local current_win = vim.fn.win_getid()
			local wins = vim.t.term_winids or {}
			for _, win in ipairs(wins) do
				if win == current_win then
					vim.t.term_winid = current_win
					vim.t.term_bufnr = vim.api.nvim_win_get_buf(current_win)

					-- Clear activity for the current group
					local current_group_idx = vim.t.term_group_idx or 1
					local activity = vim.t.term_group_activity or {}
					if activity[tostring(current_group_idx)] then
						activity[tostring(current_group_idx)] = nil
						vim.t.term_group_activity = activity
						update_winbar_overlay()
					end
					break
				end
			end

			-- Raise active pane's z-index so its borders receive clicks
			if is_float_mode() then
				for _, w in ipairs(wins) do
					if win_valid(w) then
						local cfg = vim.api.nvim_win_get_config(w)
						if cfg.relative and cfg.relative ~= "" then
							cfg.zindex = (w == current_win) and 51 or 50
							vim.api.nvim_win_set_config(w, cfg)
						end
					end
				end
			end

			-- Refocus terminal pane if winbar overlay is entered
			if current_win == vim.t.term_winbar_winid then
				vim.schedule(function()
					if vim.fn.win_getid() ~= vim.t.term_winbar_winid then
						return
					end
					local target = vim.t.term_winid
					if win_valid(target) then
						vim.api.nvim_set_current_win(target)
					else
						local term_wins2 = vim.t.term_winids or {}
						for _, win in ipairs(term_wins2) do
							if win_valid(win) then
								vim.api.nvim_set_current_win(win)
								return
							end
						end
					end
				end)
			end
		end,
	})
	vim.api.nvim_create_autocmd("TabNew", {
		pattern = "*",
		group = "Term",
		callback = function()
			vim.t.term_height = get_term_height()
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		pattern = "*",
		group = "Term",
		callback = function()
			if not toggling then
				save_term_height()
			end
			if not toggling and is_float_mode() and is_term_related_window(vim.fn.win_getid()) then
				local tab = vim.api.nvim_get_current_tabpage()
				vim.schedule(function()
					if vim.api.nvim_get_current_tabpage() ~= tab then
						return
					end
					if not is_term_related_window(vim.fn.win_getid()) then
						M.toggle({ open = false })
					end
				end)
			end
		end,
	})

	local function update_float_win_config()
		if not is_float_mode() or not is_term_open() then
			return
		end
		rebuild_group()
	end

	vim.api.nvim_create_autocmd("VimResized", {
		group = "Term",
		callback = function()
			update_float_win_config()
			update_winbar_overlay()
		end,
	})
	vim.api.nvim_create_autocmd("TabEnter", {
		group = "Term",
		callback = function()
			vim.schedule(function()
				adopt_orphaned_terminals()
				update_float_win_config()
				update_winbar_overlay()
			end)
		end,
	})
	vim.api.nvim_create_autocmd("TabClosed", {
		group = "Term",
		callback = function()
			vim.schedule(function()
				update_float_win_config()
				update_winbar_overlay()
			end)
		end,
	})
	vim.api.nvim_create_autocmd("TermClose", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local bufnr = ev.buf
			local group_idx_closed = find_buf_group(bufnr)

			local current_group_idx = vim.t.term_group_idx or 1
			local is_in_active_group = group_idx_closed == current_group_idx

			local is_displayed = is_in_active_group and is_term_open()

			remove_term_from_order(bufnr)

			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end

				if is_displayed then
					rebuild_group()
				else
					update_winbar_overlay()
				end
			end)
		end,
	})
end

local function setup_winbar_autocmds()
	if not M.config.winbar then
		return
	end

	vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter", "BufFilePost" }, {
		pattern = "*",
		group = "Term",
		callback = function()
			if toggling then
				return
			end
			if vim.bo[0].buftype == "terminal" then
				update_winbar_overlay()
			end
		end,
	})

	vim.api.nvim_create_autocmd("TermRequest", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local seq = ev.data.sequence

			if seq:match("^\x1b%]0;") then
				local title = seq:match("\x1b%]0;([^\007]+)")
				if title and #title > 0 then
					local buf = ev.buf
					vim.b[buf].term_title = title
					update_winbar_overlay()
					update_float_statuslines()
				end
			end
		end,
	})
end

local function setup_osc_notifications()
	if not M.config.osc_notifications then
		return
	end

	vim.api.nvim_create_autocmd("TermRequest", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local seq = ev.data.sequence

			if seq:sub(1, 4) ~= "\x1b]9;" and seq:sub(1, 5) ~= "\x1b]99;" and seq:sub(1, 6) ~= "\x1b]777;" then
				return
			end

			-- Pass through to terminal
			vim.loop.write(out_tty, seq)

			-- OSC 9;4 is progress reporting — pass through but don't notify
			if seq:sub(1, 5) == "\x1b]9;4" then
				return
			end

			last_notification_bufnr = ev.buf

			-- Notify when not focused in a terminal buffer
			local is_term_buf = vim.bo.buftype == "terminal"
			if is_term_buf then
				return
			end

			local title, body = seq:match("\x1b%]777;notify;([^;\007]+);([^\007]*)")
			if not body then
				body = seq:match("\x1b%]777;notify;([^\007]*)")
			end
			if not body then
				body = seq:match("\x1b%]99?;([^\007]*)")
			end
			if body then
				title = title or "Terminal notification"
				vim.notify(title .. ": " .. body, vim.log.levels.INFO)
			end
			vim.loop.write(out_tty, "\a")
		end,
	})
end

local function setup_keymap()
	local keys = M.config.keys
	if keys == false then
		return
	end

	local function map(modes, key, action, opts)
		if key == false then
			return
		end
		if type(key) == "table" then
			for _, k in ipairs(key) do
				map(modes, k, action, opts)
			end
			return
		end
		vim.keymap.set(modes, key, action, opts or {})
	end

	map({ "n", "t" }, keys.toggle, M.toggle)
	map("t", keys.normal_mode, "<C-\\><C-n>", { noremap = true })
	map({ "n", "t" }, keys.zoom, M.zoom)
	map({ "n", "t" }, keys.reset_height, M.reset_height)
	map({ "n", "t" }, keys.new, M.new, { noremap = true })
	map({ "n", "t" }, keys.delete, M.delete, { noremap = true })

	map({ "n", "t" }, keys.prev, function()
		M.switch(-1)
	end)
	map({ "n", "t" }, keys.next, function()
		M.switch(1)
	end)

	map({ "n", "t" }, keys.move_prev, function()
		M.move(-1)
	end)
	map({ "n", "t" }, keys.move_next, function()
		M.move(1)
	end)

	map({ "n", "t" }, keys.move_to_tab_prev, function()
		M.move_to_tab(-1)
	end)
	map({ "n", "t" }, keys.move_to_tab_next, function()
		M.move_to_tab(1)
	end)

	map({ "n", "t" }, keys.last_notification, M.go_to_notification, { noremap = true })

	for i = 1, 9 do
		local key = "<C-S-" .. i .. ">"
		if key ~= keys.last_notification then
			vim.keymap.set({ "n", "t" }, key, function()
				M.go_to(i)
			end, { noremap = true })
		end
	end

	local function switch_tab(direction)
		local src_mode = vim.fn.mode()
		if vim.bo.buftype == "terminal" then
			vim.b.term_mode = src_mode
		end
		if src_mode == "t" then
			vim.cmd("stopinsert")
		end
		if direction > 0 then
			vim.cmd("tabnext")
		else
			vim.cmd("tabprevious")
		end
		vim.schedule(function()
			if vim.bo.buftype == "terminal" then
				if vim.b.term_mode == "t" or vim.b.term_mode == nil then
					vim.cmd("startinsert")
				end
			end
		end)
	end

	map({ "n", "t" }, keys.tab_prev, function()
		switch_tab(-1)
	end, { noremap = true })
	map({ "n", "t" }, keys.tab_next, function()
		switch_tab(1)
	end, { noremap = true })

	if keys.paste_register ~= false then
		vim.keymap.set("t", keys.paste_register, function()
			local ok, char = pcall(vim.fn.getchar)
			if not ok or char < 0 then
				return
			end
			local reg = vim.fn.nr2char(char)
			local txt = vim.fn.getreg(reg)

			local job = vim.b.terminal_job_id
			if not job then
				vim.notify("Not in a terminal buffer!", vim.log.levels.WARN)
				return
			end
			vim.api.nvim_chan_send(job, txt)
		end, { noremap = true, silent = true })

		vim.keymap.set("t", keys.paste_register .. "=", function()
			local expr = vim.fn.input("=")
			if expr == "" then
				return
			end

			local ok, result = pcall(vim.fn.eval, expr)
			if not ok then
				vim.notify("Invalid expression: " .. result, vim.log.levels.ERROR)
				return
			end

			local txt = tostring(result)
			local opener = "\027[200~"
			local closer = "\027[201~"

			local job = vim.b.terminal_job_id
			if not job then
				vim.notify("Not in a terminal buffer!", vim.log.levels.WARN)
				return
			end
			vim.api.nvim_chan_send(job, opener .. txt .. closer)
		end, { noremap = true, silent = true })
	end

	-- <C-S-w> prefix: terminal window management
	local function restore_term_mode()
		if vim.b.term_mode == "t" or vim.b.term_mode == nil then
			vim.cmd("startinsert")
		else
			vim.cmd("stopinsert")
		end
	end

	local function pane_navigate(delta)
		local wins = vim.t.term_winids or {}
		local current = vim.fn.win_getid()
		for i, win in ipairs(wins) do
			if win == current then
				local target = i + delta
				if target >= 1 and target <= #wins and win_valid(wins[target]) then
					vim.api.nvim_set_current_win(wins[target])
					restore_term_mode()
					update_float_statuslines()
				end
				return
			end
		end
		-- Fallback to native wincmd in split mode
		if not is_float_mode() then
			vim.cmd("wincmd " .. (delta < 0 and "h" or "l"))
			restore_term_mode()
		end
	end

	local function pane_cycle()
		local wins = vim.t.term_winids or {}
		if #wins < 2 then
			return
		end
		local current = vim.fn.win_getid()
		for i, win in ipairs(wins) do
			if win == current then
				local target = (i % #wins) + 1
				if win_valid(wins[target]) then
					vim.api.nvim_set_current_win(wins[target])
					restore_term_mode()
					update_float_statuslines()
				end
				return
			end
		end
	end

	map({ "n", "t" }, "<C-S-h>", function() pane_navigate(-1) end, { noremap = true })
	map({ "n", "t" }, "<C-S-l>", function() pane_navigate(1) end, { noremap = true })
	map({ "n", "t" }, "<C-S-v>", M.vsplit, { noremap = true })

	local function resize_current_pane(delta)
		local wins = vim.t.term_winids or {}
		local current = vim.fn.win_getid()

		if not is_float_mode() then
			if delta > 0 then
				vim.cmd(delta .. "wincmd >")
			else
				vim.cmd((-delta) .. "wincmd <")
			end
			return
		end

		local pane_idx
		for i, win in ipairs(wins) do
			if win == current then
				pane_idx = i
				break
			end
		end
		if not pane_idx or #wins < 2 then
			return
		end

		local widths = {}
		for i, win in ipairs(wins) do
			if win_valid(win) then
				widths[i] = vim.api.nvim_win_get_width(win)
			else
				return
			end
		end

		local new_widths = calc_resized_widths(widths, pane_idx, delta)
		apply_float_pane_layout(new_widths)
		save_pane_widths()
	end

	local function move_pane_to(target_pos)
		local group, group_idx = get_current_group()
		if not group or #group < 2 then
			return
		end

		local bufnr = vim.fn.bufnr()
		local _, pane_idx = find_buf_group(bufnr)
		if not pane_idx then
			return
		end
		if target_pos == 1 and pane_idx == 1 then
			return
		end
		if target_pos == #group and pane_idx == #group then
			return
		end

		set_toggling()
		save_group_state()
		close_pane_windows()

		local order = get_term_order()
		table.remove(order[group_idx], pane_idx)
		table.insert(order[group_idx], target_pos, bufnr)
		vim.t.term_order = order

		local st = get_group_state(group_idx)
		st.widths = nil
		st.focus = target_pos
		set_group_state(group_idx, st)

		reopen_current_group(group_idx)
	end

	local function rotate_panes(direction)
		local group, group_idx = get_current_group()
		if not group or #group < 2 then
			return
		end

		local bufnr = vim.fn.bufnr()
		local _, pane_idx = find_buf_group(bufnr)
		if not pane_idx then
			return
		end

		set_toggling()

		save_group_state()
		close_pane_windows()

		local order = get_term_order()
		local g = order[group_idx]
		if direction > 0 then
			local last = table.remove(g)
			table.insert(g, 1, last)
		else
			local first = table.remove(g, 1)
			table.insert(g, first)
		end
		vim.t.term_order = order

		local new_pane_idx
		for i, buf in ipairs(g) do
			if buf == bufnr then
				new_pane_idx = i
				break
			end
		end

		local st = get_group_state(group_idx)
		st.widths = nil
		st.focus = new_pane_idx or 1
		set_group_state(group_idx, st)

		reopen_current_group(group_idx)
	end

	if keys.wincmd ~= false then
		local function key_match(c, ...)
			local trans = vim.fn.keytrans(c)
			for _, name in ipairs({ ... }) do
				-- Exact match
				if trans == name then return true end
				-- Case-insensitive match for modified keys only (<C-S-H> matches <C-S-h>)
				if trans:match("^<") and name:match("^<") and trans:lower() == name:lower() then
					return true
				end
			end
			return false
		end

		local function term_wincmd()
			local count = 0

			while true do
				local ok, c = pcall(vim.fn.getcharstr)
				if not ok or c == "" then
					return
				end

				if c >= "0" and c <= "9" then
					count = count * 10 + tonumber(c)
				else
					if count == 0 then
						count = 1
					end

					if key_match(c, "w", "<C-S-w>") then
						pane_cycle()
					elseif key_match(c, "v", "<C-S-v>") then
						M.vsplit()
					elseif key_match(c, "h", "<C-S-h>") then
						pane_navigate(-1)
					elseif key_match(c, "l", "<C-S-l>") then
						pane_navigate(1)
					elseif c == ">" then
						resize_current_pane(count)
					elseif c == "<" then
						resize_current_pane(-count)
					elseif key_match(c, "H", "<S-H>") then
						local group = get_current_group()
						if group then
							move_pane_to(1)
						end
					elseif key_match(c, "L", "<S-L>") then
						local group = get_current_group()
						if group then
							move_pane_to(#group)
						end
					elseif key_match(c, "r", "<C-R>", "<C-S-R>") then
						rotate_panes(1)
					elseif key_match(c, "R", "<S-R>") then
						rotate_panes(-1)
					elseif c == "=" then
						equalize_panes()
					elseif key_match(c, "p", "<C-S-p>") then
						M.toggle({ open = false })
					elseif key_match(c, "c", "<C-S-c>") then
						M.delete()
					elseif key_match(c, "<CR>", "<C-S-CR>") and count > 1 then
						vim.t.term_height = count
						local wins = vim.t.term_winids or {}
						if not is_float_mode() and #wins > 0 and win_valid(wins[1]) then
							vim.api.nvim_win_call(wins[1], function()
								vim.cmd("resize " .. count)
							end)
						end
					end
					return
				end
			end
		end

		map({ "n", "t" }, keys.wincmd, term_wincmd, { noremap = true })
	end

	-- <C-w> overrides for terminal panes (normal mode)
	local function nmap_cw(suffix, action)
		vim.keymap.set({ "n" }, "<C-w>" .. suffix, function()
			if is_in_term_window() then
				action()
			else
				local fallback = vim.api.nvim_replace_termcodes("<C-w>" .. suffix, true, true, true)
				vim.api.nvim_feedkeys(fallback, "n", false)
			end
		end, { noremap = true })
	end

	local cw_actions = {
		{ { "w", "<C-w>" }, pane_cycle },
		{ { "h", "<C-h>" }, function() pane_navigate(-1) end },
		{ { "l", "<C-l>" }, function() pane_navigate(1) end },
		{ { ">" },          function() resize_current_pane(vim.v.count1) end },
		{ { "<lt>" },       function() resize_current_pane(-vim.v.count1) end },
		{ { "=" },          equalize_panes },
		{ { "p", "<C-p>" }, function() M.toggle({ open = false }) end },
		{ { "c", "<C-c>" }, M.delete },
		{ { "v", "<C-v>" }, M.vsplit },
		{ { "H" }, function()
			local g = get_current_group(); if g then move_pane_to(1) end
		end },
		{ { "L" }, function()
			local g = get_current_group(); if g then move_pane_to(#g) end
		end },
		{ { "r", "<C-r>" }, function() rotate_panes(1) end },
		{ { "R" },          function() rotate_panes(-1) end },
	}

	for _, entry in ipairs(cw_actions) do
		for _, suffix in ipairs(entry[1]) do
			nmap_cw(suffix, entry[2])
		end
	end
end

local function setup_command()
	vim.api.nvim_create_user_command("TermSplit", "new | term", {})
	vim.api.nvim_create_user_command("TermVsplit", "vnew | term", {})
	vim.api.nvim_create_user_command("TermTab", function(opts)
		vim.cmd(opts.args .. "tabnew | term")
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("TermDelete", function()
		M.delete()
	end, {})
	vim.api.nvim_create_user_command("TermReset", 'exe "te" | bd!# | let t:term_bufnr = bufnr("%")', {})
end

local function setup_alias()
	utils.alias("tsplit", "TermSplit")
	utils.alias("tvsplit", "TermVsplit")
	utils.alias("ttab", "TermTab")
	utils.alias("tdelete", "TermDelete")
	utils.alias("st", "TermSplit")
	utils.alias("vst", "TermVsplit")
	utils.alias("tt", "TermTab")
	utils.alias("td", "TermDelete")
end

function M.setup(config)
	local default_keys = M.config.keys
	M.config = vim.tbl_extend("force", M.config, config or {})

	if M.config.keys ~= false then
		M.config.keys = vim.tbl_extend("force", default_keys, M.config.keys or {})
	end

	if loaded then
		return
	end

	setup_vars()
	setup_autocmd()
	setup_winbar_autocmds()
	setup_osc_notifications()
	setup_keymap()
	setup_command()
	setup_alias()

	require("terminal.job").setup()
	require("terminal.fugitive").setup()

	loaded = true
end

return M
