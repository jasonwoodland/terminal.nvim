-- terminal.nvim: terminal buffer naming from OSC titles

local M = {}

local config = require("terminal.config")
local inactive_rename_is_title_safe = vim.fn.has("nvim-0.13") == 1

local function disposable_buffer(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and not vim.api.nvim_buf_is_loaded(buf)
		and vim.bo[buf].buftype == ""
		and not vim.bo[buf].buflisted
		and not vim.bo[buf].modified
		and vim.fn.bufwinid(buf) == -1
end

-- nvim_buf_set_name() protects the outer title while renaming a non-current
-- buffer. keepalt preserves the user's alternate buffer. Neovim still creates
-- an unloaded placeholder for the old name, so remove only that placeholder.
local function rename_buffer(buf, name)
	local old_name = vim.api.nvim_buf_get_name(buf)
	if old_name == name or (name ~= "" and vim.fn.fnamemodify(name, ":p") == old_name) then
		return true
	end

	local ok = pcall(vim._with, { keepalt = true }, function()
		vim.api.nvim_buf_set_name(buf, name)
	end)

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
	return ("term://%s//%s"):format(pid, title)
end

function M.set_from_title(buf, title)
	if not config.config.set_buffer_name then
		return
	end
	-- Before Neovim 0.13, nvim_buf_set_name() can publish the title of a
	-- non-current buffer. Defer that rename until the terminal is focused.
	if not inactive_rename_is_title_safe and buf ~= vim.api.nvim_get_current_buf() then
		return
	end
	if vim.b[buf].term_buffer_name_title == title then
		return
	end

	if rename_buffer(buf, terminal_name(buf, title)) then
		vim.b[buf].term_buffer_name_title = title
	end
end

function M.sync(buf)
	local title = vim.b[buf].term_title
	if title and title:match("%S") then
		M.set_from_title(buf, title:match("^%s*(.-)%s*$"))
	end
end

return M
