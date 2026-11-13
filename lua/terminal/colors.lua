-- Answer OSC 10/11 queries with the colorscheme's default colors.

local M = {}

function M.setup()
	if not require("terminal.config").config.osc_colors then return end

	-- Replace only Neovim's known handler, keeping its fallback and leaving
	-- other TermRequest handlers alone. If it has already been replaced, do
	-- not install a second responder (or guess how a future handler works).
	for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = "TermRequest" })) do
		if autocmd.group_name == "nvim.terminal"
			and autocmd.desc == "Handles OSC foreground/background color requests"
			and type(autocmd.callback) == "function" then
			local fallback = autocmd.callback
			vim.api.nvim_del_autocmd(autocmd.id)
			vim.api.nvim_create_autocmd("TermRequest", {
				group = "Term",
				desc = "Report colorscheme foreground/background to terminal applications",
				callback = function(ev)
					local command = ev.data.sequence:match("^\27%](1[01]);%?$")
					if not command then return end
					local channel = vim.bo[ev.buf].channel
					if channel == 0 then return end

					local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
					local key = command == "10" and "fg" or "bg"
					if normal.reverse then key = key == "fg" and "bg" or "fg" end
					local color = normal[key]
					-- RGB highlights do not describe cterm rendering. Missing colors
					-- (e.g. transparent backgrounds) still need Neovim's default reply.
					if not vim.o.termguicolors or color == nil then
						fallback(ev)
						return
					end

					local red = math.floor(color / 65536) % 256
					local green = math.floor(color / 256) % 256
					local blue = color % 256
					vim.api.nvim_chan_send(channel, string.format(
						"\27]%s;rgb:%04x/%04x/%04x%s", command,
						red * 257, green * 257, blue * 257, ev.data.terminator or "\27\\"
					))
				end,
			})
			return
		end
	end
end

return M
