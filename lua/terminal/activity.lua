-- terminal.nvim: one-shot background terminal activity watchers

local M = {}

local state = require("terminal.state")

-- nvim_buf_attach() Lua callbacks can only detach themselves by returning
-- true. Keep the small watcher object so foreground transitions can disarm a
-- callback before its next (and final) invocation.
local watchers = {}

local function find_entry(order, bufnr)
	for i, entry in ipairs(order) do
		for _, buf in ipairs(entry.bufs) do
			if buf == bufnr then
				return i, entry
			end
		end
	end
	return nil, nil
end

local function arm(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local existing = watchers[bufnr]
	if existing then
		existing.armed = true
		return
	end

	local watcher = { armed = true }
	watchers[bufnr] = watcher

	local attached = vim.api.nvim_buf_attach(bufnr, false, {
		on_lines = function(_, buf)
			-- A Lua buffer callback cannot be detached directly. Returning true
			-- removes only this callback, without disturbing other plugins.
			if watchers[buf] == watcher then
				watchers[buf] = nil
			end
			if not watcher.armed or not vim.api.nvim_buf_is_valid(buf) then
				return true
			end

			local owner_tab = vim.b[buf].term_owner_tab
			if not owner_tab or not vim.api.nvim_tabpage_is_valid(owner_tab) then
				return true
			end

			local raw_order = vim.t[owner_tab].term_order
			if not raw_order then
				return true
			end
			local order = state.migrate_term_order(raw_order)
			local tab_idx, entry = find_entry(order, buf)
			if not tab_idx or tab_idx == (vim.t[owner_tab].term_tab_idx or 1) or entry.activity then
				return true
			end

			entry.activity = true
			vim.t[owner_tab].term_order = order
			vim.schedule(function()
				if
					vim.api.nvim_tabpage_is_valid(owner_tab)
					and vim.api.nvim_get_current_tabpage() == owner_tab
				then
					require("terminal.winbar").update()
				end
			end)
			return true
		end,
		on_detach = function(_, buf)
			if watchers[buf] == watcher then
				watchers[buf] = nil
			end
		end,
	})

	if not attached then
		watchers[bufnr] = nil
	end
end

local function disarm(bufnr)
	local watcher = watchers[bufnr]
	if watcher then
		watcher.armed = false
	end
end

-- Synchronize watchers for one Vim tabpage. The selected terminal tab never
-- needs an activity marker; every other unflagged tab gets one watcher which
-- removes itself on the first buffer update.
function M.sync(tabpage)
	tabpage = tabpage or vim.api.nvim_get_current_tabpage()
	if not vim.api.nvim_tabpage_is_valid(tabpage) then
		return
	end

	local raw_order = vim.t[tabpage].term_order
	if not raw_order then
		return
	end
	local order = state.migrate_term_order(raw_order)
	local current_idx = vim.t[tabpage].term_tab_idx or 1

	for i, entry in ipairs(order) do
		for _, buf in ipairs(entry.bufs) do
			if i == current_idx or entry.activity then
				disarm(buf)
			else
				arm(buf)
			end
		end
	end
end

-- Diagnostic helpers used by the regression suite.
function M.is_armed(bufnr)
	return watchers[bufnr] ~= nil and watchers[bufnr].armed
end

return M
