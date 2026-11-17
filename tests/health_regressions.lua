local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.runtimepath:prepend(root)
local ui = require("tests.helpers.ui").start(root, 120, 50)
local ok, err = pcall(function()
	ui.lua([[
		terminal = require('terminal')
		state = require('terminal.state')
		terminal.setup({keys=false})
		local editor = vim.api.nvim_get_current_win()
		one = terminal.new()
		vim.api.nvim_win_close(editor,true)
		assert(terminal.toggle({open=false}) and not state.is_term_open())
		assert(vim.api.nvim_get_current_buf() ~= one and state.is_managed(one), 'last ordinary pane retires into an editor window')
		assert(terminal.toggle({open=true}))
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if not state.is_managed(vim.api.nvim_win_get_buf(win)) and vim.api.nvim_win_get_config(win).relative == '' then
				vim.api.nvim_win_close(win,true)
			end
		end
		assert(terminal.toggle() and not state.is_term_open(), 'normal toggle also closes the sole drawer')
		assert(terminal.toggle({open=true}))
		two = terminal.vsplit()
		local job = vim.b[two].terminal_job_id
		terminal.toggle({open=false})
		vim.fn.jobstop(job)
	]])
	ui.wait("return not vim.api.nvim_buf_is_valid(two) and vim.t.term_bufnr == one", "hidden exit updates remembered pane")
	ui.lua([[
		assert(state.get_current_tab().focus == one and terminal.send('echo alive\n') and not state.is_term_open())
		source = vim.api.nvim_get_current_tabpage()
		vim.cmd('tabnew')
		vim.cmd('terminal')
		ordinary = vim.api.nvim_get_current_buf()
		ordinary_job = vim.b[ordinary].terminal_job_id
		owned = terminal.new()
		owned_job = vim.b[owned].terminal_job_id
		hidden_owned = terminal.new()
		hidden_job = vim.b[hidden_owned].terminal_job_id
		vim.cmd('tabclose!')
	]])
	ui.wait("return vim.b[owned].term_owner_tab == source and vim.b[hidden_owned].term_owner_tab == source", "closed Vim tab transfers visible and hidden owned jobs")
	ui.lua([[
		assert(vim.fn.jobwait({owned_job,hidden_job},0)[1] == -1 and vim.fn.jobwait({owned_job,hidden_job},0)[2] == -1)
		assert(not state.is_term_open() and state.get_current_tab().bufs[1] == one, 'adoption preserves hidden destination and selection')
		local tabs = state.get_tabs()
		assert(#tabs == 3 and tabs[2].bufs[1] == owned and tabs[3].bufs[1] == hidden_owned, 'terminal tabs append in order')
		assert(vim.api.nvim_buf_is_valid(ordinary) and vim.fn.jobwait({ordinary_job},0)[1] == -1, 'ordinary jobs remain untouched')
		assert(terminal.delete(owned) and terminal.delete(hidden_owned))
		vim.api.nvim_buf_delete(ordinary,{force=true})
		terminal.toggle({open=true})
		two = terminal.hsplit()
		vim.cmd('tabnew')
		destination = vim.api.nvim_get_current_tabpage()
		dest_buf = terminal.new()
		vim.api.nvim_set_current_tabpage(source)
	]])
	ui.input("<C-\\><C-n>")
	ui.wait("return vim.fn.mode() == 'n'", "source normal mode ready")
	ui.lua([[
		local source_id = state.get_current_tab().id
		local destination_id = state.get_tabs(destination)[1].id
		local group = vim.api.nvim_create_augroup('TransferResizeRegression',{clear=true})
		vim.api.nvim_create_autocmd('TabEnter',{group=group,callback=function()
			if vim.api.nvim_get_current_tabpage() == destination then vim.t.term_height = 1 end
		end})
		local result, reason = terminal.move_to_vim_tab(1)
		vim.api.nvim_del_augroup_by_id(group)
		assert(result == false and type(reason) == 'string')
		assert(vim.api.nvim_get_current_tabpage() == source and vim.api.nvim_get_current_buf() == two)
		assert(state.get_current_tab().id == source_id and #state.get_tabs() == 1 and #state.get_tabs()[1].bufs == 2)
		assert(state.get_tabs(destination)[1].id == destination_id and #state.get_tabs(destination) == 1)
		assert(vim.b[one].term_owner_tab == source and vim.b[two].term_owner_tab == source)
		assert(state.is_term_open() and #vim.t[destination].term_winids == 1, 'both original views are restored')
		local window, notify = require('terminal.window'), vim.notify
		local open = window.open_tab_windows
		local notices = {}
		vim.notify = function(message) notices[#notices+1] = message end
		for _, command in ipairs({'TermNew','TermSplit','TermVsplit'}) do
			local calls = 0
			window.open_tab_windows = function(...)
				calls = calls + 1
				if calls == 1 then return false end
				return open(...)
			end
			vim.cmd(command)
		end
		window.open_tab_windows, vim.notify = open, notify
		assert(#notices == 3 and #terminal.list() == 3, 'launch commands report failures and leave no provisional jobs')
	]])
end)
ui.close()
assert(ok, err)
print("Repository health regressions passed")
