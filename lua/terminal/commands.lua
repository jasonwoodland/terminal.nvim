-- terminal.nvim: user commands and command-line aliases

local M = {}

local utils = require("terminal.utils")

function M.setup(api)
	vim.api.nvim_create_user_command("TermSplit", api.hsplit, {})
	vim.api.nvim_create_user_command("TermVsplit", api.vsplit, {})
	vim.api.nvim_create_user_command("TermTab", function(opts)
		vim.cmd(opts.args .. "tabnew")
		api.new()
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("TermDelete", function()
		api.delete()
	end, {})
	vim.api.nvim_create_user_command("TermReset", api.reset, {})
	vim.api.nvim_create_user_command("TermSelect", function()
		require("terminal.telescope").terminals()
	end, { desc = "Navigate to a terminal with Telescope" })

	utils.alias("tsplit", "TermSplit")
	utils.alias("tvsplit", "TermVsplit")
	utils.alias("ttab", "TermTab")
	utils.alias("tdelete", "TermDelete")
	utils.alias("st", "TermSplit")
	utils.alias("vst", "TermVsplit")
	utils.alias("tt", "TermTab")
	utils.alias("td", "TermDelete")
end

return M
