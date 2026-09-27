-- Usage: nvim --clean --headless -l tests/config.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
local config = require("terminal.config")
config.setup({ keys = false, float = { padding = { x = 2 } } })
config.setup({ keys = { toggle = "<F2>" } })
assert(config.config.keys.toggle == "<F2>" and config.config.keys.zoom, "configuration is built from immutable defaults")
assert(config.config.float.padding.x == 24, "previous setup does not mutate float defaults")
for _, keys in ipairs({ true, { missing = "x" }, { toggle = { 1 } }, { go_to_tab = "x" } }) do
	assert(not pcall(config.setup, { keys = keys }), "invalid key configuration is rejected before installation")
end
local terminal = require("terminal")
terminal.setup({ keys = { paste_register = { "<F2>", "<F3>" }, digraph = { "<F4>", "<F5>" },
	go_to_tab = { "<M-%d>", "<F%d>" } } })
for _, key in ipairs({ "<F2>", "<F2>=", "<F3>", "<F3>=", "<F4>", "<F5>", "<M-1>", "<M-9>", "<F9>" }) do
	assert(vim.fn.maparg(key, "t") ~= "", "list mapping registered: " .. key)
end
local initial = terminal.config
assert(not pcall(terminal.setup, { keys = false }), "reconfiguration is rejected")
assert(terminal.config == initial and terminal.config.keys ~= false, "rejected setup leaves configuration untouched")
terminal.setup()
terminal.setup({})
vim.t.term_winid = 987654
assert(pcall(terminal.send, "text"), "send tolerates stale window")
vim.t.term_winid = vim.api.nvim_get_current_win()
vim.b.terminal_job_id = 987654
local ok, sent = pcall(terminal.send, "text")
assert(ok and sent == false, "send tolerates closed channel")
print("Configuration regressions passed")
