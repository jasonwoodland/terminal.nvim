-- terminal.nvim: terminal buffer naming from OSC titles

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")

local function clear_stale_buffer_name(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	if vim.b[buf].term_buffer_name and not state.find_buf_tab(buf) then
		pcall(vim.api.nvim_buf_set_name, buf, "")
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
		pcall(vim.api.nvim_buf_set_name, buf, "")
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
	local ok = pcall(vim.api.nvim_buf_set_name, buf, name)
	if ok then
		vim.b[buf].term_buffer_name_title = title
		vim.b[buf].term_buffer_name = vim.api.nvim_buf_get_name(buf)
	end
end

function M.clear(buf)
	if vim.b[buf].term_buffer_name then
		pcall(vim.api.nvim_buf_set_name, buf, "")
		vim.b[buf].term_buffer_name = nil
		vim.b[buf].term_buffer_name_title = nil
	end
end

return M
