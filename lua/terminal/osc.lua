-- terminal.nvim: OSC notification passthrough (OSC 9 / 99 / 777)

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")

-- Write-through to the outer terminal so notifications escape the embedded
-- PTY. stdout may not be a TTY (GUIs, headless); skip passthrough then.
local out_tty = nil
local function write_tty(data)
	if out_tty == nil then
		out_tty = vim.uv.guess_handle(1) == "tty" and vim.uv.new_tty(1, false) or false
	end
	if out_tty then
		vim.uv.write(out_tty, data)
	end
end

function M.setup()
	if not config.config.osc_notifications then
		return
	end

	vim.api.nvim_create_autocmd("TermRequest", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local seq = ev.data.sequence

			if seq:sub(1, 4) ~= "\x1b]9;" and seq:sub(1, 5) ~= "\x1b]99;" and seq:sub(1, 6) ~= "\x1b]777;" then
				return
			end

			-- Pass through to terminal
			write_tty(seq)

			-- OSC 9;4 is progress reporting -- pass through but don't notify
			if seq:sub(1, 5) == "\x1b]9;4" then
				return
			end

			state.set_last_notification_bufnr(ev.buf)

			-- Notify when not focused in a terminal buffer
			local is_term_buf = vim.bo.buftype == "terminal"
			if is_term_buf then
				return
			end

			local title, body = seq:match("\x1b%]777;notify;([^;\007]+);([^\007]*)")
			if not body then
				body = seq:match("\x1b%]777;notify;([^\007]*)")
			end
			if not body then
				body = seq:match("\x1b%]99?;([^\007]*)")
			end
			if body then
				title = title or "Terminal notification"
				vim.notify(title .. ": " .. body, vim.log.levels.INFO)
			end
			write_tty("\a")
		end,
	})
end

return M
