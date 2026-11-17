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
			local root,capture,floating=...
			terminal=require('terminal')
			terminal.setup({keys=false,set_buffer_name=false,show_winbar_when_single_tab=true,float={enabled=floating}})
			vim.o.mouse, vim.o.mousetime='a',0
			target=terminal.new({cmd={'python3',root..'/tests/fixtures/terminal_reader.py',capture,'mouse'}})
			other=terminal.vsplit({cmd='/bin/sh'})
			target_win=vim.fn.bufwinid(target)
		]],root,capture,floating)
		ui.wait([[return vim.api.nvim_get_mode().mode=='t' and table.concat(vim.api.nvim_buf_get_lines(target,0,-1,false),'\n'):find('READER_READY')~=nil]],'reader ready')
		local expected=''
		for _, active in ipairs({true,false}) do
			ui.lua([[terminal.focus((...) and target or other)]],active)
			ui.wait([[return vim.api.nvim_get_mode().mode=='t']],'source ready')
			local rect=ui.lua([[local p=vim.api.nvim_win_get_position(target_win);local bar=vim.wo[target_win].winbar~='' and 1 or 0;return {p[1]+bar,p[2],vim.api.nvim_win_get_width(target_win),vim.api.nvim_win_get_height(target_win)-bar}]])
			local function event(action,row,col,code,x,y,suffix)
				ui.request('nvim_input_mouse','left',action,'',0,row,col)
				expected=expected..string.format('\27[<%d;%d;%d%s',code,x,y,suffix or 'M')
				assert(vim.wait(3000,function() return bytes(capture)==expected end,10), action..' outside: '..vim.inspect(bytes(capture)))
				assert(ui.lua([[return vim.api.nvim_get_current_win()==target_win and vim.api.nvim_get_mode().mode=='t']]),'gesture remains in originating pane')
			end
			event('press',rect[1]+2,rect[2]+3,0,4,3)
			-- Cross the separator into the neighbouring pane, then re-enter.
			event('drag',rect[1]+2,rect[2]+rect[3]+3,32,rect[3],3)
			event('drag',rect[1]+rect[4]+1,rect[2]+4,32,5,rect[4])
			if rect[2]>1 then event('drag',rect[1]+2,rect[2]-2,32,1,3) end
			event('drag',rect[1]+2,rect[2]+4,32,5,3)
			-- Leave above the pane and release there: neither event ends focus.
			event('drag',rect[1]-2,rect[2]+4,32,5,1)
			event('release',rect[1]-2,rect[2]+4,0,5,1,'m')
			-- A fresh press proves native held-button state was released.
			event('press',rect[1]+2,rect[2]+3,0,4,3)
			event('release',rect[1]+2,rect[2]+3,0,4,3,'m')
		end
	end,debug.traceback)
	ui.close()
	vim.fn.delete(capture)
	assert(ok,err)
end
print('Terminal drag capture across pane boundaries passed')
