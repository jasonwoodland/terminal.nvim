-- Usage: nvim --clean --headless -l tests/input.lua (requires python3)
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.runtimepath:prepend(root)
local helper = dofile(root .. "/tests/helpers/ui.lua")
local ui = helper.start(root)
local captures = {}
local function bytes(path)
	local file = io.open(path, "rb")
	if not file then return "" end
	local value = file:read("*a")
	file:close()
	return value
end
local function received(path, expected, message)
	assert(vim.wait(3000, function() return bytes(path) == expected end, 10),
		message .. ": expected " .. vim.inspect(expected) .. ", received " .. vim.inspect(bytes(path)))
end
local ok, err = xpcall(function()
	ui.lua([[require('terminal').setup({ set_buffer_name = false, keys = {
		paste_register = '<F6>', digraph = '<F7>', toggle = '<F2>', new = '<F3>', prev = '<F4>', next = '<F5>',
	} })]])
	for _, protocol in ipairs({ "raw", "bracketed" }) do
		local capture = vim.fn.tempname()
		captures[#captures + 1] = capture
		ui.lua([[
			local root, capture, protocol = ...
			vim.cmd('enew')
			vim.fn.termopen({ 'python3', root .. '/tests/fixtures/terminal_reader.py', capture, protocol })
			vim.cmd('startinsert')
		]], root, capture, protocol)
		ui.wait([[return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('READER_READY') ~= nil
			and vim.api.nvim_get_mode().mode == 't']], "reader is ready in Terminal mode")
		local function wrapped(text)
			return protocol == "bracketed" and "\27[200~" .. text .. "\27[201~" or text
		end
		ui.lua([[vim.fn.setreg('a', 'one\ntwo\n')]])
		ui.input("<F6>a")
		local expected = wrapped("one\ntwo\n")
		received(capture, expected, protocol .. " register paste follows negotiated paste mode")
		ui.input([[<F6>="three\nfour"<CR>]])
		expected = expected .. wrapped("three\nfour")
		received(capture, expected, protocol .. " expression paste follows negotiated paste mode")
		ui.input("<F7>a:")
		expected = expected .. "ä"
		received(capture, expected, protocol .. " digraph input")
		ui.input("<F7>x<Esc>")
		ui.input("<F6><Esc><F7>q!")
		expected = expected .. "!"
		received(capture, expected, protocol .. " cancelled digraph and undefined pair")
		ui.input("<F6>=execute('enew')<CR>")
		ui.wait([[return vim.bo.buftype == '']], "expression may switch away from its originating terminal")
		assert(ui.lua([[return vim.api.nvim_buf_get_lines(0, 0, -1, false)]])[1] == "",
			"stale expression result is not inserted into the editor")
		assert(bytes(capture) == expected, "stale expression result is not sent to the old job")
	end
	local shell_output = vim.fn.tempname()
	captures[#captures + 1] = shell_output
	ui.lua([[
		vim.cmd('enew')
		vim.fn.termopen({ '/bin/sh' })
		vim.fn.setreg('a', "printf '%s\\n' 'shell paste works' > " .. vim.fn.shellescape(...) .. "\n")
		vim.cmd('startinsert')
	]], shell_output)
	ui.wait([[return vim.api.nvim_get_mode().mode == 't']], "shell is in Terminal mode")
	ui.input("<F6>a")
	received(shell_output, "shell paste works\n", "register paste executes normally in a shell")
	assert(ui.lua('return vim.v.errmsg') == '', 'no asynchronous input errors')
end, debug.traceback)
ui.close()
for _, path in ipairs(captures) do vim.fn.delete(path) end
assert(ok, err)
print("Attached-UI terminal input regressions passed")
