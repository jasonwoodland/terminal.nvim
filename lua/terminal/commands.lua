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
	vim.api.nvim_create_user_command("TermRename", function(opts)
		local bufnr = vim.api.nvim_get_current_buf()
		local function rename(name)
			local ok, err = api.rename(name, bufnr)
			if not ok then vim.notify(err, vim.log.levels.WARN) end
		end
		if opts.bang then
			if opts.args ~= "" then
				vim.notify("TermRename! does not accept a name", vim.log.levels.ERROR)
				return
			end
			rename("")
		elseif opts.args ~= "" then
			rename(opts.args)
		elseif require("terminal.state").is_managed(bufnr) then
			vim.ui.input({ prompt = "Terminal name: ", default = vim.b[bufnr].terminal_custom_name or "" }, function(name)
				if name ~= nil then rename(name) end
			end)
		else
			vim.notify("Current buffer is not a managed terminal", vim.log.levels.WARN)
		end
	end, { nargs = "*", bang = true, desc = "Rename the current terminal pane; ! restores its automatic title" })
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
