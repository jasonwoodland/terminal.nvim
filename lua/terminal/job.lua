-- Auxiliary command jobs own their buffers independently of terminal tabs.
local M = {}
local mode = require("terminal.mode")
local jobs = {}

local function forget(entry)
	for i = #jobs, 1, -1 do
		if jobs[i] == entry then table.remove(jobs, i); return end
	end
end

function M.run(cmd, cb)
	for i = #jobs, 1, -1 do
		if not vim.api.nvim_buf_is_valid(jobs[i].buf) then table.remove(jobs, i) end
	end
	local previous = vim.api.nvim_get_current_win()
	local previous_buf = vim.api.nvim_get_current_buf()
	local previous_mode = mode.record()
	vim.cmd("botright 10new")
	local buf = vim.api.nvim_get_current_buf()
	-- Set before TermOpen so the global handlers do not adopt or delete it.
	vim.b[buf].terminal_job_runner = true
	local entry = { buf = buf }
	jobs[#jobs + 1] = entry
	local ok, job = pcall(vim.fn.termopen, cmd, {
		on_exit = function(_, code)
			vim.schedule(function()
				if entry.cancelled then return end
				if code == 0 then
					forget(entry)
					if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
					if cb then cb() end
				elseif vim.api.nvim_buf_is_valid(buf) then
					-- Keep failed output available without moving the user's focus.
					vim.b[buf].terminal_job_status = code
				else
					forget(entry)
				end
			end)
		end,
	})
	if not ok or job <= 0 then
		entry.cancelled = true
		forget(entry)
		if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
	end
	if vim.api.nvim_win_is_valid(previous) and vim.api.nvim_win_get_buf(previous) == previous_buf then
		vim.api.nvim_set_current_win(previous)
		mode.restore(previous, previous_mode)
	end
	if not ok or job <= 0 then error(ok and "Could not start terminal job" or job, 0) end
	return buf, job
end

function M.close()
	while #jobs > 0 do
		local entry = table.remove(jobs)
		entry.cancelled = true
		if vim.api.nvim_buf_is_valid(entry.buf) then
			vim.api.nvim_buf_delete(entry.buf, { force = true })
			return
		end
	end
end

function M.setup()
	vim.api.nvim_create_user_command("TermJob", function(opts)
		M.run(opts.args)
	end, { nargs = 1, complete = "shellcmd" })
	vim.api.nvim_create_user_command("TermJobClose", M.close, {})
end

return M
