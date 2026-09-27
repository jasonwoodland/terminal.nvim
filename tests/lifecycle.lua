-- Usage: nvim --clean --headless -l tests/lifecycle.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
local state = require("terminal.state")
terminal.setup({ keys = false, set_buffer_name = false })
local function settle() vim.wait(200, function() return false end) end
local failures = 0
local function check(value, message)
	if not value then failures = failures + 1 end
	print((value and "ok - " or "FAIL - ") .. message)
end

terminal.toggle()
settle()
local first = vim.api.nvim_get_current_buf()
terminal.new()
settle()
local second = vim.api.nvim_get_current_buf()
terminal.new()
settle()
local third = vim.api.nvim_get_current_buf()
terminal.go_to(2)
settle()
vim.fn.jobstop(vim.b[first].terminal_job_id)
settle()
check(state.get_current_tab().bufs[1] == second, "background exit preserves selected tab identity")
check(vim.api.nvim_win_get_buf(vim.t.term_winid) == second, "selection matches displayed buffer")

local owner = vim.api.nvim_get_current_tabpage()
vim.cmd("tabnew")
settle()
local foreground = vim.api.nvim_get_current_tabpage()
vim.fn.jobstop(vim.b[third].terminal_job_id)
settle()
check(#vim.t[owner].term_order == 1, "exit removes terminal from its owning Vim tab")
check(vim.api.nvim_get_current_tabpage() == foreground, "background exit preserves Vim tab focus")
check(not state.is_term_open(), "background exit does not open panes in another Vim tab")

-- Close an active terminal, then change Vim tabs before the deferred rebuild.
vim.api.nvim_set_current_tabpage(owner)
settle()
terminal.toggle({ open = true })
settle()
vim.api.nvim_exec_autocmds("TermClose", { buffer = second })
vim.api.nvim_set_current_tabpage(foreground)
settle()
check(vim.api.nvim_get_current_tabpage() == foreground, "deferred close preserves newer focus")
check(not state.is_term_open(), "deferred close rebuild stays in its owning Vim tab")
vim.api.nvim_set_current_tabpage(owner)
settle()
check(not state.is_term_open(), "returning to the owner removes its obsolete pane windows")
check(vim.t.term_needs_rebuild == nil, "owner rebuild flag is consumed")

if failures > 0 then error(failures .. " lifecycle regressions failed") end
print("Lifecycle regressions passed")
