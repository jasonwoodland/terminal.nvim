-- terminal.nvim: terminal buffer naming from OSC titles

local M = {}

local config = require("terminal.config")

local function disposable_buffer(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and not vim.api.nvim_buf_is_loaded(buf)
		and vim.bo[buf].buftype == ""
		and not vim.bo[buf].buflisted
		and not vim.bo[buf].modified
		and vim.fn.bufwinid(buf) == -1
end

-- :file intentionally leaves an unlisted buffer for the old name so it can
-- become the alternate file. OSC titles can change frequently, so remove only
-- the unloaded placeholder created for our previous terminal name.
local function rename_buffer(buf, name)
	local old_name = vim.api.nvim_buf_get_name(buf)
	if old_name == name then
		return true
	end

	vim.b[buf].term_title_rename = true
	local ok = pcall(vim.api.nvim_buf_call, buf, function()
		if name == "" then
			vim.api.nvim_cmd({ cmd = "file", range = { 0 }, mods = { silent = true, keepalt = true } }, {})
		else
			vim.api.nvim_cmd({ cmd = "file", args = { name }, mods = { silent = true, keepalt = true } }, {})
		end
	end)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.b[buf].term_title_rename = nil
	end

	if ok and old_name ~= "" then
		for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
			if candidate ~= buf and vim.api.nvim_buf_get_name(candidate) == old_name and disposable_buffer(candidate) then
				pcall(vim.api.nvim_buf_delete, candidate, { force = true })
				break
			end
		end
	end

	return ok
end

local function terminal_name(buf, title)
	local job_id = vim.b[buf].terminal_job_id or buf
	local ok, pid = pcall(vim.fn.jobpid, job_id)
	if not ok or not pid or pid <= 0 then
		pid = job_id
	end
	return ("terminal://%s//%s"):format(pid, title)
end

function M.set_from_title(buf, title)
	if not config.config.set_buffer_name then
		return
	end
	if vim.b[buf].term_buffer_name_title == title then
		return
	end

	if rename_buffer(buf, terminal_name(buf, title)) then
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
