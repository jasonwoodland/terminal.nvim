local M = {}

local job_bufnr = nil

function M.run(cmd, cb)
	vim.cmd("bot new +resize10")
	job_bufnr = vim.fn.bufnr()
	vim.fn.termopen(cmd, {
		on_exit = function(_, code, _)
			if code == 0 then
				vim.cmd("bd" .. job_bufnr)
				if cb then
					cb()
				end
			else
				vim.cmd("wincmd p")
				vim.cmd("startinsert")
			end
		end,
	})
	vim.cmd("norm G")
	vim.cmd("wincmd p")
end

function M.close()
	if job_bufnr then
		vim.cmd("bd!" .. job_bufnr)
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
