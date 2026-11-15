-- Optional real-Telescope RPC UI regression. Set TELESCOPE_PATH/PLENARY_PATH
-- when dependencies are not installed under stdpath('data')/lazy.
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.runtimepath:prepend(root)
local telescope = vim.env.TELESCOPE_PATH or (vim.fn.stdpath("data") .. "/lazy/telescope.nvim")
local plenary = vim.env.PLENARY_PATH or (vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
if vim.fn.isdirectory(telescope) == 0 or vim.fn.isdirectory(plenary) == 0 then
	print("SKIP Telescope integration: install telescope.nvim and plenary.nvim")
	return
end
local ui = require("tests.helpers.ui").start(root, 120, 42)
local ok, err = pcall(function()
	ui.lua([[
		local telescope, plenary = ...
		vim.opt.runtimepath:append(telescope)
		vim.opt.runtimepath:append(plenary)
		vim.cmd('runtime plugin/telescope.lua')
		require('telescope').setup({ defaults = { initial_mode = 'normal' } })
		vim.api.nvim_create_autocmd('User', {
			pattern = 'TelescopePreviewerLoaded',
			callback = function()
				vim.wo.number = true
				vim.wo.signcolumn = 'yes'
			end,
		})
		require('telescope').load_extension('terminal')
		terminal = require('terminal')
		terminal.setup({ keys = false, set_buffer_name = false })
		terminal.toggle()
		original = vim.api.nvim_get_current_buf()
	]], telescope, plenary)
	ui.wait("return vim.api.nvim_get_mode().mode == 't'", "terminal enters input mode")
	ui.input("<C-\\><C-n>")
	ui.lua("terminal.new(); terminal.vsplit(); target = vim.api.nvim_get_current_buf(); owner = vim.api.nvim_get_current_tabpage()")
	ui.wait("return vim.api.nvim_get_mode().mode == 't'", "new pane enters input mode")
	ui.input("<C-\\><C-n>")
	ui.lua([[vim.api.nvim_chan_send(vim.b[target].terminal_job_id, 'i=0; while [ "$i" -lt 120 ]; do echo "$i"; i=$((i+1)); done\n')]])
	ui.wait("return vim.api.nvim_buf_line_count(target) > 100", "terminal has scrollback")
	ui.lua([[
		vim.b[target].term_mode = 'n'
		vim.wo.scrolloff = 0
		vim.api.nvim_win_set_cursor(0, { 80, 0 })
		vim.fn.winrestview({ topline = 80, lnum = 80, col = 0 })
		expected_top = vim.fn.winsaveview().topline
		source_height = vim.api.nvim_win_get_height(0)
		assert(expected_top == 80)
		terminal.go_to(1)
		terminal.toggle()
		vim.cmd('tabnew')
		editor = vim.api.nvim_get_current_buf()
		editor_win = vim.api.nvim_get_current_win()
		vim.cmd('Telescope terminal terminals')
	]])
	ui.wait("return vim.bo.filetype == 'TelescopePrompt'", "extension opens picker")
	ui.wait([[
		local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
		return picker.manager and picker.manager:num_results() == 3
	]], "picker has results")
	-- Filter through real input so a pending finder refresh cannot reset a
	-- programmatically selected row while asynchronous previews are loading.
	ui.input('i1:2:2')
	ui.wait("return require('telescope.actions.state').get_selected_entry().value.bufnr == target", "target selected")
	ui.wait([[
		local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
		local state = picker.previewer.state
		if not state or not state.winid or not vim.api.nvim_win_is_valid(state.winid) then return false end
		local wo = vim.wo[state.winid]
		return vim.api.nvim_win_get_buf(state.winid) == state.bufnr
			and vim.fn.getwininfo(state.winid)[1].topline == expected_top
			and vim.api.nvim_win_get_height(state.winid) ~= source_height
			and not wo.number and not wo.relativenumber and wo.signcolumn == 'no'
			and wo.foldcolumn == '0' and wo.statuscolumn == ''
	]], "hidden preview uses the source topline without gutters despite file-preview hooks")
	assert(ui.lua("return require('telescope.actions.state').get_selected_entry().value.bufnr == target"), "preview preserves picker selection")
	ui.lua([[vim.api.nvim_chan_send(vim.b[target].terminal_job_id, 'printf "\\114\\111\\126\\105\\137\\120\\122\\105\\126\\111\\105\\127\\137\\117\\116\\105\\n"\n')]])
	ui.wait([[
		local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
		local state = picker.previewer.state
		return table.concat(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false), '\n'):find('LIVE_PREVIEW_ONE', 1, true) ~= nil
			and vim.fn.getwininfo(state.winid)[1].topline == expected_top
	]], "hidden terminal output updates in place without moving paused scrollback")
	ui.input("<CR>")
	ui.wait([[
		return vim.api.nvim_get_current_tabpage() == owner and vim.t.term_tab_idx == 2
			and vim.api.nvim_get_current_buf() == target and vim.api.nvim_get_current_win() == vim.t.term_winids[2]
	]], "picker navigates to the correct Vim tab, terminal tab and pane")
	assert(ui.lua("return vim.api.nvim_win_get_buf(editor_win) == editor"), "picker leaves editor buffer intact")
	ui.wait("return vim.api.nvim_get_mode().mode == 'nt'", "selection restores Normal mode")
	-- The command wrapper uses the same integration; cancellation stays put.
	ui.input("<C-\\><C-n>")
	ui.lua([[
		vim.api.nvim_win_set_cursor(0, { 45, 0 })
		vim.fn.winrestview({ topline = 45, lnum = 45, col = 0 })
		visible_top = vim.fn.winsaveview().topline
		vim.cmd('TermSelect')
	]])
	ui.wait("return vim.bo.filetype == 'TelescopePrompt'", "TermSelect opens picker")
	ui.input('i1:2:2')
	ui.wait("return require('telescope.actions.state').get_selected_entry().value.bufnr == target", "select visible pane")
	ui.wait([[
		local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
		local state = picker.previewer.state
		return state and state.winid and vim.api.nvim_win_is_valid(state.winid)
			and vim.fn.getwininfo(state.winid)[1].topline == visible_top
	]], "visible pane preview matches current viewport instead of saved position")
	ui.input('<C-u>')
	ui.wait([[
		local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
		return vim.fn.getwininfo(picker.previewer.state.winid)[1].topline < visible_top
	]], "preview can scroll independently")
	ui.lua([[
		local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
		manual_top = vim.fn.getwininfo(picker.previewer.state.winid)[1].topline
		vim.api.nvim_chan_send(vim.b[target].terminal_job_id, 'printf "\\114\\111\\126\\105\\137\\120\\122\\105\\126\\111\\105\\127\\137\\124\\127\\117\\n"\n')
	]])
	ui.wait([[
		local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
		local state = picker.previewer.state
		return table.concat(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false), '\n'):find('LIVE_PREVIEW_TWO', 1, true) ~= nil
			and vim.fn.getwininfo(state.winid)[1].topline == manual_top
	]], "live refresh preserves manually scrolled preview")
	ui.input("<C-c>")
	ui.wait("return vim.bo.filetype ~= 'TelescopePrompt'", "cancel closes picker")
	assert(ui.lua("return vim.api.nvim_get_current_buf() == target"), "cancel retains pane focus")
	ui.lua([[
		vim.cmd('TermSelect')
	]])
	ui.wait([[
		if vim.bo.filetype ~= 'TelescopePrompt' then return false end
		local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
		return picker.manager and picker.manager:num_results() == 3
	]], "split selection picker ready")
	ui.lua([[
		local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
		for i = 1, picker.manager:num_results() do
			if picker.manager:get_entry(i).value.bufnr == original then picker:set_selection(picker:get_row(i)); break end
		end
	]])
	ui.input('<C-v>')
	ui.wait([[
		return vim.api.nvim_get_current_buf() == original and vim.t.term_tab_idx == 1
			and #vim.t.term_winids == 1
	]], "split shortcut navigates instead of making an editor split")
	assert(ui.lua("return vim.api.nvim_win_get_buf(editor_win) == editor"), "split shortcut leaves editor intact")
	assert(ui.lua("return vim.v.errmsg") == '', "no asynchronous Telescope errors")
end)
if not ok then
	print(vim.inspect(ui.lua([[return {
		buf = vim.api.nvim_get_current_buf(), target = target,
		tab = vim.api.nvim_get_current_tabpage(), owner = owner,
		idx = vim.t.term_tab_idx, wins = vim.t.term_winids,
		mode = vim.api.nvim_get_mode().mode, errmsg = vim.v.errmsg,
		selection = (function()
			local e = require('telescope.actions.state').get_selected_entry()
			return e and e.value
		end)(),
	}]])))
end
ui.close()
assert(ok, err)
print("Telescope workspace navigation passed")
