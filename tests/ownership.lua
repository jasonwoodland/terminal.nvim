-- Usage: nvim --clean --headless -l tests/ownership.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
vim.o.shell = "/bin/sh"
local function settle() vim.wait(150, function() return false end) end
local function wait(fn, message) assert(vim.wait(3000, fn, 10), message) end
local user_mapping = function() end
local custom_closes = 0
vim.api.nvim_create_autocmd("TermClose", {
	group = "nvim.terminal", desc = "User terminal handler",
	callback = function() custom_closes = custom_closes + 1 end,
})
vim.keymap.set("n", "<C-w>h", user_mapping)
vim.keymap.set("n", "z", user_mapping)
vim.keymap.set("t", "<F6>", user_mapping)
vim.keymap.set("n", "<ScrollWheelUp>", user_mapping)
-- Simulate user terminal defaults, registered before terminal.nvim.
vim.api.nvim_create_autocmd("TermOpen", { callback = function()
	vim.wo.number = true
	vim.wo.relativenumber = true
	vim.wo.signcolumn = "yes"
	vim.wo.scrolloff = 7
end })
vim.cmd("terminal")
local existing = vim.api.nvim_get_current_buf()
local existing_name = vim.api.nvim_buf_get_name(existing)
local terminal = require("terminal")
local state = require("terminal.state")
terminal.setup({ keys = { paste_register = "<F6>" } })
assert(#terminal.list() == 0 and not state.is_managed(existing), "setup does not adopt an existing terminal")
assert(vim.api.nvim_buf_get_name(existing) == existing_name and vim.wo.number and vim.wo.scrolloff == 7,
	"setup preserves existing terminal names and options")
assert(vim.fn.maparg("<C-w>h", "n", false, true).callback == user_mapping
	and vim.fn.maparg("z", "n", false, true).callback == user_mapping,
	"native window and z mappings outside managed buffers survive")
assert(vim.fn.maparg("<ScrollWheelUp>", "n", false, true).callback == user_mapping,
	"existing mouse mappings survive")
local global_terminal_maps = vim.api.nvim_get_keymap("t")
assert(#global_terminal_maps == 1 and global_terminal_maps[1].callback == user_mapping,
	"plugin installs no global terminal-mode mappings")

terminal.toggle()
settle()
local managed = vim.api.nvim_get_current_buf()
assert(state.is_managed(managed) and #terminal.list() == 1, "plugin-created terminals are managed")
assert(vim.fn.maparg("<F6>", "t", false, true).buffer == 1,
	"input mappings are local to managed buffers")
assert(vim.fn.maparg("<C-w>h", "n", false, true).buffer == 1,
	"pane overrides are local to managed buffers")
terminal.toggle()
settle()
vim.api.nvim_set_current_buf(existing)
assert(vim.fn.maparg("<F6>", "t", false, true).callback == user_mapping,
	"ordinary terminals retain their terminal-mode mapping")
require("terminal.mode").record()
assert(vim.b[existing].term_mode == nil and vim.b[existing].term_title_watched == nil,
	"ordinary terminals have no mode tracking or title watcher")
local before = vim.api.nvim_buf_get_name(existing)
vim.api.nvim_chan_send(vim.b[existing].terminal_job_id, "printf '\\033]0;ordinary-title\\007'\n")
settle()
assert(vim.api.nvim_buf_get_name(existing) == before, "ordinary OSC titles do not rename buffers")
state.set_last_notification_bufnr(nil)
vim.api.nvim_exec_autocmds("TermRequest", {
	buffer = existing, data = { sequence = "\27]9;unmanaged notification", terminator = "\7" },
})
assert(state.get_last_notification_bufnr() == nil, "ordinary notifications are excluded")
assert(not terminal.focus(existing) and #terminal.list() == 1, "picker API excludes ordinary terminals")
terminal.delete()
terminal.reset()
assert(vim.api.nvim_buf_is_valid(existing), "delete/reset ignore ordinary terminals")
vim.cmd("tabnew")
settle()
vim.cmd("buffer " .. existing)
settle()
assert(#terminal.list() == 1 and not state.is_managed(existing), "tab/window entry never adopts ordinary terminals")

-- A new :term also retains user settings and native failure/success policies.
vim.cmd("enew")
vim.fn.termopen({ "/bin/sh", "-c", "printf ordinary_failure; exit 7" })
local failed = vim.api.nvim_get_current_buf()
wait(function() return vim.fn.jobwait({ vim.b[failed].terminal_job_id }, 0)[1] ~= -1 end, "ordinary command exits")
settle()
assert(vim.api.nvim_buf_is_valid(failed) and vim.wo.number and vim.wo.relativenumber
	and vim.wo.signcolumn == "yes" and vim.wo.scrolloff == 7,
	"ordinary failed output and user window options survive")
assert(#vim.api.nvim_buf_get_keymap(failed, "t") == 0 and not state.is_managed(failed),
	"new ordinary terminal has no plugin-local input mappings")
vim.cmd("enew")
vim.cmd("terminal")
local success = vim.api.nvim_get_current_buf()
vim.api.nvim_chan_send(vim.b[success].terminal_job_id, "exit 0\n")
wait(function() return not vim.api.nvim_buf_is_valid(success) end, "native shell-success cleanup still runs")

-- Managed jobs still close on exit, and convenience commands create panes.
assert(terminal.focus(managed))
vim.cmd("TermVsplit")
settle()
assert(#state.get_current_tab().bufs == 2, "TermVsplit creates a managed pane")
vim.cmd("TermSplit")
settle()
assert(#state.get_current_tab().bufs == 3, "TermSplit creates a managed pane")
vim.cmd("TermTab")
settle()
local latest = vim.api.nvim_get_current_buf()
assert(state.is_managed(latest), "TermTab creates a managed terminal in a new Vim tab")
local prior_closes = custom_closes
vim.api.nvim_chan_send(vim.b[latest].terminal_job_id, "exit 7\n")
wait(function() return not vim.api.nvim_buf_is_valid(latest) end, "managed failed terminals retain plugin cleanup")
assert(custom_closes > prior_closes, "other terminal handlers still run for managed jobs")

-- Replacing a managed pane with :term does not grant ownership, and later
-- workspace operations must not close or overwrite that unrelated terminal.
assert(terminal.focus(managed))
vim.cmd("terminal")
local replacement = vim.api.nvim_get_current_buf()
local replacement_win = vim.api.nvim_get_current_win()
assert(not state.is_managed(replacement), "ordinary :term in a pane is still unmanaged")
terminal.toggle({ open = false })
settle()
assert(vim.api.nvim_win_is_valid(replacement_win) and vim.api.nvim_win_get_buf(replacement_win) == replacement,
	"closing the workspace preserves a pane window replaced by an ordinary terminal")
assert(not terminal.focus(replacement), "replacement is excluded from picker navigation")
assert(vim.v.errmsg == "", "no asynchronous ownership errors")
print("Terminal ownership regressions passed")
