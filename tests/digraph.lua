-- Usage: nvim --clean --headless -l tests/digraph.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
local callback, sends
vim.on_key = function(fn) callback = fn end
vim.fn.mode = function() return "t" end
vim.api.nvim_chan_send = function(_, text) sends[#sends + 1] = text end
vim.b.terminal_job_id = 123
require("terminal.digraph").setup("<F7>")
local start
for _, map in ipairs(vim.api.nvim_get_keymap("t")) do
	if map.lhs == "<F7>" then start = map.callback end
end
local function flush() vim.wait(10, function() return false end) end
local function pair(first, second)
	sends = {}
	start()
	local cb = callback
	assert(cb(first, first) == "", "first key is consumed")
	assert(cb(second, second) == "", "second key is consumed")
	assert(callback == nil, "completed session detaches immediately")
	assert(cb("x", "x") == nil, "queued keys after completion pass through")
	flush()
	assert(#sends == 1, "exactly one send per completed pair")
	return sends[1]
end
local buffers = #vim.api.nvim_list_bufs()
assert(pair("a", ":") == "ä", "known digraph")
assert(pair("q", "!") == "!", "unknown ASCII pair uses the second character")
assert(pair("é", "x") == "x", "multibyte first character does not call the byte-only API")
assert(pair("a", "雪") == "雪", "multibyte second character passes through")
assert(pair("a", vim.api.nvim_replace_termcodes("<Left>", true, false, true)) == "<Left>",
	"special second key is sent in printable form")
assert(#vim.api.nvim_list_bufs() == buffers, "completed sessions release indicator buffers")

sends = {}
for _ = 1, 3 do start(); callback("\27", "\27"); flush() end
assert(#sends == 0 and #vim.api.nvim_list_bufs() == buffers, "cancelled sessions release buffers without sending")
start()
callback("a", "a")
callback(":", ":")
start()
local next_callback = callback
flush()
assert(callback == next_callback and #sends == 0, "old completion cannot close or send from a new session")
callback("\27", "\27")
flush()

start()
callback("a", "a")
callback(":", ":")
vim.b.terminal_job_id = 456
flush()
assert(#sends == 0, "stale job is not used by a deferred send")
vim.api.nvim_chan_send = function() error("closed channel") end
start(); callback("a", "a"); callback(":", ":"); flush()
assert(#vim.api.nvim_list_bufs() == buffers, "closed channel still releases resources")
print("Digraph regressions passed")
