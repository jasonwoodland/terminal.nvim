local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.runtimepath:prepend(root)
local ui = require("tests.helpers.ui").start(root, 120, 50)
local ok, err = pcall(function()
	ui.lua([[
		terminal = require('terminal')
		state = require('terminal.state')
		window = require('terminal.window')
		terminal.setup({keys=false, height=20, float_zoom_hide_cmdline=true, float={padding={x=3,y=3}}})
		function failed(action, ...)
			local ok, reason = action(...)
			assert(ok == false and type(reason) == 'string')
		end
		for _, opts in ipairs({false, true, 'open', {open=1}, {open='true'}, {height=20}}) do failed(terminal.toggle, opts) end
		assert(not state.is_term_open() and #terminal.list() == 0)
		failed(terminal.equalize)
		assert(terminal.toggle({open=false}))
		local termopen, count = vim.fn.termopen, #vim.api.nvim_list_bufs()
		vim.fn.termopen = function() error('injected display startup failure') end
		for _, action in ipairs({terminal.toggle, terminal.zoom, terminal.float_toggle}) do
			failed(action)
			assert(not state.is_term_open() and #terminal.list() == 0 and not vim.t.term_zoom and vim.t.term_float_enabled == nil)
			assert(#vim.api.nvim_list_bufs() == count, 'failed display startup cleans up temporary buffers')
		end
		vim.fn.termopen = termopen
		assert(terminal.toggle({open=true}))
		assert(terminal.equalize(), 'single-pane equalize succeeds as a no-op')
		one = vim.api.nvim_get_current_buf()
		local wins = vim.deepcopy(vim.t.term_winids)
		assert(terminal.toggle({open=true}) and vim.deep_equal(wins, vim.t.term_winids), 'already open succeeds without rebuilding')
		assert(terminal.zoom() and vim.t.term_zoom and vim.o.cmdheight == 0)
		local can_open, notify = window.can_open_tab, vim.notify
		vim.notify = function() end
		window.can_open_tab = function() return false end
		failed(terminal.zoom)
		assert(vim.t.term_zoom and vim.o.cmdheight == 0, 'failed unzoom retains zoom state')
		failed(terminal.float_toggle)
		assert(vim.t.term_zoom and vim.t.term_float_enabled == nil, 'failed float change retains base mode')
		window.can_open_tab = can_open
		assert(terminal.float_toggle() and vim.t.term_float_enabled and not vim.t.term_zoom)
		assert(terminal.float_toggle() and not vim.t.term_float_enabled)
		terminal.config.float_zoom = false
		local height = state.drawer_span()
		assert(terminal.zoom() and vim.t.term_prev_height ~= nil)
		assert(terminal.zoom() and vim.t.term_prev_height == nil and state.drawer_span() == height)
		terminal.config.float_zoom = true
		assert(terminal.toggle({open=false}) and not state.is_term_open())
		assert(terminal.equalize() and not state.is_term_open(), 'hidden equalize succeeds without opening')
		assert(terminal.toggle({open=false}))
		window.can_open_tab = function() return false end
		failed(terminal.toggle, {open=true})
		assert(not state.is_term_open())
		window.can_open_tab = can_open
		assert(terminal.zoom() and state.is_term_open() and vim.t.term_zoom, 'zoom opens a hidden workspace')
		assert(terminal.zoom() and not vim.t.term_zoom)
		state.set_last_notification_bufnr(nil)
		failed(terminal.go_to_notification)
		terminal.new()
		state.set_last_notification_bufnr(one)
		assert(terminal.go_to_notification() and vim.api.nvim_get_current_buf() == one)
		assert(terminal.toggle({open=false}))
		assert(terminal.go_to_notification() and state.is_term_open() and vim.api.nvim_get_current_buf() == one)
		local current = vim.api.nvim_get_current_buf()
		local ordinary = vim.api.nvim_create_buf(false, true)
		state.set_last_notification_bufnr(ordinary)
		failed(terminal.go_to_notification)
		assert(vim.api.nvim_get_current_buf() == current)
		vim.api.nvim_buf_delete(ordinary, {force=true})
		failed(terminal.go_to_notification)
		vim.notify = notify
		assert(vim.v.errmsg == '', vim.v.errmsg)
	]])
end)
ui.close()
assert(ok, err)
print("Display and notification API passed")
