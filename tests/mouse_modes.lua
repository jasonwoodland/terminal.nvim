vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ':p:h:h'))
local mouse = require('terminal.mouse')
local buf = vim.api.nvim_get_current_buf()
vim.b[buf].term_mode, vim.b[buf].terminal_job_id = 't', 42
local output, modifiers = '', 0
local send, getmod = vim.fn.chansend, vim.fn.getcharmod
vim.fn.chansend = function(job, data) assert(job == 42); output = data; return #data end
vim.fn.getcharmod = function() return modifiers end
local feed = mouse.observe(buf)
local function emit(data) feed(42, {data}) end
local function wheel(expected)
	output = ''
	local handled = mouse.wheel(vim.api.nvim_get_current_win(), '<ScrollWheelUp>', {screenrow=3,screencol=4})
	assert(handled == (expected ~= nil) and output == (expected or ''), vim.inspect({handled,output,expected}))
end
wheel(nil)
emit('\27[?1049h') -- Alternate screen alone is insufficient.
wheel(nil)
emit('\27[?10'); emit('02;1006h')
wheel('\27[<64;4;3M')
modifiers = 14
wheel('\27[<92;4;3M')
modifiers = 0
emit('\27]0;fake \27[?1002l\7')
emit('\27Pfake \27[?1002l\27'); emit('\\')
wheel('\27[<64;4;3M')
emit('\27[?1002s\27[?1002l')
wheel(nil)
emit('\27[?1002r\27[?1006l')
wheel('\27[M' .. string.char(96,36,35))
emit('\27[?1005h')
wheel('\27[M' .. string.char(96,36,35))
emit('\27[?1015h')
wheel('\27[96;4;3M')
emit('\27[?1006h')
wheel('\27[<64;4;3M')
emit('\27[?1016h')
wheel(nil)
emit('\27c')
wheel(nil)
emit('\27[?1000;1006h')
vim.b[buf].term_mode = 'n'
wheel(nil)
vim.b[buf].term_mode = 't'
mouse.detach(buf)
wheel(nil)
vim.fn.chansend, vim.fn.getcharmod = send, getmod
print('Terminal mouse mode tracking regressions passed')
