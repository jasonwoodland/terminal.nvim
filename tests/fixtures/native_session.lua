local root, path, directory = vim.env.TERMINAL_SESSION_ROOT, vim.env.TERMINAL_SESSION_FILE, vim.env.TERMINAL_SESSION_CWD
vim.opt.runtimepath:prepend(root)
vim.env.SHELL, vim.o.shell = "/bin/sh", "/bin/sh"
local terminal = require("terminal")
local state = require("terminal.state")
terminal.setup({ keys = false, set_buffer_name = false, float = { padding = { x = 2, y = 2 } } })
local function settle() vim.wait(150, function() return false end) end
local one, two = directory .. "/one.txt", directory .. "/two.txt"
if vim.env.TERMINAL_SESSION_PHASE == "write" then
	vim.fn.writefile({ "one", "two", "three" }, one)
	vim.fn.writefile({ "alpha", "beta", "gamma" }, two)
	vim.cmd.edit(one)
	terminal.new({ name = "Frontend",
		cmd = { "python3", "-c", "import sys; print('hello|world'); sys.stdin.readline()" },
		env = { SESSION_QUOTING = "line one\nline two | ' \" \\" },
	})
	local tests = terminal.vsplit({ name = "Tests" })
	terminal.hsplit({ name = "Logs" })
	terminal.new({ name = "Database" })
	assert(terminal.focus(tests))
	terminal.float_toggle()
	assert(terminal.resize({ width = "80%", height = "75%" }))
	terminal.zoom()
	terminal.toggle({ open = false })
	vim.cmd("tabnew")
	vim.cmd.edit(two)
	local editor = vim.api.nvim_get_current_win()
	terminal.new({ name = "Shell" })
	assert(terminal.resize({ height = "50%" }))
	vim.api.nvim_set_current_win(editor)
	vim.api.nvim_win_set_cursor(editor, { 2, 0 })
	vim.cmd("tabnew")
	vim.cmd("terminal")
	local ordinary = vim.api.nvim_get_current_buf()
	assert(not state.is_managed(ordinary))
	vim.cmd("tabprevious")
	local tab = vim.api.nvim_get_current_tabpage()
	local names = {}
	for _, item in ipairs(terminal.list()) do names[#names + 1] = vim.api.nvim_buf_get_name(item.bufnr) end
	vim.cmd("mksession! " .. vim.fn.fnameescape(path))
	assert(vim.api.nvim_get_current_tabpage() == tab and vim.api.nvim_get_current_win() == editor,
		"session writing preserves editor focus")
	assert(#terminal.list() == 5 and #vim.api.nvim_list_tabpages() == 3 and state.is_term_open(),
		"session writing restores live workspace views")
	local content = table.concat(vim.fn.readfile(path), "\n")
	assert(content:find("restore_session", 1, true), "native session includes terminal workspace extension")
	for _, name in ipairs(names) do assert(not content:find(name, 1, true), "managed terminal URI is excluded from native recreation") end
	assert(vim.bo[ordinary].buflisted, "ordinary terminal listing is untouched")
	vim.opt.sessionoptions:remove("terminal")
	vim.cmd("mksession! " .. vim.fn.fnameescape(path .. ".no-terminals"))
	assert(not table.concat(vim.fn.readfile(path .. ".no-terminals"), "\n"):find("restore_session", 1, true),
		"sessionoptions without terminal excludes managed workspaces")
	vim.opt.sessionoptions:append("terminal")
	vim.opt.sessionoptions:remove("tabpages")
	vim.cmd("mksession! " .. vim.fn.fnameescape(path .. ".current"))
	assert(vim.api.nvim_get_current_win() == editor and #terminal.list() == 5,
		"current-tab session writing leaves other workspaces intact")
elseif vim.env.TERMINAL_SESSION_PHASE == "current" then
	vim.cmd("source " .. vim.fn.fnameescape(path .. ".current"))
	settle()
	assert(#vim.api.nvim_list_tabpages() == 1 and #terminal.list() == 1 and terminal.list()[1].title == "Shell",
		"sessionoptions without tabpages restores only the saved Vim tab")
	assert(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(two),
		"current-tab sessions preserve editor focus")
else
	local session = require("terminal.session")
	local restore, payload = session.restore_session
	session.restore_session = function(json) payload = json; return restore(json) end
	vim.cmd("source " .. vim.fn.fnameescape(path))
	session.restore_session = restore
	settle()
	assert(#vim.api.nvim_list_tabpages() == 3 and #terminal.list() == 5,
		"native session restores workspaces in the original Vim tabs without duplicates")
	assert(vim.fn.tabpagenr() == 2 and vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(two)
		and vim.api.nvim_win_get_cursor(0)[1] == 2,
		"native editor focus and cursor survive terminal restoration: " .. vim.inspect({
			tab = vim.fn.tabpagenr(), buf = vim.api.nvim_buf_get_name(0), expected = two, cursor = vim.api.nvim_win_get_cursor(0),
		}))
	assert(state.is_term_open(), "drawer is restored behind the focused editor")
	assert(vim.t.term_drawer_size == "50%", "percentage drawer size survives sessions")
	for _, item in ipairs(terminal.list()) do
		if item.title == "Frontend" then
			assert(vim.b[item.bufnr].terminal_launch.env.SESSION_QUOTING == "line one\nline two | ' \" \\",
				"native session preserves quoted commands and environment values")
		end
	end
	local ordinary = 0
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].buftype == "terminal" and not state.is_managed(buf) then ordinary = ordinary + 1 end
	end
	assert(ordinary == 1, "ordinary terminal uses native restoration and stays unmanaged")
	vim.cmd("tabfirst")
	settle()
	assert(not state.is_term_open() and vim.t.term_float_enabled and vim.t.term_zoom and #state.get_tabs() == 2,
		"hidden float and terminal tabs restore in the first Vim tab")
	assert(vim.deep_equal(vim.t.term_float_size, {width="80%", height="75%"}), "float dimensions survive sessions")
	terminal.toggle({ open = true })
	settle()
	assert(#vim.t.term_winids == 3 and state.get_title(vim.api.nvim_get_current_buf()) == "Tests",
		"nested pane layout and selected pane are restored")
	assert(vim.v.errmsg == "", "native session has no asynchronous errors")
	-- Malformed metadata and failed launches must preserve native editor tabs.
	local data = vim.json.decode(payload)
	local notices, notify = {}, vim.notify
	vim.notify = function(message) notices[#notices + 1] = message end
	local count, current = #vim.api.nvim_list_tabpages(), vim.api.nvim_get_current_buf()
	local broken = vim.deepcopy(data)
	broken.workspaces[1].entries[1].layout.children[1].pane = 99
	assert(not session.restore_session(vim.json.encode(broken)), "malformed pane references are rejected")
	assert(#vim.api.nvim_list_tabpages() == count and vim.api.nvim_get_current_buf() == current,
		"validation does not change native tabs or focus")
	broken = vim.deepcopy(data)
	local targets = {}
	for i, workspace in ipairs(broken.workspaces) do
		vim.cmd("tabnew")
		targets[i] = vim.api.nvim_get_current_tabpage()
		workspace.tabnr = vim.fn.tabpagenr()
	end
	broken.workspaces[1].open = true
	broken.workspaces[2].entries[1].panes[1].cmd = { directory .. "/missing-executable" }
	local tabs, buffers = #vim.api.nvim_list_tabpages(), #vim.api.nvim_list_bufs()
	current = vim.api.nvim_get_current_buf()
	assert(not session.restore_session(vim.json.encode(broken)), "process-start failures are reported")
	settle()
	assert(#vim.api.nvim_list_tabpages() == tabs and #vim.api.nvim_list_bufs() == buffers
		and vim.api.nvim_get_current_buf() == current and #terminal.list() == 5,
		"failed restoration removes new jobs and panes while preserving editor tabs")
	for _, tabpage in ipairs(targets) do assert(#state.get_tabs(tabpage) == 0, "failed targets have no stale workspace") end
	assert(#notices == 2, "failed native restores report their errors")
	vim.notify = notify
end
print("Native session " .. vim.env.TERMINAL_SESSION_PHASE .. " passed")
