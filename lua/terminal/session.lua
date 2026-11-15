-- Extend Neovim's native sessions with managed layouts and launch settings.
local M = {}
local state = require("terminal.state")
local frame = require("terminal.frame")
local config = require("terminal.config")
local window = require("terminal.window")
local launch = require("terminal.launch")

local function float_enabled(vars)
	if vars.term_float_enabled ~= nil then return vars.term_float_enabled end
	local setting = config.config.float
	if type(setting) == "table" then return setting.enabled ~= false end
	return not not setting
end

local function encode_layout(node, indices)
	local result = { t = node.t, w = node.w, h = node.h }
	if node.t == "leaf" then
		result.pane = assert(indices[node.buf], "layout references an unknown pane")
	else
		result.children = {}
		for _, child in ipairs(node.children) do
			result.children[#result.children + 1] = encode_layout(child, indices)
		end
	end
	return result
end

local function snapshot()
	local result = { version = 1, selected = 0, workspaces = {} }
	local current_tab, current_win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
	for tabnr, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		local order = state.get_tabs(tabpage)
		if #order > 0 then
			local vars = vim.t[tabpage]
			local active = vars.term_tab_idx or 1
			local live = {}
			for _, win in ipairs(vars.term_winids or {}) do
				if state.win_valid(win) then
					local buf = vim.api.nvim_win_get_buf(win)
					if state.is_managed(buf) then live[buf] = win end
				end
			end
			local workspace = {
				tabnr = tabnr,
				height = vars.term_height or config.get_term_height(),
				previous_height = vars.term_prev_height,
				float = float_enabled(vars), zoom = not not vars.term_zoom,
				open = next(live) ~= nil, active = active, entries = {},
			}
			workspace.focused = live[vars.term_bufnr] == vim.api.nvim_tabpage_get_win(tabpage)
			for index, entry in ipairs(order) do
				local saved = { panes = {}, focus = 1 }
				local indices, sizes, visible = {}, {}, 0
				local focus = index == active and vars.term_bufnr or entry.focus
				for pane, buf in ipairs(entry.bufs) do
					indices[buf] = pane
					local settings = assert(vim.b[buf].terminal_launch, "terminal has no saved launch settings")
					local pane_mode = vim.b[buf].term_mode or "t"
					if live[buf] == current_win then pane_mode = vim.api.nvim_get_mode().mode == "t" and "t" or "n" end
					local env = vim.deepcopy(settings.env or {})
					if next(env) == nil then env = vim.empty_dict() end
					saved.panes[pane] = {
						cmd = vim.deepcopy(settings.cmd), cwd = settings.cwd, env = env,
						name = vim.b[buf].terminal_custom_name, mode = pane_mode,
					}
					if buf == focus then saved.focus = pane end
					if live[buf] then
						visible = visible + 1
						sizes[pane] = { w = vim.api.nvim_win_get_width(live[buf]), h = vim.api.nvim_win_get_height(live[buf]) }
					end
				end
				local layout = vim.deepcopy(entry.layout)
				if index == active and visible == #entry.bufs then frame.set_leaf_sizes(layout, sizes) end
				saved.layout = encode_layout(layout, indices)
				workspace.entries[index] = saved
			end
			result.workspaces[#result.workspaces + 1] = workspace
			if tabpage == current_tab then result.selected = #result.workspaces end
		end
	end
	assert(#result.workspaces > 0, "No managed terminals to save")
	return result
end

local function integer(value, minimum, maximum)
	return type(value) == "number" and value < math.huge and value == math.floor(value) and value >= minimum
		and (not maximum or value <= maximum)
end

local function validate_layout(node, count, seen, parent)
	assert(type(node) == "table" and integer(node.w, 1) and integer(node.h, 1), "invalid pane dimensions")
	if node.t == "leaf" then
		assert(integer(node.pane, 1, count) and not seen[node.pane], "invalid or duplicate pane reference")
		seen[node.pane] = true
	else
		assert((node.t == "row" or node.t == "col") and node.t ~= parent, "invalid pane layout")
		assert(type(node.children) == "table" and vim.islist(node.children) and #node.children >= 2,
			"invalid layout children")
		for _, child in ipairs(node.children) do validate_layout(child, count, seen, node.t) end
	end
end

local function validate(data)
	assert(type(data) == "table" and data.version == 1, "unsupported terminal workspace version")
	assert(type(data.workspaces) == "table" and vim.islist(data.workspaces) and #data.workspaces > 0,
		"workspace has no terminal tabs")
	assert(integer(data.selected, 0, #data.workspaces), "invalid selected workspace")
	for _, workspace in ipairs(data.workspaces) do
		assert(type(workspace) == "table" and type(workspace.float) == "boolean"
			and type(workspace.zoom) == "boolean" and type(workspace.open) == "boolean", "invalid workspace view")
		assert(integer(workspace.height, 1), "invalid drawer height")
		assert(integer(workspace.tabnr, 1), "invalid Vim tab number")
		assert(type(workspace.focused) == "boolean", "invalid workspace focus")
		assert(workspace.previous_height == nil or integer(workspace.previous_height, 1), "invalid previous drawer height")
		assert(type(workspace.entries) == "table" and vim.islist(workspace.entries) and #workspace.entries > 0,
			"workspace has no terminal entries")
		assert(integer(workspace.active, 1, #workspace.entries), "invalid active terminal tab")
		for _, entry in ipairs(workspace.entries) do
			assert(type(entry) == "table" and type(entry.panes) == "table" and vim.islist(entry.panes)
				and #entry.panes > 0, "terminal tab has no panes")
			assert(integer(entry.focus, 1, #entry.panes), "invalid focused pane")
			local seen = {}
			validate_layout(entry.layout, #entry.panes, seen)
			for i, pane in ipairs(entry.panes) do
				assert(seen[i], "pane is missing from layout")
				assert(type(pane) == "table" and (pane.mode == "t" or pane.mode == "n"), "invalid pane mode")
				assert(pane.cmd ~= nil and type(pane.cwd) == "string", "invalid saved launch settings")
				pane.launch = launch.normalize({ cmd = pane.cmd, cwd = pane.cwd, env = pane.env, name = pane.name })
			end
		end
	end
	return data
end

local function restore_layout(node, bufs)
	local result = { t = node.t, w = node.w, h = node.h }
	if node.t == "leaf" then
		result.buf = bufs[node.pane]
	else
		result.children = {}
		for _, child in ipairs(node.children) do result.children[#result.children + 1] = restore_layout(child, bufs) end
	end
	return result
end

local function restore_data(data, targets)
	local original_tab, original_win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
	local original_mode = vim.api.nvim_get_mode().mode
	require("terminal.mode").record()
	local tabs, buffers, editor_wins, original_vars = {}, {}, {}, {}
	local function return_to_original()
		if vim.api.nvim_tabpage_is_valid(original_tab) then vim.api.nvim_set_current_tabpage(original_tab) end
		if state.win_valid(original_win) then vim.api.nvim_set_current_win(original_win) end
		if state.is_managed() then
			require("terminal.mode").restore_scheduled(original_win)
		else
			vim.cmd((original_mode == "t" or original_mode:sub(1, 1) == "i") and "startinsert" or "stopinsert")
		end
	end
	local ok, err = pcall(function()
		-- Preflight saved panes before starting jobs; keep native editor windows.
		for index, workspace in ipairs(data.workspaces) do
			vim.api.nvim_set_current_tabpage(targets[index])
			original_vars[targets[index]] = {}
			for key, value in pairs(vim.fn.gettabvar(vim.api.nvim_tabpage_get_number(targets[index]), "")) do
				if key:match("^term_") or key == "prev_winid" then original_vars[targets[index]][key] = value end
			end
			tabs[#tabs + 1] = vim.api.nvim_get_current_tabpage()
			editor_wins[index] = vim.api.nvim_get_current_win()
			state.setup_vars()
			vim.t.term_height = workspace.height
			vim.t.term_prev_height = workspace.previous_height
			vim.t.term_float_enabled = workspace.float
			vim.t.term_zoom = workspace.zoom and true or nil
			if workspace.open then
				local entry = workspace.entries[workspace.active]
				local placeholders = {}
				for i in ipairs(entry.panes) do placeholders[i] = -i end
				assert(window.can_open_tab({ layout = restore_layout(entry.layout, placeholders) }, #workspace.entries),
					"saved terminal layout does not fit")
			end
		end
		for index, workspace in ipairs(data.workspaces) do
			vim.api.nvim_set_current_tabpage(tabs[index])
			state.set_toggling()
			vim.t.prev_winid = vim.api.nvim_get_current_win()
			local order = {}
			for _, saved in ipairs(workspace.entries) do
				local bufs, modes = {}, {}
				for pane, settings in ipairs(saved.panes) do
					local buf = vim.api.nvim_create_buf(false, true)
					buffers[#buffers + 1] = buf
					bufs[pane] = buf
					window.termopen_with_size(buf, #saved.panes, #workspace.entries, settings.launch)
					vim.b[buf].term_mode = settings.mode
					modes[tostring(buf)] = settings.mode
				end
				local entry = state.new_entry(bufs[1])
				entry.layout = restore_layout(saved.layout, bufs)
				entry.focus, entry.modes = bufs[saved.focus], modes
				state.sync_bufs(entry)
				order[#order + 1] = entry
			end
			state.set_term_order(order)
			vim.t.term_tab_idx = workspace.active
			if workspace.open then
				assert(window.open_tab_windows(order[workspace.active], workspace.active), "could not open saved workspace")
			end
			if not workspace.focused and state.win_valid(editor_wins[index]) then
				vim.api.nvim_set_current_win(editor_wins[index])
				vim.cmd("stopinsert")
			end
		end
		if data.selected > 0 then
			vim.api.nvim_set_current_tabpage(tabs[data.selected])
			local win = vim.t.term_winid
			if state.win_valid(win) and vim.api.nvim_get_current_win() == win then require("terminal.mode").restore_scheduled(win) end
		else
			return_to_original()
		end
	end)
	if not ok then
		for i = #tabs, 1, -1 do
			if vim.api.nvim_tabpage_is_valid(tabs[i]) then
				vim.api.nvim_set_current_tabpage(tabs[i])
				pcall(window.close_pane_windows)
			end
		end
		for _, buf in ipairs(buffers) do
			if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
		end
		for tabpage, vars in pairs(original_vars) do
			if vim.api.nvim_tabpage_is_valid(tabpage) then
				for key in pairs(vim.fn.gettabvar(vim.api.nvim_tabpage_get_number(tabpage), "")) do
					if key:match("^term_") or key == "prev_winid" then vim.t[tabpage][key] = nil end
				end
				for key, value in pairs(vars) do vim.t[tabpage][key] = value end
			end
		end
		return_to_original()
		return false, tostring(err)
	end
	return true, tabs
end

-- Called by the extension written into Neovim's native session file.
function M.restore_session(json)
	local ok, result = pcall(function()
		local data = validate(vim.json.decode(json))
		local tabpages, targets, seen = vim.api.nvim_list_tabpages(), {}, {}
		for _, workspace in ipairs(data.workspaces) do
			local tabpage = tabpages[workspace.tabnr or 0]
			assert(tabpage and not seen[tabpage], "saved Vim tab is unavailable")
			assert(#state.get_tabs(tabpage) == 0, "Vim tab already has a terminal workspace")
			seen[tabpage] = true
			targets[#targets + 1] = tabpage
		end
		local restored, err = restore_data(data, targets)
		assert(restored, err)
		return targets
	end)
	if not ok then vim.notify("Could not restore terminal session: " .. tostring(result), vim.log.levels.ERROR) end
	return ok, result
end

function M.setup()
	if vim.fn.exists("##SessionWritePre") == 0 then return end
	local pending
	local function recover(context)
		for buf, listed in pairs(context.listed) do
			if vim.api.nvim_buf_is_valid(buf) then vim.bo[buf].buflisted = listed end
		end
		for _, item in ipairs(context.views) do
			if vim.api.nvim_tabpage_is_valid(item.tabpage) then
				vim.api.nvim_set_current_tabpage(item.tabpage)
				state.set_toggling()
				window.reopen_current_tab()
				if state.win_valid(item.editor) then vim.api.nvim_set_current_win(item.editor) end
			end
		end
		if vim.api.nvim_tabpage_is_valid(context.tabpage) then vim.api.nvim_set_current_tabpage(context.tabpage) end
		if state.win_valid(context.win) then vim.api.nvim_set_current_win(context.win) end
		require("terminal.mode").restore_scheduled(vim.api.nvim_get_current_win())
	end
	vim.api.nvim_create_autocmd("SessionWritePre", {
		group = "Term",
		callback = function()
			if not vim.tbl_contains(vim.opt.sessionoptions:get(), "terminal") then return end
			local has_terminals = false
			for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
				if #state.get_tabs(tabpage) > 0 then has_terminals = true; break end
			end
			if not has_terminals then return end
			local context = {
				data = snapshot(), listed = {}, views = {},
				tabpage = vim.api.nvim_get_current_tabpage(), win = vim.api.nvim_get_current_win(),
				previous_session = vim.v.this_session,
				previous_stat = vim.uv.fs_stat(vim.v.this_session),
			}
			pending = context
			-- Restore live views even if session writing is interrupted.
			vim.schedule(function()
				if pending == context then pending = nil; recover(context) end
			end)
			local all_tabs = vim.tbl_contains(vim.opt.sessionoptions:get(), "tabpages")
			local original_tabnr = vim.api.nvim_tabpage_get_number(context.tabpage)
			local included, selected = {}, 0
			for index, workspace in ipairs(context.data.workspaces) do
				local tabpage = vim.api.nvim_list_tabpages()[workspace.tabnr]
				for _, entry in ipairs(state.get_tabs(tabpage)) do
					for _, buf in ipairs(entry.bufs) do
						context.listed[buf] = vim.bo[buf].buflisted
						vim.bo[buf].buflisted = false
					end
				end
				if all_tabs or workspace.tabnr == original_tabnr then
					if context.data.selected == index then selected = #included + 1 end
					included[#included + 1] = workspace
					if not all_tabs then workspace.tabnr = 1 end
					if workspace.open then
						vim.api.nvim_set_current_tabpage(tabpage)
						local editor = vim.api.nvim_get_current_win()
						if state.is_in_term_window() then editor = nil end
						context.views[#context.views + 1] = { tabpage = tabpage, editor = editor }
						state.set_toggling()
						window.save_tab_state()
						window.close_pane_windows()
					end
				end
			end
			context.data.workspaces, context.data.selected = included, selected
			vim.api.nvim_set_current_tabpage(context.tabpage)
			if state.win_valid(context.win) then vim.api.nvim_set_current_win(context.win) end
		end,
	})
	vim.api.nvim_create_autocmd("SessionWritePost", {
		group = "Term",
		callback = function()
			local context = pending
			if not context then return end
			pending = nil
			local path, stat = vim.v.this_session, vim.uv.fs_stat(vim.v.this_session)
			local old = context.previous_stat
			local written = stat and (path ~= context.previous_session or not old
				or stat.mtime.sec ~= old.mtime.sec or stat.mtime.nsec ~= old.mtime.nsec or stat.size ~= old.size)
			local ok, err = pcall(function()
				if written and #context.data.workspaces > 0 then
					local command = "lua do local ok, session = pcall(require, 'terminal.session'); if ok then session.restore_session("
						.. string.format("%q", vim.json.encode(context.data)) .. ") end end"
					assert(vim.fn.writefile({ command }, path, "a") == 0, "could not extend native session")
				end
			end)
			recover(context)
			if not ok then error(err, 0) end
		end,
	})
end

return M
