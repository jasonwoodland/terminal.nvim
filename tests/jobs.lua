-- Usage: nvim --clean --headless -l tests/jobs.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
require("terminal").setup({ keys = false, set_buffer_name = false })
local jobs = require("terminal.job")
local state = require("terminal.state")
local function wait(predicate, message) assert(vim.wait(2000, predicate, 10), message) end
local previous = vim.api.nvim_get_current_win()
local successes = 0
local succeeded = jobs.run({ "/bin/sh", "-c", "printf success; exit 0" }, function() successes = successes + 1 end)
wait(function() return successes == 1 end, "success callback completes")
assert(not vim.api.nvim_buf_is_valid(succeeded), "successful output is closed")
assert(vim.api.nvim_get_current_win() == previous, "success preserves focus")

local failed = jobs.run({ "/bin/sh", "-c", "printf failure; exit 7" })
wait(function() return vim.api.nvim_buf_is_valid(failed) and vim.b[failed].terminal_job_status == 7 end,
	"failure status is recorded")
assert(table.concat(vim.api.nvim_buf_get_lines(failed, 0, -1, false)):find("failure"), "failed output is retained")
assert(#state.get_tabs() == 0, "auxiliary jobs are not managed terminal tabs")
local failed_win = vim.fn.bufwinid(failed)
vim.api.nvim_set_current_win(failed_win)
state.adopt_current_terminal()
state.adopt_orphaned_terminals()
assert(#state.get_tabs() == 0, "focus/orphan scans do not adopt command jobs")
vim.api.nvim_set_current_win(previous)

local later, job = jobs.run({ "/bin/sh", "-c", "read ignored; exit 3" })
vim.cmd("new")
local replacement = vim.api.nvim_get_current_win()
vim.api.nvim_win_close(previous, true)
vim.api.nvim_chan_send(job, "done\n")
wait(function() return vim.b[later].terminal_job_status == 3 end, "late failure completes after originating window closes")
assert(vim.api.nvim_get_current_win() == replacement and vim.fn.mode() ~= "i", "late failure does not steal focus or enter insert")
jobs.close()
assert(not vim.api.nvim_buf_is_valid(later) and vim.api.nvim_buf_is_valid(failed), "close selects the newest remaining job")
jobs.close()
assert(not vim.api.nvim_buf_is_valid(failed), "repeated close reaches older retained jobs")

local stopped = jobs.run({ "/bin/sh", "-c", "read ignored" }, function() successes = successes + 1 end)
jobs.close()
wait(function() return not vim.api.nvim_buf_is_valid(stopped) end, "explicit close releases a running job")
assert(successes == 1, "cancelled jobs do not invoke success callbacks")

local before = #vim.api.nvim_list_bufs()
assert(not pcall(jobs.run, { "/path/that/does/not/exist" }), "startup failure is reported")
assert(#vim.api.nvim_list_bufs() == before, "startup failure removes its buffer")
local fugitive = require("terminal.fugitive")
assert(fugitive.run("true") == nil and #vim.api.nvim_list_bufs() == before, "missing Fugitive is handled before starting a job")
vim.cmd([[
let g:terminal_test_fugitive_calls = 0
function! FugitiveDidChange()
  let g:terminal_test_fugitive_calls += 1
endfunction
]])
fugitive.run({ "/bin/sh", "-c", "exit 0" })
wait(function() return vim.g.terminal_test_fugitive_calls == 1 end, "successful job refreshes Fugitive")
print("Auxiliary job regressions passed")
