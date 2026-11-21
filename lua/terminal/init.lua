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

local display = require("terminal.display")
for _, name in ipairs({ "toggle", "zoom", "float_toggle", "resize", "equalize" }) do M[name] = display[name] end

--------------------------------------------------------------------------------
-- Buffer switching
--------------------------------------------------------------------------------

function M.switch(delta, clamp_range)
	if type(delta) ~= "number" or math.abs(delta) == math.huge or delta ~= math.floor(delta) then
		return false, "Terminal tab delta must be an integer"
	end
	if clamp_range ~= nil and type(clamp_range) ~= "boolean" then
		return false, "Terminal tab clamp must be a boolean"
	end
	local tabs = state.get_tabs()
	if #tabs == 0 then return false, "No terminal tabs in this Vim tab" end

	local current_idx = vim.t.term_tab_idx or 1
	local target_idx

	if clamp_range then
		target_idx = math.max(1, math.min(#tabs, current_idx + delta))
	else
		target_idx = ((current_idx + delta - 1) % #tabs) + 1
	end

	return M.go_to(target_idx)
end

function M.go_to(index)
	if type(index) ~= "number" or index < 1 or index == math.huge or index ~= math.floor(index) then
		return false, "Terminal tab index must be a positive integer"
	end
	local tabs = state.get_tabs()
	if #tabs == 0 then return false, "No terminal tabs in this Vim tab" end
	if index > #tabs then return false, "Terminal tab index is out of range" end

	local current_idx = vim.t.term_tab_idx or 1

	if not state.is_term_open() then
		if index ~= current_idx then state.remember_current_tab() end
		vim.t.term_tab_idx = index
		vim.t.term_bufnr = tabs[index].focus or tabs[index].bufs[1]
		return true
	end
	if index == current_idx then return true end

	local ok, result = pcall(window.switch_to_tab, index)
	if not ok then return false, tostring(result) end
	if result == false then return false, "Terminal workspace could not be switched" end
	return true
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

local function movement_result(action, ...)
	local ok, result, err = pcall(action, ...)
	if not ok then return false, tostring(result) end
	return result, err
end

local function move(direction)
	local tabs = state.get_tabs()
	if #tabs == 0 then return false, "No terminal tabs in this Vim tab" end
	if #tabs == 1 then return true end

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
	return true
end

function M.move(direction)
	if direction ~= -1 and direction ~= 1 then return false, "Terminal move direction must be -1 or 1" end
	return movement_result(move, direction)
end

function M.move_to_vim_tab(direction)
	if direction ~= -1 and direction ~= 1 then return false, "Terminal move direction must be -1 or 1" end
	return movement_result(require("terminal.transfer").move, direction)
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
	local target = state.find_pane(bufnr)
	if not target then return false, "Terminal is no longer managed" end
	name = vim.trim(name)
	vim.b[bufnr].terminal_custom_name = name ~= "" and name or nil
	if target.tabpage == vim.api.nvim_get_current_tabpage() then winbar.update() end
	return true
end

function M.focus(bufnr)
	local target = state.find_pane(bufnr)
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
		if not window.switch_to_tab(tab_idx) then return false, "Terminal workspace could not be switched" end
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
		return false, "No recent notification"
	end
	local called, ok, err = pcall(M.focus, bufnr)
	if not called then ok, err = false, tostring(ok) end
	if not ok then
		vim.notify(err, vim.log.levels.WARN)
	end
	return ok, err
end

local lifecycle = require("terminal.lifecycle")
for _, name in ipairs({ "new", "split", "vsplit", "hsplit", "delete", "reset", "close_tab" }) do M[name] = lifecycle[name] end

-- Like CTRL-W_T: move the current pane out of its split into a new terminal
-- tab of its own. Fails if the pane's tab has only one pane.
local function break_pane_to_tab()
	local bufnr = vim.api.nvim_get_current_buf()
	local tab_idx = state.find_buf_tab(bufnr)
	if not tab_idx then
		return false, "Current buffer is not a managed terminal pane"
	end

	local tabs = state.get_tabs()
	local tab = tabs[tab_idx]
	if #tab.bufs < 2 then
		return false, "Terminal tab has only one pane"
	end
	if not window.check_size(nil, #tabs + 1) then return false, "Terminal layout does not fit" end
	state.remember_current_tab()

	state.set_toggling()
	mode.record()
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

	if not window.reopen_current_tab(new_idx) then return false, "Terminal workspace could not be opened" end
	return true
end

function M.break_pane_to_tab()
	return movement_result(break_pane_to_tab)
end

function M.next()
	return M.switch(1)
end

function M.prev()
	return M.switch(-1)
end

function M.send(text, bufnr)
	if type(text) ~= "string" then return false, "Terminal text must be a string" end
	if bufnr == nil then bufnr = vim.t.term_bufnr end
	local target = state.find_pane(bufnr)
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
	require("terminal.cwd").setup()
	require("terminal.colors").setup()
	require("terminal.keymaps").setup(M)
	require("terminal.commands").setup(M)
	require("terminal.session").setup()

	require("terminal.job").setup()
	require("terminal.fugitive").setup()

	loaded = true
end

return M
