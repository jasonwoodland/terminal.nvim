-- terminal.nvim: managed terminal creation and lifecycle

local M = {}
local config = require("terminal.config")
local state = require("terminal.state")
local mode = require("terminal.mode")
local window = require("terminal.window")
local winbar = require("terminal.winbar")
local context = require("terminal.context")

-- A started job is provisional until its view can be installed. Restore the
-- old workspace and stop only that provisional job when rendering fails.
local function rollback_launch(original, selected, previous_id, buf, caller, was_open, reason)
	local closed, close_err = pcall(window.close_pane_windows)
	if not closed then reason = reason .. "; " .. tostring(close_err) end
	state.set_term_order(original)
	vim.t.term_tab_idx = selected
	vim.t.term_prev_tab_id = previous_id
	local entry = original[selected or 1]
	vim.t.term_bufnr = entry and (entry.focus or entry.bufs[1]) or nil
	if vim.api.nvim_buf_is_valid(buf) then
		local deleted, delete_err = pcall(vim.api.nvim_buf_delete, buf, { force = true })
		if not deleted then reason = reason .. "; " .. tostring(delete_err) end
	end
	if was_open then reason = window.recover_tab(reason) end
	context.restore(caller)
	return false, reason
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

-- Resolve ownership before prompting. Run in the owner's window context so
-- hidden entries and foreign Vim tabs can be edited without opening them.
local function pane_action(bufnr, action)
	if bufnr == nil then bufnr = vim.api.nvim_get_current_buf() end
	local target = state.find_pane(bufnr)
	if not target then return false, "Terminal is no longer managed" end
	if not confirm_terminal_close(bufnr) then return false, "Terminal action cancelled" end
	target = state.find_pane(bufnr)
	if not target then return false, "Terminal is no longer managed" end
	local caller = context.capture()
	mode.record()
	local function run()
		local tab_idx = state.find_buf_tab(bufnr)
		if not tab_idx then return false, "Terminal is no longer in its workspace" end
		return action(bufnr, tab_idx)
	end
	local ok, result, err
	if target.tabpage == caller.tab then
		ok, result, err = pcall(run)
	else
		ok, result, err = pcall(vim.api.nvim_win_call, vim.api.nvim_tabpage_get_win(target.tabpage), run)
	end
	if caller.buf ~= bufnr then context.restore(caller) end
	state.sync_zoom_options()
	if not ok then return false, tostring(result) end
	return result, err
end

function M.delete(bufnr)
	return pane_action(bufnr, function(buf, tab_idx)
		state.set_toggling()
		window.save_tab_state()
		local open = state.is_term_open()
		local tabs = state.get_tabs()
		local strip_changes = #tabs[tab_idx].bufs == 1
			and config.should_show_winbar(#tabs) ~= config.should_show_winbar(#tabs - 1)
		local rebuild = open and (tab_idx == vim.t.term_tab_idx
			or strip_changes)
		if rebuild then window.close_pane_windows() end
		state.remove_term_from_order(buf)
		vim.api.nvim_buf_delete(buf, { force = true })
		if vim.t.term_bufnr == buf then
			local entry = state.get_current_tab()
			vim.t.term_bufnr = entry and (entry.focus or entry.bufs[1]) or nil
		end
		if rebuild then
			if not window.reopen_current_tab() and #state.get_tabs() > 0 then
				return false, "Terminal pane was deleted but the workspace could not be reopened"
			end
		else winbar.update() end
		return true
	end)
end

local function reset_pane(old, tab_idx)
	state.set_toggling()
	window.save_tab_state()
	local order = state.get_term_order()
	local selected = vim.t.term_tab_idx
	local original, caller, was_open = vim.deepcopy(order), context.capture(), state.is_term_open()
	local previous_id = vim.t.term_prev_tab_id
	local replacement = vim.api.nvim_create_buf(false, true)
	vim.b[replacement].terminal_custom_name = vim.b[old].terminal_custom_name
	-- Start before discarding the old job. TermOpen temporarily registers the new
	-- buffer; replace that provisional order with the original pane tree below.
	local ok, err = pcall(window.termopen_with_size, replacement, #order[tab_idx].bufs, #order,
		vim.b[old].terminal_launch)
	if not ok then
		state.set_term_order(order)
		vim.t.term_tab_idx = selected
		return false, tostring(err)
	end
	vim.b[replacement].term_mode = vim.b[old].term_mode
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
	if state.is_term_open() and tab_idx == selected then
		local shown, result = pcall(function()
			return window.swap_tab_buffers(entry, tab_idx) or window.rebuild_tab()
		end)
		if not shown or not result then
			return rollback_launch(original, selected, previous_id, replacement, caller, was_open,
				shown and "Replacement terminal workspace could not be opened" or tostring(result))
		end
	end
	vim.api.nvim_buf_delete(old, { force = true })
	return replacement
end

function M.reset(bufnr)
	return pane_action(bufnr, reset_pane)
end

function M.new(opts)
	opts = require("terminal.launch").normalize(opts)
	if not window.check_size(nil, #state.get_tabs() + 1) then return false, "Terminal layout does not fit" end
	state.set_toggling()

	local _, current_idx = state.get_current_tab()
	window.save_tab_state()
	local original = state.get_term_order()
	local previous_id = vim.t.term_prev_tab_id
	local previous_win = vim.api.nvim_get_current_win()
	local caller, was_open = context.capture(), state.is_term_open()
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
	local shown, result = pcall(function()
		window.close_pane_windows()
		return window.open_tab_windows(entry, insert_idx)
	end)
	if not shown or not result then
		return rollback_launch(original, current_idx, previous_id, bufnr, caller, was_open,
			shown and "Terminal workspace could not be opened" or tostring(result))
	end
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
	local caller, was_open, previous_id = context.capture(), state.is_term_open(), vim.t.term_prev_tab_id
	local preview = vim.deepcopy(original[tab_idx])
	if not state.split_entry(preview, -1, current_bufnr, dir or "row")
		or not window.check_size(preview) then return false, "Terminal pane layout does not fit" end
	state.set_toggling()

	local bufnr = vim.api.nvim_create_buf(false, true)

	-- Add to tab before termopen so TermOpen autocmd doesn't double-add
	if not state.split_buf_in_tab(bufnr, tab_idx, current_bufnr, dir or "row") then
		vim.api.nvim_buf_delete(bufnr, { force = true })
		return false, "Terminal pane could not be split"
	end

	local ok, err = pcall(window.termopen_with_size, bufnr, #tab.bufs + 1, #state.get_term_order(), opts)
	if not ok then
		state.set_term_order(original)
		vim.t.term_tab_idx = tab_idx
		if state.win_valid(previous_win) then vim.api.nvim_set_current_win(previous_win) end
		mode.restore_current()
		error(err, 0)
	end
	local shown, result = pcall(function()
		window.close_pane_windows()
		return window.reopen_current_tab(tab_idx)
	end)
	if not shown or not result then
		return rollback_launch(original, tab_idx, previous_id, bufnr, caller, was_open,
			shown and "Terminal workspace could not be reopened" or tostring(result))
	end

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

return M
