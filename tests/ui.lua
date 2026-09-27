-- Usage: nvim --clean --headless -l tests/ui.lua
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
local ui = dofile(root .. "/tests/helpers/ui.lua").start(root)
local ok, err = xpcall(function()
	ui.lua([[require('terminal').setup({ set_buffer_name = false,
		float = { padding = { x = 3, y = 2 } }, keys = {
			toggle = '<F2>', new = '<F3>', prev = '<F4>', next = '<F5>',
			float_toggle = '<F8>', vsplit = '<F9>', pane_left = '<F10>', pane_right = '<F11>',
		} })
		vim.o.mouse = 'a'
	]])
	ui.input('<F2>')
	ui.wait([[return require('terminal.state').is_term_open() and vim.api.nvim_get_mode().mode == 't']], 'drawer opens in Terminal mode')
	ui.input('<F2>')
	ui.wait([[return not require('terminal.state').is_term_open() and vim.api.nvim_get_mode().mode == 'n']], 'toggle returns to editor')
	ui.input('<F2>')
	ui.wait([[return require('terminal.state').is_term_open() and vim.api.nvim_get_mode().mode == 't']], 'toggle restores Terminal mode')
	ui.input('<C-\\><C-n>')
	ui.wait([[return vim.api.nvim_get_mode().mode == 'nt']], 'leave Terminal mode')
	ui.input('<F2>')
	ui.wait([[return not require('terminal.state').is_term_open()]], 'hide normal-mode terminal')
	ui.input('<F2>')
	ui.wait([[return require('terminal.state').is_term_open() and vim.api.nvim_get_mode().mode == 'nt']], 'toggle restores Normal mode')
	ui.input('<F3>')
	ui.wait([[return vim.t.term_tab_idx == 2 and vim.api.nvim_get_mode().mode == 't']], 'new tab enters Terminal mode')
	ui.input('<F4>')
	ui.wait([[return vim.t.term_tab_idx == 1 and vim.api.nvim_get_mode().mode == 'nt']], 'previous tab restores Normal mode')
	ui.input('<F5>')
	ui.wait([[return vim.t.term_tab_idx == 2 and vim.api.nvim_get_mode().mode == 't']], 'next tab restores Terminal mode')
	ui.input('<F8>')
	ui.wait([[return require('terminal.config').is_float_mode() and vim.api.nvim_get_mode().mode == 't']], 'float toggle keeps Terminal mode')
	ui.input('<F9>')
	ui.wait([[return #vim.t.term_winids == 2 and vim.api.nvim_get_mode().mode == 't']], 'split enters Terminal mode')
	ui.wait([[return not vim.t.term_toggling]], 'structural transition finished')
	ui.lua([[
		_G.mouse_events = {}
		local layout = require('terminal.float_layout')
		for _, name in ipairs({ 'on_left_mouse', 'on_left_drag', 'on_left_release' }) do
			local callback = layout[name]
			layout[name] = function(mouse)
				table.insert(_G.mouse_events, {name, mouse})
				return callback(mouse)
			end
		end
	]])
	local drag = ui.lua([[
		local layout = require('terminal.state').get_current_tab().layout
		local _, separators = require('terminal.frame').rects(layout)
		local row, col = require('terminal.float_layout').content_origin(require('terminal.window').get_float_win_config())
		return { row + separators[1].row + 2, col + separators[1].col,
			vim.api.nvim_win_get_width(vim.t.term_winids[1]) }
	]])
	ui.request('nvim_input_mouse', 'left', 'press', '', 0, drag[1], drag[2])
	ui.wait([[return #_G.mouse_events >= 1]], 'mouse press processed')
	ui.request('nvim_input_mouse', 'left', 'drag', '', 0, drag[1], drag[2] + 3)
	ui.wait([[return #_G.mouse_events >= 2]], 'mouse drag processed')
	ui.request('nvim_input_mouse', 'left', 'release', '', 0, drag[1], drag[2] + 3)
	ui.wait(('return vim.api.nvim_win_get_width(vim.t.term_winids[1]) == %d'):format(drag[3] + 3), 'RPC mouse drag resizes separator')
	ui.wait([[return vim.api.nvim_get_mode().mode == 't']], 'drag preserves Terminal mode')
	-- Winbar click travels through actual mouse input and restores the target's mode.
	local bar = ui.lua([[return vim.api.nvim_win_get_position(vim.t.term_winbar_winid)]])
	ui.request('nvim_input_mouse', 'left', 'press', '', 0, bar[1], bar[2] + 1)
	ui.wait([[return vim.t.term_tab_idx == 1]], 'winbar press processed')
	ui.request('nvim_input_mouse', 'left', 'release', '', 0, bar[1], bar[2] + 1)
	ui.wait([[return vim.t.term_tab_idx == 1 and vim.api.nvim_get_mode().mode == 'nt']], 'winbar click switches tab and restores mode')
	assert(ui.redraws > 0, 'attached UI consumed redraw notifications')
	assert(ui.lua('return vim.v.errmsg') == '', 'no asynchronous UI errors')
end, debug.traceback)
if not ok then print(vim.inspect(ui.lua([[return { events = _G.mouse_events, mode = vim.fn.mode(), widths = vim.tbl_map(vim.api.nvim_win_get_width, vim.t.term_winids or {}), errmsg = vim.v.errmsg }]]))) end
ui.close()
assert(ok, err)
print('Attached-UI mode and mouse regressions passed')
