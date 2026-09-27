-- Usage: nvim --clean --headless -l tests/osc.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))

local writes, notifications = {}, {}
vim.uv.guess_handle = function() return "tty" end
vim.uv.new_tty = function() return {} end
vim.uv.write = function(_, data) writes[#writes + 1] = data end
vim.notify = function(message) notifications[#notifications + 1] = message end
vim.api.nvim_create_augroup("Term", {})
require("terminal.osc").setup()
local state = require("terminal.state")

local function request(sequence, terminator)
	writes, notifications = {}, {}
	state.set_last_notification_bufnr(nil)
	vim.api.nvim_exec_autocmds("TermRequest", {
		buffer = 0,
		data = { sequence = sequence, terminator = terminator },
	})
end

request("\27]777;notify;Build;Done", "\7")
assert(writes[1] == "\27]777;notify;Build;Done\7", "preserve BEL termination")
assert(notifications[1] == "Build: Done", "notification text excludes terminator")
request("\27]9;Done", "\27\\")
assert(writes[1] == "\27]9;Done\27\\", "preserve ST termination")
request("\27]9;Done")
assert(writes[1] == "\27]9;Done\27\\", "terminate requests from Neovim 0.11")
request("\27]9;4;1;50", "\7")
assert(#writes == 1 and #notifications == 0, "progress passes through without ringing")
assert(state.get_last_notification_bufnr() == nil, "progress is not a notification")
request("\27]9;40 minutes remaining", "\7")
assert(#notifications == 1, "notification beginning with 4 is not progress")
request("\27]2;title", "\7")
assert(#writes == 0 and #notifications == 0, "unrelated OSC is ignored")
print("OSC regressions passed")
