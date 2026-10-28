-- Usage: nvim --clean --headless -l tests/titles.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
require("terminal").setup({ keys = false, set_buffer_name = false })
local autocmds = require("terminal.autocmds")
local original, updates = autocmds.title_changed, 0
local watched
function autocmds.title_changed(buf)
	updates = updates + 1
	watched = buf
	original(buf)
end

-- Exercise callbacks from actual PTY output, inside libuv's read callback.
-- Assigning vim.b.term_title directly misses the event-loop reentry crash.
local job = vim.fn.jobstart({ "python3", "-c", [[
import sys, time
for i in range(3000):
    sys.stdout.write("\033]2;title-%d\007" % i)
    sys.stdout.flush()
    time.sleep(.001)
sys.stdout.flush()
time.sleep(30)
]] }, { term = true })
assert(job > 0, "terminal starts")
local buf = vim.api.nvim_get_current_buf()
assert(vim.wait(10000, function() return updates == 3000 end, 10), "all title callbacks run")
assert(watched == buf, "watcher retains its originating buffer")
assert(vim.wait(2000, function()
	return vim.b[buf].term_title_handled == "title-2999"
end, 10), "coalesced update handles final title")
vim.fn.jobstop(job)
print("Sustained terminal title regressions passed")
