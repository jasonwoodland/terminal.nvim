local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.runtimepath:prepend(root)
local ui = require("tests.helpers.ui").start(root)
local captures = { vim.fn.tempname(), vim.fn.tempname(), vim.fn.tempname() }
local function received(index, expected)
	assert(vim.wait(3000, function()
		local file = io.open(captures[index], "rb")
		if not file then return false end
		local contents = file:read("*a")
		file:close()
		return contents == expected
	end, 5), "reader " .. index .. " did not receive the expected raw bytes")
end
local ok, err = pcall(function()
	ui.lua([[
		local root, paths = ...
		terminal = require('terminal')
		state = require('terminal.state')
		terminal.setup({keys=false})
		function failed(text, buf)
			local ok, reason = terminal.send(text, buf)
			assert(ok == false and type(reason) == 'string')
		end
		failed('no selected pane')
		function reader(index)
			return {cmd={'python3', root .. '/tests/fixtures/terminal_reader.py', paths[index], 'bracketed'}}
		end
		one = terminal.new(reader(1))
		two = terminal.hsplit(reader(2))
		function ready(buf)
			return table.concat(vim.api.nvim_buf_get_lines(buf,0,-1,false), '\n'):find('READER_READY') ~= nil
		end
	]], root, captures)
	ui.wait("return ready(one) and ready(two)", "readers ready")
	ui.lua([[
		assert(terminal.send('visible\n'))
		terminal.toggle({open=false})
		local tab, win, mode = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win(), vim.fn.mode()
		assert(terminal.send('hidden\n'))
		assert(not state.is_term_open() and vim.api.nvim_get_current_tabpage() == tab and vim.api.nvim_get_current_win() == win)
		assert(vim.fn.mode() == mode)
		assert(terminal.send('explicit\n', one))
		vim.cmd('tabnew')
		failed('must not target another tab by default')
		three = terminal.new(reader(3))
	]])
	received(1, "explicit\n")
	received(2, "visible\nhidden\n")
	ui.wait("return ready(three) and vim.fn.mode() == 't'", "other Vim tab reader ready")
	ui.lua([[
		local tab, win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
		assert(terminal.send('cross-tab\n', one))
		assert(vim.api.nvim_get_current_tabpage() == tab and vim.api.nvim_get_current_win() == win and vim.fn.mode() == 't')
		assert(terminal.send('local\n'))
		for _, buf in ipairs({false, 'bad', -1, 0, 999999}) do failed('text', buf) end
		failed(nil, three)
		failed({'text'}, three)
		local job = vim.b[three].terminal_job_id
		vim.b[three].terminal_job_id = nil
		failed('missing job', three)
		vim.b[three].terminal_job_id = 999999
		failed('closed channel', three)
		vim.b[three].terminal_job_id = job
		vim.cmd('stopinsert')
		vim.cmd('new')
		vim.fn.termopen('/bin/sh')
		ordinary = vim.api.nvim_get_current_buf()
		failed('must not reach ordinary terminal\n', ordinary)
		assert(terminal.send('editor-focus\n'), 'default retains this Vim tab last managed pane')
		assert(vim.api.nvim_get_current_buf() == ordinary)
		vim.fn.jobstop(vim.b[one].terminal_job_id)
	]])
	received(1, "explicit\ncross-tab\n")
	received(3, "local\neditor-focus\n")
	ui.wait("return not vim.api.nvim_buf_is_valid(one) or vim.b[one].terminal_job_id == nil or vim.fn.jobwait({vim.b[one].terminal_job_id},0)[1] ~= -1", "job stopped")
	ui.lua("failed('stopped job', one)")
end)
ui.close()
for _, path in ipairs(captures) do vim.fn.delete(path) end
assert(ok, err)
print("Raw terminal sending passed")
