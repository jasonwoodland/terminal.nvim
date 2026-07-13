-- terminal.nvim: terminal buffer naming from OSC titles

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")

local function disposable_buffer(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and not vim.api.nvim_buf_is_loaded(buf)
		and vim.bo[buf].buftype == ""
		and not vim.bo[buf].buflisted
		and not vim.bo[buf].modified
		and vim.fn.bufwinid(buf) == -1
end

-- :file and nvim_buf_set_name() intentionally create an unlisted buffer for
-- the old name so it can become the alternate file. Terminal titles are not
-- files, and changing them frequently would otherwise grow the buffer list
-- without bound. :keepalt preserves the user's real alternate buffer; this
-- removes only the unloaded placeholder created for our previous title.
local function rename_buffer(buf, name)
	local old_name = vim.api.nvim_buf_get_name(buf)
	if old_name == name or (name ~= "" and vim.fn.fnamemodify(name, ":p") == old_name) then
		return true
	end

	vim.b[buf].term_title_rename = true
	local ok = pcall(vim.api.nvim_buf_call, buf, function()
		if name == "" then
			vim.api.nvim_cmd({ cmd = "file", range = { 0 }, mods = { silent = true, keepalt = true } }, {})
		else
			-- Structured command arguments keep terminal-controlled OSC titles
			-- out of Ex command parsing.
			vim.api.nvim_cmd({ cmd = "file", args = { name }, mods = { silent = true, keepalt = true } }, {})
		end
	end)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.b[buf].term_title_rename = nil
	end

	if ok and old_name ~= "" then
		for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
			if
				candidate ~= buf
				and vim.api.nvim_buf_get_name(candidate) == old_name
				and disposable_buffer(candidate)
			then
				pcall(vim.api.nvim_buf_delete, candidate, { force = true })
				break
			end
		end
	end

	return ok
end

local function clear_stale_buffer_name(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	if vim.b[buf].term_buffer_name and not state.find_buf_tab(buf) then
		rename_buffer(buf, "")
		vim.b[buf].term_buffer_name = nil
		vim.b[buf].term_buffer_name_title = nil
		return true
	end
	if
		name ~= ""
		and vim.bo[buf].buftype == ""
		and not vim.bo[buf].buflisted
		and not vim.bo[buf].modified
		and vim.fn.bufwinid(buf) == -1
		and not vim.uv.fs_stat(name)
	then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		return true
	end
	return false
end

local function buffer_name_exists(name, current_buf)
	local normalized_name = vim.fn.fnamemodify(name, ":p")
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= current_buf and vim.api.nvim_buf_is_valid(buf) then
			local existing = vim.api.nvim_buf_get_name(buf)
			if existing == name or existing == normalized_name then
				if not clear_stale_buffer_name(buf) then
					return true
				end
			end
		end
	end
	return false
end

local function unique_buffer_name(title, buf)
	if not buffer_name_exists(title, buf) then
		return title
	end

	local i = 2
	while buffer_name_exists(title .. " (" .. i .. ")", buf) do
		i = i + 1
	end
	return title .. " (" .. i .. ")"
end

function M.set_from_title(buf, title)
	if not config.config.set_buffer_name then
		return
	end
	if vim.b[buf].term_buffer_name_title == title and vim.api.nvim_buf_get_name(buf) == vim.b[buf].term_buffer_name then
		return
	end

	local name = unique_buffer_name(title, buf)
	local ok = rename_buffer(buf, name)
	if ok then
		vim.b[buf].term_buffer_name_title = title
		vim.b[buf].term_buffer_name = vim.api.nvim_buf_get_name(buf)
	end
end

function M.clear(buf)
	if vim.b[buf].term_buffer_name then
		rename_buffer(buf, "")
		vim.b[buf].term_buffer_name = nil
		vim.b[buf].term_buffer_name_title = nil
	end
end

return M
