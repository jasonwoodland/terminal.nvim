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
			vim.b[source_buf].terminal_managed = true
			vim.b[source_buf].term_owner_tab = vim.api.nvim_get_current_tabpage()
			_G.channel = vim.api.nvim_open_term(source_buf, {})
			require('terminal.mouse').observe(source_buf)
		]], floating)
		ui.input('<F2>')
		ui.wait([[return vim.api.nvim_get_current_buf() == source_buf and vim.api.nvim_get_mode().mode == 't']], 'source enters Terminal mode')
		if with_winbar then
			ui.lua([[require('terminal').new(); require('terminal').go_to(1)]])
			ui.wait([[return vim.api.nvim_get_current_buf() == source_buf and vim.wo.winbar ~= ''
				and vim.api.nvim_get_mode().mode == 't']], 'second tab makes winbar visible')
		end
		ui.wait([[return vim.api.nvim_buf_line_count(source_buf) <= vim.api.nvim_win_get_height(0)
			- (vim.wo.winbar ~= '' and 1 or 0)]], 'empty terminal resize settles without scrollback')
		local empty_pos = ui.lua([[
			vim.o.mouse, vim.o.mousetime = 'a', 0
			_G.empty_leaves = 0
			_G.empty_watch = vim.api.nvim_create_autocmd('TermLeave', {
				callback = function() empty_leaves = empty_leaves + 1 end,
			})
			local p = vim.api.nvim_win_get_position(0)
			return {p[1] + 2, p[2] + 2}
		]])
		for _, mods in ipairs({ '', 'S', 'C' }) do
			ui.request('nvim_input_mouse', 'wheel', 'up', mods, 0, empty_pos[1], empty_pos[2])
		end
		ui.lua([[vim.wait(50, function() return false end); vim.api.nvim_del_autocmd(empty_watch)]])
		assert(ui.lua([[return vim.api.nvim_get_mode().mode == 't' and empty_leaves == 0
			and vim.fn.winsaveview().topline == 1
			and require('terminal.follow').is_following(vim.api.nvim_get_current_win())]]),
			'wheel-up without scrollback preserves Terminal mode and following')
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
		local pos = ui.lua([[vim.o.mouse = 'a'; vim.o.mousetime = 0
			local p = vim.api.nvim_win_get_position(source_win); return {p[1] + 2, p[2] + 2}]])
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
		ui.wait([[return not at_live_screen()]], 'inactive pane scrolls back before keyboard focus')
		ui.input('<C-S-h>')
		ui.wait([[return vim.api.nvim_get_current_win() == source_win
			and vim.api.nvim_get_mode().mode:sub(1, 1) == 'n' and not at_live_screen()]],
			'keyboard focus preserves wheel scrollback in Normal mode')
		ui.request('nvim_input_mouse', 'wheel', 'down', '', 0, pos[1], pos[2])
		ui.wait([[return vim.api.nvim_get_mode().mode == 't' and at_live_screen()]],
			'wheel down resumes Terminal mode after keyboard focus')
		ui.input('<C-S-l>')
		ui.wait([[return vim.api.nvim_get_current_win() == focus and vim.api.nvim_get_mode().mode == 't']],
			'keyboard focus returns to the other pane')
		ui.request('nvim_input_mouse', 'left', 'press', '', 0, pos[1], pos[2])
		ui.wait([[return vim.api.nvim_get_current_win() == source_win and vim.api.nvim_get_mode().mode == 't'
			and at_live_screen()]], 'pressing a following pane restores Terminal mode before release')
		ui.request('nvim_input_mouse', 'left', 'release', '', 0, pos[1], pos[2])
		ui.input('<C-S-l>')
		ui.wait([[return vim.api.nvim_get_current_win() == focus and vim.api.nvim_get_mode().mode == 't']],
			'keyboard focus returns after clicking the following pane')
		ui.request('nvim_input_mouse', 'wheel', 'up', '', 0, pos[1], pos[2])
		ui.wait([[return not at_live_screen() and not require('terminal.follow').is_following(source_win)]],
			'scroll pauses before click focus')
		ui.lua([[_G.click_top = vim.api.nvim_win_call(source_win, vim.fn.winsaveview).topline]])
		ui.request('nvim_input_mouse', 'left', 'press', '', 0, pos[1], pos[2])
		ui.request('nvim_input_mouse', 'left', 'release', '', 0, pos[1], pos[2])
		ui.wait([[return vim.api.nvim_get_current_win() == source_win
			and vim.api.nvim_get_mode().mode:sub(1, 1) == 'n'
			and vim.fn.winsaveview().topline == click_top]], 'click focus preserves wheel scrollback in Normal mode')
		ui.request('nvim_input_mouse', 'wheel', 'down', '', 0, pos[1], pos[2])
		ui.wait([[return vim.api.nvim_get_mode().mode == 't' and at_live_screen()]],
			'wheel down resumes Terminal mode after click focus')
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
		ui.request('nvim_input_mouse', 'left', 'press', '', 0, pos[1], pos[2])
		ui.request('nvim_input_mouse', 'left', 'release', '', 0, pos[1], pos[2])
		ui.wait([[return vim.api.nvim_get_current_win() == source_win
			and vim.api.nvim_get_mode().mode:sub(1, 1) == 'n' and not at_live_screen()]],
			'clicking a pane left in Normal mode preserves scrollback')
		ui.lua([[require('terminal.mode').restore(source_win, 't')]])
		ui.wait([[return vim.api.nvim_get_mode().mode == 't' and at_live_screen()]], 'focus source at live screen')
		ui.lua([[vim.o.mousescroll = 'ver:1,hor:0']])
		for _, start_mode in ipairs({ 't', 'n' }) do
			if start_mode == 'n' then
				ui.lua([[require('terminal.follow').set_following(source_win, true)]])
				ui.input('<C-\\><C-n>')
				ui.wait([[return vim.api.nvim_get_mode().mode:sub(1, 1) == 'n'
					and not require('terminal.follow').is_following(source_win)]],
					'leaving Terminal mode explicitly stops following')
			end
			ui.lua([[
				_G.bottom_events = 0
				_G.bottom_watch = vim.api.nvim_create_autocmd({'WinScrolled', 'TermLeave'}, {
					callback = function() bottom_events = bottom_events + 1 end,
				})
			]])
			for _, mods in ipairs({ '', 'S', 'C' }) do
				ui.request('nvim_input_mouse', 'wheel', 'down', mods, 0, pos[1], pos[2])
			end
			if start_mode == 't' then
				ui.request('nvim_input_mouse', 'wheel', 'left', '', 0, pos[1], pos[2])
				ui.request('nvim_input_mouse', 'wheel', 'right', '', 0, pos[1], pos[2])
			end
			ui.lua([[vim.wait(50, function() return false end); vim.api.nvim_del_autocmd(bottom_watch)]])
			assert(ui.lua([[return bottom_events == 0 and at_live_screen()
				and vim.api.nvim_get_mode().mode:sub(1, 1) == ...]], start_mode),
				'focused wheel at the bottom preserves the viewport and mode')
			ui.request('nvim_input_mouse', 'wheel', 'up', '', 0, pos[1], pos[2])
			ui.wait([[return vim.api.nvim_get_mode().mode:sub(1, 1) == 'n' and not at_live_screen()]],
				'focused wheel scrolls into scrollback')
			for _ = 1, 12 do ui.request('nvim_input_mouse', 'wheel', 'down', '', 0, pos[1], pos[2]) end
			ui.wait([[return at_live_screen()]], 'focused wheel returns to live screen')
			ui.wait("return vim.api.nvim_get_mode().mode:sub(1, 1) == " .. vim.inspect(start_mode),
				'focused wheel preserves the mode from before scrolling')
			assert(ui.lua([[return require('terminal.follow').is_following(source_win) == (... == 't')]], start_mode),
				'focused wheel at the bottom follows only after restoring Terminal mode')
		end
		ui.lua([[
			_G.bottom_view = vim.fn.winsaveview().topline
			_G.line_count = vim.api.nvim_buf_line_count(source_buf)
			vim.api.nvim_chan_send(channel, '\27[999;1H\r\noutput after scrolling to the bottom')
		]])
		ui.wait([[return vim.api.nvim_buf_line_count(source_buf) > line_count]], 'new output arrives after wheel-down')
		assert(ui.lua([[return vim.fn.winsaveview().topline == bottom_view]]),
			'wheel-down in explicit Normal mode keeps the viewport still as output arrives')
		ui.request('nvim_input_mouse', 'wheel', 'up', '', 0, pos[1], pos[2])
		ui.wait([[return not at_live_screen()]], 'scroll back in the active pane before opening its menu')
		open_menu('Enter terminal mode')
		assert(ui.find_text('Follow output') == nil, 'active pane menu offers Terminal mode')
		ui.input('<Down><CR>')
		ui.wait([[return vim.api.nvim_get_current_win() == source_win and vim.api.nvim_get_mode().mode == 't'
			and at_live_screen()]], 'menu returns the active pane to Terminal mode and live output')
		for _, normal_key in ipairs({ '<C-\\><C-n>', '<C-S-\\>' }) do
			ui.lua([[vim.api.nvim_chan_send(channel, '\27[999;1Hlast row')]])
			ui.wait([[return vim.api.nvim_win_get_cursor(source_win)[1] == vim.api.nvim_buf_line_count(source_buf)]],
				'terminal cursor reaches the last buffer line')
			ui.lua([[_G.bottom_view = vim.fn.winsaveview().topline; _G.line_count = vim.api.nvim_buf_line_count(source_buf)]])
			ui.input(normal_key)
			ui.wait([[return vim.api.nvim_get_mode().mode:sub(1, 1) == 'n'
				and not require('terminal.follow').is_following(source_win)]], 'explicit Normal mode pauses following')
			ui.input('ggG')
			ui.wait([[return vim.api.nvim_win_get_cursor(source_win)[1] == line_count]],
				'G moves the Normal-mode cursor to the last buffer line')
			ui.lua([[vim.api.nvim_chan_send(channel, '\r\nnew output\r\nmore output')]])
			ui.wait([[return vim.api.nvim_buf_line_count(source_buf) > line_count]], 'new output adds scrollback')
			ui.wait([[return vim.fn.winsaveview().topline == bottom_view
				and vim.api.nvim_win_get_cursor(source_win)[1] == line_count]],
				'G preserves the Normal-mode viewport and cursor as output arrives')
			ui.input('i')
			ui.wait([[return vim.api.nvim_get_mode().mode == 't']], 'resume Terminal mode')
		end
		ui.input('<C-\\><C-n>')
		ui.wait([[return vim.api.nvim_get_mode().mode:sub(1, 1) == 'n'
			and not require('terminal.follow').is_following(source_win)]], 'explicit Normal mode clears following')
		ui.input('<C-S-l>')
		ui.wait([[return vim.api.nvim_get_current_win() == focus]], 'leave the Normal-mode pane inactive')
		for _, opted_in in ipairs({ false, true }) do
			if opted_in then
				open_menu('[ ] Follow output')
				ui.input('<Down><CR>')
				ui.wait([[return require('terminal.follow').is_following(source_win)]], 'explicitly enable following')
			end
			ui.request('nvim_input_mouse', 'wheel', 'up', '', 0, pos[1], pos[2])
			ui.wait([[return not at_live_screen()]], 'scroll back in the inactive Normal-mode pane')
			ui.request('nvim_input_mouse', 'wheel', 'down', '', 0, pos[1], pos[2])
			ui.wait([[return at_live_screen()]], 'return inactive Normal-mode pane to the bottom')
			for _ = 1, 4 do ui.request('nvim_input_mouse', 'wheel', 'down', '', 0, pos[1], pos[2]) end
			assert(ui.lua([[return require('terminal.follow').is_following(source_win) == ...
				and vim.b[source_buf].term_mode == 'n' and vim.api.nvim_get_current_win() == focus]], opted_in),
				'inactive Normal-mode pane follows only after explicit opt-in')
		end
	end, debug.traceback)
	ui.close()
	assert(ok, err)
end
print('Terminal output following regressions passed')
