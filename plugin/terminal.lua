local utils = require('terminal.utils')

vim.cmd('command! -nargs=0 TerminalSplit :new|term')
vim.cmd('command! -nargs=0 TerminalVsplit :vnew|term')
vim.cmd('command! -nargs=? TerminalTab :<args>tabnew|term')
vim.cmd('command! -nargs=0 TerminalClose :call CloseTerminal()')
vim.cmd('command! -nargs=0 TerminalReset :exe "te"|bd!#|let t:term_bufnr = bufnr("%")')

utils.alias('st', 'TerminalSplit')
utils.alias('vt', 'TerminalVsplit')
utils.alias('tt', 'TerminalTab')
utils.alias('tc', 'TerminalClose')

vim.g.term_bufnr = vim.g.term_bufnr or nil
vim.t.term_winid = vim.g.term_winid or 0
vim.t.term_height = vim.t.term_height or 25
vim.t.current_win = vim.t.current_win or 0

vim.cmd [[
augroup ToggleTerminal
  autocmd!
  autocmd TermOpen * setlocal signcolumn=no nonumber norelativenumber scrolloff=0 display=
  autocmd TabNew * let t:term_height = 25
  autocmd WinLeave * lua SaveTerminalHeight()
augroup END
]]

function SaveTerminalHeight()
	if vim.fn.exists("t:term_bufnr") ~= 0 then
		vim.t.term_height = vim.fn.winheight(vim.fn.bufwinnr(vim.t.term_bufnr))
	end
end

function ToggleTerminal(height)
	if vim.t.term_winid ~= 0 and vim.fn.win_id2win(vim.t.term_winid) > 0 then
		if vim.fn.win_getid() ~= vim.t.term_winid then
			vim.t.current_win = vim.fn.win_getid()
			vim.api.nvim_set_current_win(vim.t.term_winid)
			vim.cmd('startinsert')
			return
		end
		vim.g.term_bufnr = vim.api.nvim_win_get_buf(vim.t.term_winid)
		vim.t.term_height = vim.fn.winheight(vim.fn.bufwinnr(vim.g.term_bufnr))
		vim.cmd(vim.fn.bufwinnr(vim.g.term_bufnr) .. 'close')
		if vim.t.current_win > 0 then
			vim.api.nvim_set_current_win(vim.t.current_win)
		end
	else
		vim.t.current_win = vim.fn.win_getid()
		vim.t.prev_winid = vim.fn.win_getid()
		if vim.fn.exists('g:term_bufnr') ~= 0 and vim.fn.bufexists(vim.g.term_bufnr) ~= 0 then
			vim.cmd('botright sb' .. vim.g.term_bufnr)
			vim.t.term_winid = vim.fn.win_getid()
		else
			vim.cmd("botright sp term://" .. vim.env.SHELL)
			vim.cmd [[ autocmd TermClose <buffer> execute 'bdelete! ' . expand('<abuf>') ]]
		end

		local terminal_height = height > 1 and height or vim.t.term_height
		vim.cmd("res " .. terminal_height)
		vim.cmd("set wfh")
		vim.g.term_bufnr = vim.fn.bufnr()
		vim.t.term_winid = vim.fn.win_getid()
		vim.cmd("startinsert")
	end
end

vim.api.nvim_set_keymap('n', '<C-bs>', [[<Cmd>lua ToggleTerminal(vim.v.count1)<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('t', '<C-bs>', [[<C-\><C-n><Cmd>lua ToggleTerminal(vim.v.count1)<CR>]],
	{ noremap = true, silent = true })

vim.api.nvim_set_keymap('t', '<C-\\>', [[<C-\><C-n>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('t', '<C-pageup>', [[<C-\><C-n><C-pageup>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('t', '<C-pagedown>', [[<C-\><C-n><C-pagedown>]], { noremap = true, silent = true })

function SwitchTerminal(delta)
	local bufs = {}
	for i = 1, vim.fn.bufnr("$") do
		if vim.fn.getbufvar(i, "&buftype") == "terminal" then
			table.insert(bufs, i)
		end
	end

	local i = vim.fn.index(bufs, vim.fn.bufnr("%"))
	if i == nil then
		i = delta == 1 and #bufs or 1
	else
		i = i + delta
	end

	local b = bufs[(i) % #bufs + 1]
	vim.cmd("buffer " .. b)
end

function CloseTerminal()
	if vim.bo.buftype ~= "terminal" then return end
	SwitchTerminal(-1)
	if _G.term_bufnr ~= vim.fn.bufnr("%") then
		vim.cmd("bdelete!")
		_G.term_bufnr = vim.fn.bufnr("%")
	else
		vim.cmd("bdelete!")
	end
end

-- Map keys
vim.api.nvim_set_keymap("n", "[t", [[<Cmd>lua SwitchTerminal(-1)<CR>]], { silent = true })
vim.api.nvim_set_keymap("n", "]t", [[<Cmd>lua SwitchTerminal(1)<CR>]], { silent = true })

function TerminalJob(cmd, cb)
	vim.cmd("bot new +resize10")
	local bufnr = vim.fn.bufnr()
	vim.fn.termopen(cmd, {
		on_exit = function(job_id, code, event)
			if code == 0 then
				vim.cmd("bd" .. bufnr)
				if cb then cb() end
			else
				vim.cmd("wincmd p")
				vim.cmd("resize 25")
				vim.cmd("startinsert")
			end
		end
	})
	vim.cmd("norm G")
	_G.terminal_job_bufnr = bufnr
	vim.cmd("wincmd p")
end

function TerminalJobClose()
	vim.cmd("bd!" .. _G.terminal_job_bufnr)
end

function FugitiveJob(cmd)
	TerminalJob(cmd, ReloadFugitiveBuffers)
end

vim.cmd("command! -nargs=1 -complete=shellcmd TerminalJob lua TerminalJob(<q-args>)")
vim.cmd("command! -nargs=1 -complete=shellcmd FugitiveJob lua FugitiveJob(<q-args>)")
vim.cmd("command! TerminalJobClose lua TerminalJobClose()")

vim.cmd("cabbrev tj TerminalJob")
vim.cmd("cabbrev tjc TerminalJobClose")

function ReloadFugitiveBuffers()
	vim.cmd("call FugitiveDidChange()")
	print("Reloading fugitive buffers")
	-- local buf_list = vim.api.nvim_list_bufs()
	-- local current_buf = vim.api.nvim_get_current_buf()

	-- for _, buf_id in ipairs(buf_list) do
	-- 	local buf_name = vim.api.nvim_buf_get_name(buf_id)
	-- 	if string.find(buf_name, 'fugitive:') then
	-- 		print("Reloading " .. buf_name)
	-- 		vim.api.nvim_set_current_buf(buf_id)
	-- 		vim.cmd('edit!')
	-- 	end
	-- end
	-- vim.api.nvim_set_current_buf(current_buf)
end
