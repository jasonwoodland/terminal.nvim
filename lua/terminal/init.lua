-- terminal.nvim

local M = {}

local loaded = false

local config = require("terminal.config")
local state = require("terminal.state")
local mode = require("terminal.mode")
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
	if not is_open and vim.t.term_winid and vim.t.term_winid ~= 0 and state.win_valid(vim.t.term_winid)
		and state.is_managed(vim.api.nvim_win_get_buf(vim.t.term_winid)) then
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
		if state.win_valid(vim.t.term_winid) and state.is_managed(vim.api.nvim_win_get_buf(vim.t.term_winid)) then
			vim.t.term_bufnr = vim.api.nvim_win_get_buf(vim.t.term_winid)
			vim.t.term_mode = vim.api.nvim_get_mode().mode
		end
		window.close_pane_windows()
	else
		-- Open
		vim.t.prev_winid = vim.api.nvim_get_current_win()

		local tab, tab_idx = state.get_current_tab()
		window.refresh_drawer_size()
		if height > 1 then vim.t.term_height = height; vim.t.term_drawer_size = nil end
		if not window.check_size(tab, math.max(#state.get_tabs(), 1)) then return false end

		if tab and #tab.bufs > 0 then
			window.open_tab_windows(tab, tab_idx)
		else
			-- Create a new terminal and open it via open_tab_windows
			local bufnr = vim.api.nvim_create_buf(false, true)
			local order = state.get_term_order()
			table.insert(order, state.new_entry(bufnr))
			state.set_term_order(order)
			vim.t.term_tab_idx = #order
			window.termopen_with_size(bufnr, nil, #order)
			window.reopen_current_tab()
		end
	end
end

function M.zoom()
	state.set_toggling()

	if not state.is_term_open() then
		if config.is_float_config_enabled() or config.config.float_zoom then
			vim.t.term_zoom = true
		end
		M.toggle({ open = true })
		return
	end

	if config.is_float_config_enabled() then
		local previous_zoom = vim.t.term_zoom
		vim.t.term_zoom = (not previous_zoom) and true or nil
		if not window.rebuild_tab() then vim.t.term_zoom = previous_zoom end
		return
	end

	if config.config.float_zoom then
		local previous_zoom = vim.t.term_zoom
		window.save_tab_state()

		if not vim.t.term_zoom then
			state.save_term_height()
			vim.t.term_zoom = true
		else
			vim.t.term_zoom = nil
		end

		if not window.rebuild_tab() then vim.t.term_zoom = previous_zoom end
		return
	end

	-- Non-float, non-float_zoom: old height toggle behavior
	local wins2 = vim.t.term_winids or {}
	if #wins2 == 0 or not state.win_valid(wins2[1]) then
		return
	end
	if vim.t.term_prev_height == nil then
		-- set before resizing so WinResized doesn't overwrite term_height
		vim.t.term_prev_height = state.drawer_span() or vim.t.term_height
		-- maximize; vim/set_drawer_height clamp to the available rows
		window.set_drawer_height(vim.o.lines)
	else
		local target = vim.t.term_prev_height
		vim.t.term_prev_height = nil
		window.set_drawer_height(target)
	end
end

function M.float_toggle()
	state.set_toggling()

	-- Zoom is a layered overlay on top of float/drawer and looks the same in
	-- either base mode, so toggling float while zoomed would be invisible.
	-- Lift the overlay and force float on so the keystroke produces visible
	-- feedback regardless of which base mode the zoom was sitting on top of.
	-- Same reasoning when closed: open in float mode rather than silently
	-- flipping a config the user can't see.
	local force_on = (not state.is_term_open()) or (vim.t.term_zoom ~= nil)
	local target = force_on or (not config.is_float_config_enabled())

	window.save_tab_state()
	local previous_float = vim.t.term_float_enabled
	local previous_zoom, previous_height = vim.t.term_zoom, vim.t.term_prev_height
	local previous_drawer_height = vim.t.term_height
	vim.t.term_zoom = nil
	vim.t.term_prev_height = nil

	vim.t.term_float_enabled = target
	if not target and vim.t.term_drawer_size then
		local _, available = require("terminal.size").available(false)
		vim.t.term_height = require("terminal.size").resolve(vim.t.term_drawer_size, available)
	end

	if not window.check_size(state.get_current_tab()) then
		vim.t.term_float_enabled = previous_float
		vim.t.term_zoom, vim.t.term_prev_height = previous_zoom, previous_height
		vim.t.term_height = previous_drawer_height
		return false
	end
	if state.is_term_open() then
		window.rebuild_tab()
	else
		M.toggle({ open = true })
	end
end

-- Resize the current Vim tab's terminal workspace without starting jobs or
-- opening a hidden workspace. Pane proportions are retained by the renderer.
function M.resize(opts)
	local size = require("terminal.size")
	local requested, err = size.validate(opts)
	if not requested then return false, err end
	local floating = config.is_float_config_enabled()
	if requested.width and not floating then return false, "Drawer width is fixed; use height only" end
	window.save_tab_state()
	local keys = { "term_height", "term_prev_height", "term_zoom", "term_float_size", "term_drawer_size" }
	local previous = {}
	for _, key in ipairs(keys) do previous[key] = vim.t[key] end
	local function rollback()
		for _, key in ipairs(keys) do vim.t[key] = previous[key] end
		state.sync_zoom_options()
	end
	vim.t.term_zoom, vim.t.term_prev_height = nil, nil
	state.sync_zoom_options()
	local width, height = size.available(floating)
	for key, value in pairs(requested) do
		if type(value) == "number" and value > (key == "width" and width or height) then
			rollback()
			return false, "Requested " .. key .. " exceeds the available editor area"
		end
	end
	if floating then
		vim.t.term_float_size = next(requested) and vim.tbl_extend("force", previous.term_float_size or {}, requested) or nil
	else
		vim.t.term_drawer_size = requested.height
		vim.t.term_height = requested.height and size.resolve(requested.height, height) or config.get_term_height()
	end
	if not window.can_open_tab(state.get_current_tab()) then
		rollback()
		return false, "Not enough room for terminal panes"
	end
	if state.is_term_open() then
		local current = vim.api.nvim_get_current_win()
		local editor = not state.is_managed(vim.api.nvim_win_get_buf(current))
		local was_insert = vim.fn.mode():sub(1, 1) == "i"
		state.set_toggling()
		local ok, result = pcall(window.rebuild_tab)
		if not ok or result == false then
			rollback()
			pcall(window.rebuild_tab)
			return false, ok and "Could not resize terminal panes" or tostring(result)
		end
		if editor and state.win_valid(current) then
			vim.api.nvim_set_current_win(current)
			vim.cmd(was_insert and "startinsert" or "stopinsert")
		end
	end
	return true
end

function M.equalize()
	if state.is_term_open() then require("terminal.float_layout").equalize_panes() end
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

local function get_visible_tab_idx(tabs)
	local bufnr = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "terminal" then
		if state.win_valid(vim.t.term_winid) then
			bufnr = vim.api.nvim_win_get_buf(vim.t.term_winid)
		end
	end

	local tab_idx = state.find_buf_tab(bufnr)
	if tab_idx then
		vim.t.term_tab_idx = tab_idx
		return tab_idx
	end

	return state.clamp(vim.t.term_tab_idx or 1, 1, #tabs)
end

function M.move(direction)
	local tabs = state.get_tabs()
	if #tabs < 2 then
		return
	end

	local current_idx = get_visible_tab_idx(tabs)
	local new_idx = ((current_idx + direction - 1) % #tabs) + 1

	-- Entries own their state (widths/focus/modes/activity), so moving the
	-- entry moves everything with it.
	local order = state.get_term_order()
	local entry = table.remove(order, current_idx)
	table.insert(order, new_idx, entry)
	state.set_term_order(order)

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
	window.open_tab_windows(target_tabs[target_tab_idx], target_tab_idx)
end

-- Enumerate managed panes without changing the current Vim tab or window.
-- Buffer numbers are session-local identities; indices are display metadata.
function M.list()
	local result = {}
	for tabnr, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		for tab_index, entry in ipairs(state.get_tabs(tabpage)) do
			for pane_index, bufnr in ipairs(entry.bufs) do
				result[#result + 1] = {
					bufnr = bufnr,
					tabpage = tabpage,
					tabnr = tabnr,
					tab_id = entry.id,
					tab_index = tab_index,
					pane_index = pane_index,
					title = state.get_title(bufnr),
				}
			end
		end
	end
	return result
end

function M.rename(name, bufnr)
	if type(name) ~= "string" then return false, "Terminal name must be a string" end
	if name:find("%c") then return false, "Terminal name must not contain control characters" end
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local target
	for _, item in ipairs(M.list()) do
		if item.bufnr == bufnr then target = item; break end
	end
	if not target then return false, "Terminal is no longer managed" end
	name = vim.trim(name)
	vim.b[bufnr].terminal_custom_name = name ~= "" and name or nil
	if target.tabpage == vim.api.nvim_get_current_tabpage() then winbar.update() end
	return true
end

function M.focus(bufnr)
	local target
	for _, item in ipairs(M.list()) do
		if item.bufnr == bufnr then target = item; break end
	end
	if not target then return false, "Terminal is no longer managed" end

	mode.record()
	if target.tabpage ~= vim.api.nvim_get_current_tabpage() then
		vim.api.nvim_set_current_tabpage(target.tabpage)
		state.setup_vars()
	end
	-- Resolve again after TabEnter: entries can be moved/reordered while a
	-- picker is open, and user autocmds may change ownership on entry.
	local tab_idx, pane_idx = state.find_buf_tab(bufnr)
	if not tab_idx then return false, "Terminal is no longer in its workspace" end
	local entry = state.get_tabs()[tab_idx]
	if not window.check_size(entry) then return false, "Terminal layout does not fit" end

	state.set_toggling()
	if not state.is_term_open() then
		window.save_tab_state()
		local order = state.get_term_order()
		order[tab_idx].focus = bufnr
		state.set_term_order(order)
		vim.t.prev_winid = vim.api.nvim_get_current_win()
		if not window.open_tab_windows(order[tab_idx], tab_idx) then
			return false, "Terminal workspace could not be opened"
		end
	elseif tab_idx ~= (vim.t.term_tab_idx or 1) then
		local order = state.get_term_order()
		order[tab_idx].focus = bufnr
		state.set_term_order(order)
		window.switch_to_tab(tab_idx)
	end

	local win = (vim.t.term_winids or {})[pane_idx]
	if not state.win_valid(win) or vim.api.nvim_win_get_buf(win) ~= bufnr then
		return false, "Terminal pane is no longer available"
	end
	local previous = vim.t.term_winid
	if previous ~= win and state.win_valid(previous) then vim.t.term_prev_pane_winid = previous end
	vim.api.nvim_set_current_win(win)
	vim.t.term_winid = win
	vim.t.term_bufnr = bufnr
	local order = state.get_term_order()
	order[tab_idx].focus = bufnr
	state.set_term_order(order)
	mode.restore(win)
	statusline.update()
	winbar.update()
	return true
end

function M.go_to_notification()
	local bufnr = state.get_last_notification_bufnr()
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("No recent notification", vim.log.levels.WARN)
		return
	end
	local ok, err = M.focus(bufnr)
	if not ok then
		vim.notify(err, vim.log.levels.WARN)
	end
end

local function confirm_terminal_close(bufnr)
	local job_id = vim.b[bufnr].terminal_job_id
	if not job_id then
		return true
	end
	local ok, pid = pcall(vim.fn.jobpid, job_id)
	if not ok or not pid then
		return true -- Job already exited.
	end
	local inspected, children = pcall(vim.api.nvim_get_proc_children, pid)
	if inspected and #children == 0 then return true end
	local message = inspected and "Terminal has child processes. Close anyway?"
		or "Could not inspect terminal child processes. Close anyway?"
	return vim.fn.confirm(message, "&Yes\n&No", 2) == 1
end

function M.delete()
	if not state.is_managed() then
		return
	end
	state.set_toggling()

	local bufnr = vim.api.nvim_get_current_buf()

	local tab_idx, _ = state.find_buf_tab(bufnr)
	if not tab_idx or not confirm_terminal_close(bufnr) then
		return
	end

	window.save_tab_state()
	window.close_pane_windows()

	-- Applies the terminal layout's close rule: the neighboring pane absorbs the space and
	-- receives focus; single-pane tabs are removed entirely.
	state.remove_term_from_order(bufnr)
	vim.api.nvim_buf_delete(bufnr, { force = true })
	window.reopen_current_tab()
end

function M.reset()
	local old = vim.api.nvim_get_current_buf()
	if vim.bo[old].buftype ~= "terminal" then return end
	local tab_idx = state.find_buf_tab(old)
	if not tab_idx or not confirm_terminal_close(old) then return end
	state.set_toggling()
	window.save_tab_state()
	local order = state.get_term_order()
	local selected = vim.t.term_tab_idx
	local replacement = vim.api.nvim_create_buf(false, true)
	vim.b[replacement].terminal_custom_name = vim.b[old].terminal_custom_name
	-- Start before discarding the old job. TermOpen temporarily registers the new
	-- buffer; replace that provisional order with the original pane tree below.
	local ok, err = pcall(window.termopen_with_size, replacement, #order[tab_idx].bufs, #order,
		vim.b[old].terminal_launch)
	if not ok then
		state.set_term_order(order)
		vim.t.term_tab_idx = selected
		error(err, 0)
	end
	local entry = order[tab_idx]
	for _, leaf in ipairs(require("terminal.frame").leaf_nodes(entry.layout)) do
		if leaf.buf == old then leaf.buf = replacement end
	end
	if entry.focus == old then entry.focus = replacement end
	if entry.modes then
		entry.modes[tostring(replacement)] = entry.modes[tostring(old)]
		entry.modes[tostring(old)] = nil
	end
	state.sync_bufs(entry)
	state.set_term_order(order)
	vim.t.term_tab_idx = selected
	if vim.t.term_bufnr == old then vim.t.term_bufnr = replacement end
	if not window.swap_tab_buffers(entry, tab_idx) then window.rebuild_tab() end
	vim.api.nvim_buf_delete(old, { force = true })
	return replacement
end

function M.new(opts)
	opts = require("terminal.launch").normalize(opts)
	if not window.check_size(nil, #state.get_tabs() + 1) then return false end
	state.set_toggling()

	local _, current_idx = state.get_current_tab()
	window.save_tab_state()
	local original = state.get_term_order()
	local previous_id = vim.t.term_prev_tab_id
	local previous_win = vim.api.nvim_get_current_win()
	state.remember_current_tab()

	local bufnr = vim.api.nvim_create_buf(false, true)

	-- Add to order before termopen so TermOpen autocmd doesn't double-add
	local order = state.get_term_order()
	local insert_idx = #order == 0 and 1 or (current_idx or #order) + 1
	local entry = state.new_entry(bufnr)
	table.insert(order, insert_idx, entry)
	state.set_term_order(order)
	vim.t.term_tab_idx = insert_idx

	-- Keep existing pane windows alive until the new process has started.
	local ok, err = pcall(window.termopen_with_size, bufnr, nil, #order, opts)
	if not ok then
		state.set_term_order(original)
		vim.t.term_tab_idx = current_idx
		vim.t.term_prev_tab_id = previous_id
		if state.win_valid(previous_win) then vim.api.nvim_set_current_win(previous_win) end
		mode.restore_current()
		error(err, 0)
	end
	window.close_pane_windows()

	window.open_tab_windows(entry, insert_idx)
	return bufnr
end

-- Split the current pane. dir: "row" (vsplit, side by side) or "col"
-- (split, stacked). The new terminal goes after the current pane and takes
-- half its space (vim split sizing).
function M.split(dir, opts)
	dir = dir or "row"
	assert(dir == "row" or dir == "col", "split direction must be row or col")
	opts = require("terminal.launch").normalize(opts)

	local tab, tab_idx = state.get_current_tab()
	if not tab then
		return M.new(opts)
	end

	-- Find current pane before closing windows
	local current_bufnr = vim.api.nvim_get_current_buf()
	local _, current_pane_idx = state.find_buf_tab(current_bufnr)

	window.save_tab_state()
	local original = state.get_term_order()
	local previous_win = vim.api.nvim_get_current_win()
	local preview = vim.deepcopy(original[tab_idx])
	if not state.split_entry(preview, -1, current_bufnr, dir or "row")
		or not window.check_size(preview) then return false end
	state.set_toggling()

	local bufnr = vim.api.nvim_create_buf(false, true)

	-- Add to tab before termopen so TermOpen autocmd doesn't double-add
	if not state.split_buf_in_tab(bufnr, tab_idx, current_bufnr, dir or "row") then
		vim.api.nvim_buf_delete(bufnr, { force = true })
		return
	end

	local ok, err = pcall(window.termopen_with_size, bufnr, #tab.bufs + 1, #state.get_term_order(), opts)
	if not ok then
		state.set_term_order(original)
		vim.t.term_tab_idx = tab_idx
		if state.win_valid(previous_win) then vim.api.nvim_set_current_win(previous_win) end
		mode.restore_current()
		error(err, 0)
	end
	window.close_pane_windows()

	window.reopen_current_tab(tab_idx)

	local wins = vim.t.term_winids or {}
	if current_pane_idx and wins[current_pane_idx] then
		vim.t.term_prev_pane_winid = wins[current_pane_idx]
	end
	return bufnr
end

function M.vsplit(opts)
	return M.split("row", opts)
end

function M.hsplit(opts)
	return M.split("col", opts)
end

-- Like CTRL-W_T: move the current pane out of its split into a new terminal
-- tab of its own. Fails if the pane's tab has only one pane.
function M.break_pane_to_tab()
	local bufnr = vim.api.nvim_get_current_buf()
	local tab_idx = state.find_buf_tab(bufnr)
	if not tab_idx then
		return
	end

	local tabs = state.get_tabs()
	local tab = tabs[tab_idx]
	if #tab.bufs < 2 then
		return
	end
	if not window.check_size(nil, #tabs + 1) then return false end
	state.remember_current_tab()

	state.set_toggling()
	window.save_tab_state()
	window.close_pane_windows()

	local order = state.get_term_order()
	local pane_mode = order[tab_idx].modes and order[tab_idx].modes[tostring(bufnr)]

	-- Applies the close-space rule to the source tab
	state.remove_term_from_order(bufnr)

	order = state.get_term_order()
	local new_idx = tab_idx + 1
	local entry = state.new_entry(bufnr)
	entry.modes = pane_mode and { [tostring(bufnr)] = pane_mode } or nil
	table.insert(order, new_idx, entry)
	state.set_term_order(order)
	vim.t.term_tab_idx = new_idx

	window.reopen_current_tab(new_idx)
end

function M.next()
	M.switch(1)
end

function M.prev()
	M.switch(-1)
end

function M.send(text, bufnr)
	if type(text) ~= "string" then return false, "Terminal text must be a string" end
	if bufnr == nil then bufnr = vim.t.term_bufnr end
	local target
	for _, item in ipairs(M.list()) do
		if item.bufnr == bufnr then target = item; break end
	end
	if not target then return false, "Terminal is no longer managed or no pane is selected" end
	local job = vim.b[bufnr].terminal_job_id
	if not job then return false, "Terminal has no job" end
	local ok, err = pcall(vim.api.nvim_chan_send, job, text)
	if not ok then return false, tostring(err) end
	return true
end

function M.setup(user_config)
	if loaded then
		if user_config and next(user_config) then
			error("terminal.setup() accepts configuration only on its first call", 2)
		end
		return
	end
	config.setup(user_config)
	M.config = config.config

	state.setup_vars()

	require("terminal.autocmds").setup(M)
	require("terminal.follow").setup()
	require("terminal.osc").setup()
	require("terminal.colors").setup()
	require("terminal.keymaps").setup(M)
	require("terminal.commands").setup(M)
	require("terminal.session").setup()

	require("terminal.job").setup()
	require("terminal.fugitive").setup()

	loaded = true
end

return M
