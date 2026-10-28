-- Usage: nvim --clean --headless -l tests/follow.lua
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
for _, case in ipairs({ { false, false }, { false, true }, { true, false }, { true, true } }) do
	local floating, with_winbar = unpack(case)
	local ui = dofile(root .. "/tests/helpers/ui.lua").start(root)
	local ok, err = xpcall(function()
		ui.lua([[
			require('terminal').setup({ set_buffer_name = false, float = { enabled = ... },
				keys = { toggle = '<F2>', vsplit = '<F9>' } })
			_G.source_buf = vim.api.nvim_create_buf(false, true)
			_G.channel = vim.api.nvim_open_term(source_buf, {})
		]], floating)
		ui.input('<F2>')
		ui.wait([[return vim.api.nvim_get_current_buf() == source_buf and vim.api.nvim_get_mode().mode == 't']], 'source enters Terminal mode')
		if with_winbar then
			ui.lua([[require('terminal').new(); require('terminal').go_to(1)]])
			ui.wait([[return vim.api.nvim_get_current_buf() == source_buf and vim.wo.winbar ~= ''
				and vim.api.nvim_get_mode().mode == 't']], 'second tab makes winbar visible')
		end
		ui.lua([[
			local lines = {}
			for i = 1, 100 do lines[i] = 'output ' .. i .. '\r\n' end
			vim.api.nvim_chan_send(channel, table.concat(lines) .. '\27[3;1Hprompt')
		]])
		ui.wait([[return vim.api.nvim_buf_line_count(source_buf) > 80]], 'scrollback populated')
		ui.input('<F9>')
		ui.wait([[return #vim.t.term_winids == 2 and vim.api.nvim_get_mode().mode == 't']], 'split focuses new pane')
		ui.lua([[
			_G.focus = vim.api.nvim_get_current_win()
			for _, win in ipairs(vim.t.term_winids) do
				if vim.api.nvim_win_get_buf(win) == source_buf then _G.source_win = win end
			end
			_G.enters = 0
			vim.api.nvim_create_autocmd({'WinEnter', 'TermEnter'}, { callback = function() enters = enters + 1 end })
			_G.at_live_screen = function()
				for _, win in ipairs(vim.t.term_winids) do
					if vim.api.nvim_win_get_buf(win) == source_buf then source_win = win end
				end
				local last = vim.api.nvim_buf_line_count(source_buf)
				local view = vim.api.nvim_win_call(source_win, vim.fn.winsaveview)
				local height = vim.api.nvim_win_get_height(source_win) - (vim.wo[source_win].winbar ~= '' and 1 or 0)
				return view.topline == math.max(1, last - height + 1)
			end
		]])
		ui.wait([[return at_live_screen()]], 'split keeps inactive pane on live screen')
		-- Output redraws with the application cursor above the final screen row.
		ui.lua([[vim.api.nvim_chan_send(channel, '\27[2J\27[2;1Hredrawn prompt')]])
		ui.lua([[vim.wait(100, function() return false end)]])
		ui.wait([[return at_live_screen()]], 'redraw follows without focusing source')
		assert(ui.lua([[return vim.api.nvim_get_current_win() == focus and vim.api.nvim_get_mode().mode == 't'
			and enters == 0]]), 'output following never changes focus or mode or emits enter events')
		ui.request('nvim_ui_try_resize', 82, 28)
		ui.wait([[return at_live_screen()]], 'UI resize keeps inactive pane on live screen')
		ui.lua([[
			_G.focus = vim.api.nvim_get_current_win()
			_G.enters = 0
			vim.b[source_buf].term_mode = 'n'
			vim.api.nvim_win_set_cursor(source_win, { 5, 0 })
			vim.api.nvim_win_call(source_win, function() vim.fn.winrestview({ topline = 1 }) end)
			vim.api.nvim_chan_send(channel, '\27[4;1Hnormal mode redraw')
		]])
		-- Drain the emulator refresh and scheduled callbacks before checking that
		-- normal-mode scrollback wasn't pulled back to the live screen.
		ui.lua([[vim.wait(100, function() return false end)]])
		assert(ui.lua([[return vim.api.nvim_win_get_cursor(source_win)[1] == 5
			and vim.api.nvim_win_call(source_win, vim.fn.winsaveview).topline == 1]]), 'normal-mode scrollback preserved')
		assert(ui.lua([[return vim.api.nvim_get_current_win() == focus and vim.api.nvim_get_mode().mode == 't'
			and enters == 0 and vim.v.errmsg == '']]), 'following never changes focus or mode or emits enter events')
	end, debug.traceback)
	ui.close()
	assert(ok, err)
end
print('Inactive terminal following regressions passed')
