local root = vim.fn.fnamemodify(arg[0], ':p:h:h')
local function bytes(path)
	local file = io.open(path, 'rb')
	if not file then return '' end
	local data = file:read('*a')
	file:close()
	return data
end
for _, floating in ipairs({ false, true }) do
	local ui = dofile(root .. '/tests/helpers/ui.lua').start(root, 120, 50)
	local capture = vim.fn.tempname()
	local ok, err = xpcall(function()
		ui.lua([[
			local root, capture, floating = ...
			terminal = require('terminal')
			terminal.setup({keys=false,set_buffer_name=false,float={enabled=floating}})
			vim.o.mouse='a'
			vim.o.mousetime=0
			editor=vim.api.nvim_get_current_win()
			target=terminal.new({cmd={'python3',root..'/tests/fixtures/terminal_reader.py',capture,'mouse'}})
			other=terminal.vsplit({cmd='/bin/sh'})
			target_win=vim.fn.bufwinid(target)
		]], root, capture, floating)
		ui.wait([[return vim.api.nvim_get_mode().mode=='t' and table.concat(vim.api.nvim_buf_get_lines(target,0,-1,false),'\n'):find('READER_READY')~=nil]], 'mouse reader ready')
		local expected = ''
		for _, source in ipairs({ 'terminal', 'editor' }) do
			ui.lua([[
				local source=...
				if source=='terminal' then terminal.focus(other)
				else vim.api.nvim_set_current_win(editor); vim.cmd('stopinsert') end
				require('terminal.follow').set_following(target_win,false)
			]], source)
			ui.wait(source == 'terminal' and [[return vim.api.nvim_get_mode().mode=='t' and vim.api.nvim_get_current_buf()==other]]
				or [[return vim.api.nvim_get_mode().mode=='n' and vim.api.nvim_get_current_win()==editor]], 'source mode ready')
			local pos=ui.lua([[local p=vim.api.nvim_win_get_position(target_win);return {p[1]+2,p[2]+3}]])
			for _, event in ipairs({{'press',0,0,'M'},{'drag',1,32,'M'},{'release',1,0,'m'}}) do
				ui.request('nvim_input_mouse','left',event[1],'',0,pos[1],pos[2]+event[2])
				expected=expected..string.format('\27[<%d;%d;3%s',event[3],4+event[2],event[4])
				-- nvim_input_mouse shares a position slot across queued events;
				-- wait for each event to be consumed before moving the pointer.
				assert(vim.wait(3000,function() return bytes(capture)==expected end,10), source..' native '..event[1]..': '..vim.inspect(bytes(capture)))
			end
			assert(vim.wait(3000,function() return bytes(capture)==expected end,10), source..' native gesture: '..vim.inspect(bytes(capture)))
			ui.wait([[return vim.api.nvim_get_current_win()==target_win and vim.api.nvim_get_mode().mode=='t'
				and require('terminal.follow').is_following(target_win)]], 'click focuses in Terminal mode and resumes following')
			assert(ui.lua([[return vim.b[other].term_mode=='t']]), 'source terminal keeps its saved mode')
		end
		-- Explicit Normal mode retains native text selection instead of forwarding.
		ui.input('<C-\\><C-n>')
		ui.wait([[return vim.fn.mode()=='n' and vim.b[target].term_mode=='n']], 'target Normal mode saved')
		ui.lua([[terminal.focus(other)]])
		ui.wait([[return vim.api.nvim_get_mode().mode=='t' and vim.api.nvim_get_current_buf()==other]], 'other terminal focused')
		local pos=ui.lua([[local p=vim.api.nvim_win_get_position(target_win);return {p[1]+2,p[2]+3}]])
		ui.request('nvim_input_mouse','left','press','',0,pos[1],pos[2])
		ui.wait([[return vim.api.nvim_get_current_win()==target_win]], 'Normal-mode pane focused')
		ui.request('nvim_input_mouse','left','drag','',0,pos[1],pos[2]+2)
		ui.wait([[return vim.fn.mode():match('[vV\22]')~=nil]], 'Normal-mode drag selects text')
		ui.request('nvim_input_mouse','left','release','',0,pos[1],pos[2]+2)
		ui.wait([[return vim.api.nvim_get_current_win()==target_win and vim.fn.mode():match('[vV\22]')~=nil]], 'Normal-mode pane selects text')
		assert(bytes(capture)==expected,'Normal-mode selection sends no input')
	end,debug.traceback)
	ui.close()
	vim.fn.delete(capture)
	assert(ok,err)
end
print('Native terminal mouse focus and drag regressions passed')
