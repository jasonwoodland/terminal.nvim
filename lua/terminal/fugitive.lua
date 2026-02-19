local job = require("terminal.job")

local M = {}

local function reload_fugitive_buffers()
	vim.cmd("call FugitiveDidChange()")
end

function M.run(cmd)
	job.run(cmd, reload_fugitive_buffers)
end

function M.setup()
	vim.api.nvim_create_user_command("FugitiveJob", function(opts)
		M.run(opts.args)
	end, { nargs = 1, complete = "shellcmd" })
end

return M
