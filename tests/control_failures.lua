local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.runtimepath:prepend(root)
local ui = require("tests.helpers.ui").start(root, 120, 50)
local ok, err = pcall(function()
	ui.lua([[
		terminal = require('terminal')
		state = require('terminal.state')
		window = require('terminal.window')
		terminal.setup({keys=false})
		local initial_open = window.open_tab_windows
		window.open_tab_windows = function() return false end
		local started, start_reason = terminal.toggle({open=true})
		window.open_tab_windows = initial_open
		assert(started == false and type(start_reason) == 'string' and #terminal.list() == 0,
			'failed first view does not leave a provisional terminal job')
		one = terminal.new({name='keep'})
		two = terminal.vsplit()
		local title = state.get_title
		state.get_title = function() error('lookup must not enumerate titles') end
		local target = state.find_pane(one)
		assert(target and target.tabpage == vim.api.nvim_get_current_tabpage() and target.pane_index == 1)
		state.get_title = title
		for _, value in ipairs({false, {}, -1, 0, 999999}) do assert(not state.find_pane(value)) end
		local function unchanged(before, buf, reason)
			assert(vim.deep_equal(before, state.get_tabs()), reason .. vim.inspect({before, state.get_tabs()}))
			assert(vim.api.nvim_buf_is_valid(buf) and vim.fn.jobwait({vim.b[buf].terminal_job_id},0)[1] == -1)
			assert(state.is_term_open() and vim.api.nvim_get_current_buf() == buf)
		end
		require('terminal.mode').record()
		window.save_tab_state()
		local before = state.get_tabs()
		local panes = require('terminal.panes')
		for _, failure in ipairs({'error', 'false'}) do
			local reopen, attempts = window.reopen_current_tab, 0
			local notify = vim.notify
			local reported
			vim.notify = function(message) reported = message end
			window.reopen_current_tab = function(...)
				attempts = attempts + 1
				if attempts == 1 then
					if failure == 'error' then error('Vim:E36: Not enough room') end
					return false
				end
				return reopen(...)
			end
			panes.splitmove('bottom')
			window.reopen_current_tab, vim.notify = reopen, notify
			assert(reported and attempts == 2, 'failed structural move reports and restores the drawer')
			unchanged(before, two, 'failed structural move restores old layout and focus')
			assert(terminal.toggle({open=false}) ~= false)
			assert(terminal.toggle({open=true}) ~= false)
			unchanged(before, two, 'drawer can still toggle after a failed structural move')
		end
		local set_buf, notify = vim.api.nvim_win_set_buf, vim.notify
		local failed_attachment = false
		vim.notify = function() end
		vim.api.nvim_win_set_buf = function(win, buf)
			if not failed_attachment and (buf == one or buf == two) then
				failed_attachment = true
				error('Vim:E36: Not enough room')
			end
			return set_buf(win, buf)
		end
		local eventignore = vim.o.eventignore
		panes.splitmove('bottom')
		vim.api.nvim_win_set_buf, vim.notify = set_buf, notify
		assert(failed_attachment and vim.o.eventignore == eventignore)
		unchanged(before, two, 'partial window construction is cleaned up before rollback')
		local open, calls = window.open_tab_windows, 0
		window.open_tab_windows = function(...)
			calls = calls + 1
			if calls == 1 then return false end
			return open(...)
		end
		local result, reason = terminal.new()
		window.open_tab_windows = open
		assert(result == false and type(reason) == 'string')
		unchanged(before, two, 'failed new view restores old jobs and layout')
		local reopen = window.reopen_current_tab
		calls = 0
		window.reopen_current_tab = function(...)
			calls = calls + 1
			if calls == 1 then return false end
			return reopen(...)
		end
		result, reason = terminal.hsplit()
		window.reopen_current_tab = reopen
		assert(result == false and type(reason) == 'string')
		unchanged(before, two, 'failed split view restores old jobs and layout')
		local swap, rebuild = window.swap_tab_buffers, window.rebuild_tab
		window.swap_tab_buffers = function() return false end
		calls = 0
		window.rebuild_tab = function(...)
			calls = calls + 1
			if calls == 1 then return false end
			return rebuild(...)
		end
		result, reason = terminal.reset()
		window.swap_tab_buffers, window.rebuild_tab = swap, rebuild
		assert(result == false and type(reason) == 'string')
		unchanged(before, two, 'failed replacement view keeps the original job')
		assert(#terminal.list() == 2, 'provisional terminal jobs are removed on failure')
		window.swap_tab_buffers = function() return false end
		window.rebuild_tab = function() return false end
		result, reason = terminal.reset()
		window.swap_tab_buffers, window.rebuild_tab = swap, rebuild
		assert(result == false and reason:find('could not restore terminal workspace',1,true), 'recovery failure is included in the error')
		assert(vim.api.nvim_buf_is_valid(two) and #terminal.list() == 2)
		assert(window.rebuild_tab())
		local layout = require('terminal.float_layout')
		local apply = layout.apply_layout
		layout.apply_layout = function() return false end
		result, reason = terminal.equalize()
		layout.apply_layout = apply
		assert(result == false and type(reason) == 'string', 'equalize reports a rejected layout update')
		local other = terminal.new()
		local switch = window.switch_to_tab
		window.switch_to_tab = function() return false end
		result, reason = terminal.focus(one)
		window.switch_to_tab = switch
		assert(result == false and vim.api.nvim_get_current_buf() == other, 'focus reports a rejected tab switch')
		reopen = window.reopen_current_tab
		window.reopen_current_tab = function() return false end
		result, reason = terminal.delete(other)
		window.reopen_current_tab = reopen
		assert(result == false and reason:find('was deleted',1,true), 'delete reports failure to reopen remaining workspace')
		assert(not vim.api.nvim_buf_is_valid(other) and window.rebuild_tab())
		assert(vim.v.errmsg == '', vim.v.errmsg)
	]])
end)
ui.close()
assert(ok, err)
print("Control failure propagation and recovery passed")
