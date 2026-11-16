-- terminal.nvim: display controls

local M = {}
local config = require("terminal.config")
local state = require("terminal.state")
local window = require("terminal.window")
local context = require("terminal.context")

local function display_result(action, ...)
	local keys = { "term_zoom", "term_prev_height", "term_float_enabled", "term_height", "term_drawer_size" }
	local previous = {}
	for _, key in ipairs(keys) do previous[key] = vim.t[key] end
	local was_open = state.is_term_open()
	local ok, result, err = pcall(action, ...)
	if ok and result == true then return true end
	for _, key in ipairs(keys) do vim.t[key] = previous[key] end
	state.sync_zoom_options()
	local reason = ok and (err or "Terminal layout does not fit") or tostring(result)
	if was_open and not state.is_term_open() then reason = window.recover_tab(reason) end
	return false, reason
end

local function toggle(opts)
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
		return true
	end
	if opts and opts.open == false and not is_open then
		return true
	end

	if is_open then
		-- Close
		window.save_tab_state()
		if state.win_valid(vim.t.term_winid) and state.is_managed(vim.api.nvim_win_get_buf(vim.t.term_winid)) then
			vim.t.term_bufnr = vim.api.nvim_win_get_buf(vim.t.term_winid)
			vim.t.term_mode = vim.api.nvim_get_mode().mode
		end
		window.close_pane_windows()
		return true
	else
		-- Open
		vim.t.prev_winid = vim.api.nvim_get_current_win()

		local tab, tab_idx = state.get_current_tab()
		window.refresh_drawer_size()
		if height > 1 then vim.t.term_height = height; vim.t.term_drawer_size = nil end
		if not window.check_size(tab, math.max(#state.get_tabs(), 1)) then return false, "Terminal layout does not fit" end

		if tab and #tab.bufs > 0 then
			return window.open_tab_windows(tab, tab_idx)
		else
			local buf, err = require("terminal.lifecycle").new()
			if not buf then return false, err end
			return true
		end
	end
end

function M.toggle(opts)
	if opts ~= nil then
		if type(opts) ~= "table" then return false, "Terminal toggle options must be a table" end
		for key, value in pairs(opts) do
			if key ~= "open" then return false, "Unknown terminal toggle option: " .. tostring(key) end
			if type(value) ~= "boolean" then return false, "Terminal toggle open must be a boolean" end
		end
	end
	return display_result(toggle, opts)
end

local function zoom()
	state.set_toggling()

	if not state.is_term_open() then
		if config.is_float_config_enabled() or config.config.float_zoom then
			vim.t.term_zoom = true
		end
		return M.toggle({ open = true })
	end

	if config.is_float_config_enabled() then
		vim.t.term_zoom = (not vim.t.term_zoom) and true or nil
		return window.rebuild_tab()
	end

	if config.config.float_zoom then
		window.save_tab_state()

		if not vim.t.term_zoom then
			state.save_term_height()
			vim.t.term_zoom = true
		else
			vim.t.term_zoom = nil
		end

		return window.rebuild_tab()
	end

	-- Non-float, non-float_zoom: old height toggle behavior
	local wins2 = vim.t.term_winids or {}
	if #wins2 == 0 or not state.win_valid(wins2[1]) then
		return false, "No terminal pane is available to zoom"
	end
	if vim.t.term_prev_height == nil then
		-- set before resizing so WinResized doesn't overwrite term_height
		vim.t.term_prev_height = state.drawer_span() or vim.t.term_height
		-- maximize; vim/set_drawer_height clamp to the available rows
		return window.set_drawer_height(vim.o.lines)
	else
		local target = vim.t.term_prev_height
		vim.t.term_prev_height = nil
		return window.set_drawer_height(target)
	end
end

function M.zoom()
	return display_result(zoom)
end

local function float_toggle()
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
	vim.t.term_zoom = nil
	vim.t.term_prev_height = nil

	vim.t.term_float_enabled = target
	if not target and vim.t.term_drawer_size then
		local _, available = require("terminal.size").available(false)
		vim.t.term_height = require("terminal.size").resolve(vim.t.term_drawer_size, available)
	end

	if not window.check_size(state.get_current_tab()) then
		return false, "Terminal layout does not fit"
	end
	if state.is_term_open() then
		return window.rebuild_tab()
	else
		return M.toggle({ open = true })
	end
end

function M.float_toggle()
	return display_result(float_toggle)
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
		local caller = context.capture()
		state.set_toggling()
		local ok, result = pcall(window.rebuild_tab)
		if not ok or result == false then
			rollback()
			local reason = window.recover_tab(ok and "Could not resize terminal panes" or tostring(result))
			if not caller.managed then context.restore(caller) end
			return false, reason
		end
		if not caller.managed then context.restore(caller) end
	end
	return true
end

function M.equalize()
	if #state.get_tabs() == 0 then return false, "No terminal tabs in this Vim tab" end
	if not state.is_term_open() then return true end
	local ok, result = pcall(require("terminal.float_layout").equalize_panes)
	if not ok then return false, tostring(result) end
	if result == false then return false, "Terminal panes could not be equalized" end
	return true
end

return M
