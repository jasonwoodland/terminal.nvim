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
		ui.lua([[_G.focus = vim.api.nvim_get_current_win()]])
		local pos = ui.lua([[vim.o.mouse = 'a'; local p = vim.api.nvim_win_get_position(source_win); return {p[1] + 2, p[2] + 2}]])
		ui.request('nvim_input_mouse', 'wheel', 'up', '', 0, pos[1], pos[2])
		ui.wait([[return not require('terminal.follow').is_following(source_win) and not at_live_screen()]], 'wheel pauses following')
		ui.lua([[
			_G.scrolled_top = vim.api.nvim_win_call(source_win, vim.fn.winsaveview).topline
			vim.api.nvim_chan_send(channel, '\27[4;1Hpaused redraw')
			vim.wait(100, function() return false end)
		]])
		assert(ui.lua([[return vim.api.nvim_win_call(source_win, vim.fn.winsaveview).topline == scrolled_top
			and vim.b[source_buf].term_mode == 't' and vim.api.nvim_get_current_win() == focus]]), 'paused output preserves view, mode and focus')
		local function open_menu(label)
			ui.request('nvim_input_mouse', 'right', 'press', '', 0, pos[1], pos[2])
			assert(vim.wait(3000, function() return ui.find_text(label) ~= nil end, 10), 'native follow menu shows ' .. label)
			local item = ui.find_text(label)
			assert(math.abs(item[1] - pos[1]) <= 1 and math.abs(item[2] - pos[2]) <= 2,
				'native menu opens at the mouse position: ' .. vim.inspect({ item = item, mouse = pos }))
		end
		open_menu('[ ] Follow output')
		local item = assert(ui.find_text('[ ] Follow output'))
		ui.request('nvim_input_mouse', 'left', 'press', '', 0, item[1], item[2] + 2)
		ui.request('nvim_input_mouse', 'left', 'release', '', 0, item[1], item[2] + 2)
		ui.wait([[return require('terminal.follow').is_following(source_win) and at_live_screen()]], 'menu resumes following')
		assert(ui.lua([[return vim.api.nvim_get_current_win() == focus]]), 'menu preserves focus')
		open_menu('[x] Follow output')
		ui.input('<Esc>')
		assert(vim.wait(3000, function() return ui.find_text('Follow output') == nil end, 10), 'Escape dismisses native menu')
		assert(ui.lua([[return vim.api.nvim_get_current_win() == focus and vim.api.nvim_get_mode().mode == 't']]), 'dismissal preserves focus and mode')
		open_menu('[x] Follow output')
		ui.input('<Down><CR>')
		ui.wait([[return not require('terminal.follow').is_following(source_win)]], 'menu disables following')
		ui.wait([[return vim.api.nvim_get_mode().mode == 't' and vim.b.term_mode == 't']], 'native menu action preserves Terminal mode')
		ui.lua([[vim.api.nvim_chan_send(channel, '\27[5;1Hdisabled redraw'); vim.wait(50, function() return false end)]])
		assert(ui.lua([[return not require('terminal.follow').is_following(source_win)]]), 'output does not re-enable disabled following')
		ui.request('nvim_input_mouse', 'wheel', 'up', '', 0, pos[1], pos[2])
		ui.wait([[return not at_live_screen()]], 'scroll away from bottom')
		for _ = 1, 12 do ui.request('nvim_input_mouse', 'wheel', 'down', '', 0, pos[1], pos[2]) end
		ui.wait([[return require('terminal.follow').is_following(source_win) and at_live_screen()]], 'scrolling to bottom resumes following')
		ui.lua([[
			_G.bottom_scrolls = 0
			_G.scroll_watch = vim.api.nvim_create_autocmd('WinScrolled', {
				callback = function() bottom_scrolls = bottom_scrolls + 1 end,
			})
		]])
		for _ = 1, 20 do ui.request('nvim_input_mouse', 'wheel', 'down', '', 0, pos[1], pos[2]) end
		ui.lua([[vim.wait(50, function() return false end); vim.api.nvim_del_autocmd(scroll_watch)]])
		assert(ui.lua([[return bottom_scrolls == 0 and at_live_screen()
			and vim.api.nvim_get_current_win() == focus]]), 'scrolling past bottom never moves the viewport or focus')
		ui.request('nvim_input_mouse', 'wheel', 'up', '', 0, pos[1], pos[2])
		ui.wait([[return not require('terminal.follow').is_following(source_win)]], 'scroll pauses before focus')
		ui.request('nvim_input_mouse', 'left', 'press', '', 0, pos[1], pos[2])
		ui.request('nvim_input_mouse', 'left', 'release', '', 0, pos[1], pos[2])
		ui.wait([[return vim.api.nvim_get_current_win() == source_win and vim.api.nvim_get_mode().mode == 't'
			and require('terminal.follow').is_following(source_win) and at_live_screen()]], 'focus resumes Terminal mode and live screen')
		ui.lua([[vim.api.nvim_set_current_win(focus); require('terminal.mode').restore_current()]])
		ui.wait([[return vim.api.nvim_get_mode().mode == 't']], 'return to other terminal mode')
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
