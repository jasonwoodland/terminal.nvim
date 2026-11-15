-- Usage: nvim --clean --headless -l tests/rename.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
terminal.setup({ keys = false, show_winbar_when_single_tab = true })
local function settle() vim.wait(150, function() return false end) end
local function title(buf)
	for _, item in ipairs(terminal.list()) do
		if item.bufnr == buf then return item.title end
	end
end
local function bar()
	local win = vim.t.term_winbar_winid
	assert(win and vim.api.nvim_win_is_valid(win), "winbar is visible")
	return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false))
end
terminal.toggle()
settle()
local first = vim.api.nvim_get_current_buf()
vim.api.nvim_chan_send(vim.b[first].terminal_job_id, "printf '\\033]0;automatic-one\\007'\n")
assert(vim.wait(2000, function() return vim.b[first].term_title_handled == "automatic-one" end, 10))
local buffer_name = vim.api.nvim_buf_get_name(first)
assert(terminal.rename("  Frontend/api worker  "))
assert(title(first) == "Frontend/api worker" and bar():find("Frontend/api worker", 1, true),
	"custom names appear unchanged in picker metadata and winbar")
assert(vim.api.nvim_buf_get_name(first) == buffer_name, "rename does not change the terminal URI")
vim.api.nvim_chan_send(vim.b[first].terminal_job_id, "printf '\\033]0;automatic-two\\007'\n")
assert(vim.wait(2000, function() return vim.b[first].term_title_handled == "automatic-two" end, 10))
assert(title(first) == "Frontend/api worker" and bar():find("Frontend/api worker", 1, true),
	"OSC updates do not replace custom names")
assert(terminal.rename(""))
assert(title(first) == "automatic-two" and bar():find("automatic-two", 1, true),
	"clearing restores the latest automatic title")
vim.cmd("TermRename Frontend API")
assert(title(first) == "Frontend API", "command accepts names containing spaces")
vim.cmd("TermRename!")
assert(title(first) == "automatic-two", "bang restores automatic naming")
for _, invalid in ipairs({ 7, false, "bad\nname", "bad\tname", "bad\127name" }) do
	assert(not terminal.rename(invalid), "invalid names are rejected")
end
assert(title(first) == "automatic-two", "invalid input leaves the name unchanged")

terminal.vsplit()
settle()
local second = vim.api.nvim_get_current_buf()
assert(terminal.rename("Backend", second))
assert(bar():find("Backend", 1, true), "focused pane supplies the tab's display name")
local replacement = terminal.reset()
settle()
assert(replacement and replacement ~= second and title(replacement) == "Backend",
	"reset preserves the pane name on its replacement job")
assert(not terminal.rename("stale", second), "deleted jobs cannot be renamed")
terminal.break_pane_to_tab()
settle()
terminal.move(-1)
settle()
assert(title(replacement) == "Backend" and bar():find("Backend", 1, true),
	"name follows a pane through break-to-tab and reordering")

local input, notices = vim.ui.input, {}
local notify = vim.notify
vim.notify = function(message) notices[#notices + 1] = message end
local confirm, defaults
vim.ui.input = function(opts, callback) defaults, confirm = opts, callback end
vim.cmd("TermRename")
assert(defaults.default == "Backend", "rename prompt starts with the custom name")
assert(terminal.focus(first))
confirm("Database")
assert(title(replacement) == "Database" and title(first) == "automatic-two",
	"asynchronous prompt renames its original pane after focus changes")
assert(terminal.focus(replacement))
vim.cmd("TermRename")
confirm(nil)
assert(title(replacement) == "Database", "cancel leaves the name unchanged")
vim.cmd("TermRename")
confirm("")
assert(title(replacement) ~= "Database", "empty prompt restores automatic naming")
vim.cmd("TermRename! invalid")
assert(#notices == 1, "bang plus a name is rejected")
vim.cmd("TermRename")
terminal.delete()
settle()
confirm("Too late")
assert(#notices == 2 and title(first) == "automatic-two", "closed prompt target cannot rename a different pane")
vim.ui.input, vim.notify = input, notify

local owner = vim.api.nvim_get_current_tabpage()
vim.cmd("tabnew")
settle()
local editor = vim.api.nvim_get_current_buf()
assert(terminal.rename("Hidden frontend", first), "explicit buffer can name a pane in another Vim tab")
assert(vim.api.nvim_get_current_buf() == editor, "background rename does not move focus")
assert(not terminal.rename("Unmanaged", editor), "ordinary buffers are excluded")
assert(terminal.focus(first))
settle()
assert(vim.api.nvim_get_current_tabpage() == owner and bar():find("Hidden frontend", 1, true),
	"background rename appears when the owning tab is shown")
assert(vim.v.errmsg == "", "no asynchronous rename errors")
print("Terminal rename regressions passed")
