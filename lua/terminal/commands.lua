-- terminal.nvim: user commands and command-line aliases

local M = {}

local utils = require("terminal.utils")

function M.setup(api)
	vim.api.nvim_create_user_command("TermSplit", "new | term", {})
	vim.api.nvim_create_user_command("TermVsplit", "vnew | term", {})
	vim.api.nvim_create_user_command("TermTab", function(opts)
		vim.cmd(opts.args .. "tabnew | term")
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("TermDelete", function()
		api.delete()
	end, {})
	vim.api.nvim_create_user_command("TermReset", 'exe "te" | bd!# | let t:term_bufnr = bufnr("%")', {})

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
