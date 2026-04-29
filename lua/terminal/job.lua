local M = {}

local job_bufnr = nil

function M.run(cmd, cb)
	local prev_win = vim.api.nvim_get_current_win()
	vim.cmd("bot new +resize10")
	job_bufnr = vim.api.nvim_get_current_buf()
	vim.fn.termopen(cmd, {
		on_exit = function(_, code, _)
			if code == 0 then
				if vim.api.nvim_buf_is_valid(job_bufnr) then
					vim.api.nvim_buf_delete(job_bufnr, { force = true })
				end
				if cb then
					cb()
				end
			else
				vim.api.nvim_set_current_win(prev_win)
				vim.cmd("startinsert")
			end
		end,
	})
	local line_count = vim.api.nvim_buf_line_count(job_bufnr)
	vim.api.nvim_win_set_cursor(0, { line_count, 0 })
	vim.api.nvim_set_current_win(prev_win)
end

function M.close()
	if job_bufnr then
		if vim.api.nvim_buf_is_valid(job_bufnr) then
			vim.api.nvim_buf_delete(job_bufnr, { force = true })
		end
		job_bufnr = nil
	end
end

function M.setup()
	vim.api.nvim_create_user_command("TermJob", function(opts)
		M.run(opts.args)
	end, { nargs = 1, complete = "shellcmd" })

	vim.api.nvim_create_user_command("TermJobClose", function()
		M.close()
	end, {})
end

return M
