local job = require("terminal.job")

local M = {}

local function reload_fugitive_buffers()
	if vim.fn.exists("*FugitiveDidChange") == 1 then vim.fn["FugitiveDidChange"]() end
end

function M.run(cmd)
	if vim.fn.exists("*FugitiveDidChange") ~= 1 then
		vim.notify("FugitiveJob requires vim-fugitive", vim.log.levels.WARN)
		return
	end
	return job.run(cmd, reload_fugitive_buffers)
end

function M.setup()
	vim.api.nvim_create_user_command("FugitiveJob", function(opts)
		M.run(opts.args)
	end, { nargs = 1, complete = "shellcmd" })
end

return M
