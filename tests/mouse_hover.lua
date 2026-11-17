local root = vim.fn.fnamemodify(arg[0], ':p:h:h')
local function bytes(path)
	local file = io.open(path, 'rb')
	if not file then return '' end
	local data = file:read('*a')
	file:close()
	return data
end
local program = [[
import os, sys, tty
tty.setraw(sys.stdin.fileno())
def emit(data): os.write(1, data)
emit(b'\x1b[?1002h\x1b[?1006hREADER_READY\r\n')
with open(sys.argv[1], 'ab', buffering=0) as output:
    while True:
        data = os.read(0, 4096)
        if data == b'\x01':
            emit(b'\x1b[?1002l\x1b[?1006l' + b'scrollback\r\n' * 150 + b'MOUSE_OFF\r\n')
        elif data == b'\x02':
            emit(b'\x1b[?1002h\x1b[?1006hMOUSE_ON\r\n')
        else: output.write(data)
]]
for _, floating in ipairs({ false, true }) do
	local ui = dofile(root .. '/tests/helpers/ui.lua').start(root, 120, 50)
	local capture = vim.fn.tempname()
	local ok, err = xpcall(function()
		ui.lua([[
			local capture, program, floating = ...
			terminal = require('terminal')
			terminal.setup({keys=false, set_buffer_name=false, float={enabled=floating}})
			vim.o.mouse = 'a'
			hover_buf = terminal.new({cmd={'python3','-c',program,capture}})
			hover_win = vim.api.nvim_get_current_win()
			other = terminal.vsplit({cmd='/bin/sh'})
			hover_win = vim.fn.bufwinid(hover_buf)
			focus = vim.api.nvim_get_current_win()
		]], capture, program, floating)
		ui.wait([[return vim.api.nvim_get_mode().mode == 't' and table.concat(vim.api.nvim_buf_get_lines(hover_buf,0,-1,false),'\n'):find('READER_READY') ~= nil]], 'reader ready')
		local pos = ui.lua([[local p=vim.api.nvim_win_get_position(hover_win); return {p[1]+2,p[2]+3}]])
		local expected = ''
		local function wheel(direction)
			ui.request('nvim_input_mouse','wheel',direction,'',0,pos[1],pos[2])
			expected = expected .. string.format('\27[<%d;4;3M', direction == 'up' and 64 or 65)
			assert(vim.wait(3000,function() return bytes(capture)==expected end,10), 'hover wheel bytes: '..vim.inspect(bytes(capture)))
			assert(ui.lua([[return vim.api.nvim_get_current_win()==focus and vim.api.nvim_get_mode().mode=='t' and require('terminal.follow').is_following(hover_win)]]), 'hover scrolling preserves focus, mode and following')
		end
		wheel('up')
		wheel('down')
		-- Also forward when the source is a normal editor window.
		ui.lua([[
			vim.cmd('stopinsert')
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_get_config(win).relative == '' and not require('terminal.state').is_managed(vim.api.nvim_win_get_buf(win)) then
					vim.api.nvim_set_current_win(win)
					break
				end
			end
			focus=vim.api.nvim_get_current_win()
		]])
		ui.wait([[return vim.api.nvim_get_mode().mode == 'n']], 'editor normal mode')
		pos = ui.lua([[local p=vim.api.nvim_win_get_position(hover_win); return {p[1]+2,p[2]+3}]])
		ui.request('nvim_input_mouse','wheel','up','',0,pos[1],pos[2])
		expected = expected .. '\27[<64;4;3M'
		assert(vim.wait(3000,function() return bytes(capture)==expected end,10), 'editor hover forwards')
		assert(ui.lua([[return vim.api.nvim_get_current_win()==focus and vim.api.nvim_get_mode().mode=='n']]), 'editor focus preserved')
		ui.lua([[vim.fn.chansend(vim.b[hover_buf].terminal_job_id,'\1')]])
		ui.wait([[return table.concat(vim.api.nvim_buf_get_lines(hover_buf,0,-1,false),'\n'):find('MOUSE_OFF') ~= nil]], 'mouse reporting disabled')
		ui.request('nvim_input_mouse','wheel','up','',0,pos[1],pos[2])
		ui.wait([[return not require('terminal.follow').is_following(hover_win)]], 'disabled reporting scrolls buffer')
		assert(bytes(capture)==expected, 'disabled reporting sends no input')
		-- Resume following and re-enable reporting without entering alternate screen.
		ui.lua([[require('terminal.follow').set_following(hover_win,true); vim.fn.chansend(vim.b[hover_buf].terminal_job_id,'\2')]])
		ui.wait([[return table.concat(vim.api.nvim_buf_get_lines(hover_buf,0,-1,false),'\n'):find('MOUSE_ON') ~= nil]], 'mouse reporting re-enabled')
		ui.request('nvim_input_mouse','wheel','down','',0,pos[1],pos[2])
		expected = expected .. '\27[<65;4;3M'
		assert(vim.wait(3000,function() return bytes(capture)==expected end,10), 'reporting resumes')
	end, debug.traceback)
	ui.close()
	vim.fn.delete(capture)
	assert(ok, err)
end
print('Inactive terminal mouse wheel regressions passed')
