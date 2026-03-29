-- terminal.nvim: setup (autocmds, keymaps, commands)

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local window = require("terminal.window")
local winbar = require("terminal.winbar")
local statusline = require("terminal.statusline")
local float_layout = require("terminal.float_layout")
local utils = require("terminal.utils")

local out_tty = vim.loop.new_tty(1, true)

function M.setup_autocmd(api)
	vim.api.nvim_create_augroup("Term", {})
	pcall(vim.api.nvim_clear_autocmds, { group = "nvim.terminal", event = "TermClose" })
	vim.api.nvim_create_autocmd("TermOpen", {
		pattern = "*",
		group = "Term",
		callback = function()
			vim.opt_local.signcolumn = "no"
			vim.opt_local.number = false
			vim.opt_local.relativenumber = false
			vim.opt_local.scrolloff = 0
			vim.opt_local.sidescrolloff = 0
			vim.opt_local.winblend = 0
			local bufnr = vim.fn.bufnr()
			if not state.find_buf_tab(bufnr) then
				state.add_term_to_order(bufnr)
			end
			vim.b.term_mode = "t"
			float_layout.setup_mouse_mappings(bufnr, api)
			vim.api.nvim_buf_attach(bufnr, false, {
				on_lines = function(_, buf)
					if not vim.api.nvim_buf_is_valid(buf) then
						return true
					end
					-- Find the vim tabpage that owns this buffer
					local owner_tab = nil
					for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
						local ok, order = pcall(vim.api.nvim_tabpage_get_var, tp, "term_order")
						if ok and order then
							for _, tab in ipairs(order) do
								for _, b in ipairs(tab) do
									if b == buf then
										owner_tab = tp
										break
									end
								end
								if owner_tab then break end
							end
						end
						if owner_tab then break end
					end
					if not owner_tab then
						return
					end
					local ok_tog, tab_toggling = pcall(vim.api.nvim_tabpage_get_var, owner_tab, "term_toggling")
					if ok_tog and tab_toggling then
						return
					end
					-- Skip if buffer is displayed in a current terminal window
					local ok_wins, wins = pcall(vim.api.nvim_tabpage_get_var, owner_tab, "term_winids")
					if ok_wins and wins then
						for _, win in ipairs(wins) do
							if state.win_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
								return
							end
						end
					end
					-- Find the tab index of this buffer within the owning tabpage
					local ok_order, order = pcall(vim.api.nvim_tabpage_get_var, owner_tab, "term_order")
					if not ok_order or not order then
						return
					end
					local gi = nil
					for i, tab in ipairs(state.migrate_term_order(order)) do
						for _, b in ipairs(tab) do
							if b == buf then
								gi = i
								break
							end
						end
						if gi then break end
					end
					local ok_idx, tab_idx = pcall(vim.api.nvim_tabpage_get_var, owner_tab, "term_tab_idx")
					if not gi or gi == (ok_idx and tab_idx or 1) then
						return
					end
					local ok_act, activity = pcall(vim.api.nvim_tabpage_get_var, owner_tab, "term_tab_activity")
					activity = (ok_act and activity) or {}
					if activity[tostring(gi)] then
						return
					end
					activity[tostring(gi)] = true
					vim.api.nvim_tabpage_set_var(owner_tab, "term_tab_activity", activity)
					vim.schedule(function()
						winbar.update()
					end)
				end,
			})
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		pattern = "*:t",
		group = "Term",
		callback = function()
			if vim.bo.buftype == "terminal" then
				vim.b.term_mode = "t"
			end
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		pattern = { "t:nt", "t:n" },
		group = "Term",
		callback = function()
			local bufnr = vim.fn.bufnr()
			local winid = vim.fn.win_getid()
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end
				if vim.fn.win_getid() ~= winid then
					return
				end
				if vim.bo[bufnr].buftype == "terminal" then
					vim.b[bufnr].term_mode = "n"
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("WinResized", {
		pattern = "*",
		group = "Term",
		callback = function()
			if vim.t.term_toggling then
				return
			end
			if vim.t.term_bufnr == nil then
				return
			end
			if vim.t.term_prev_height ~= nil or vim.t.term_zoom then
				return
			end
			local wins = vim.t.term_winids or {}
			if #wins > 0 and state.win_valid(wins[1]) then
				local height = vim.api.nvim_win_get_height(wins[1])
				if height > 0 then
					vim.t.term_height = height
				end
			end
			-- Save pane widths when user explicitly resizes (2+ panes)
			if #wins >= 2 then
				local _, tab_idx = state.get_current_tab()
				if tab_idx then
					local widths = {}
					local all_valid = true
					for i, win in ipairs(wins) do
						if state.win_valid(win) then
							widths[i] = vim.api.nvim_win_get_width(win)
						else
							all_valid = false
							break
						end
					end
					if all_valid then
						local st = state.get_tab_state(tab_idx)
						st.widths = widths
						state.set_tab_state(tab_idx, st)
					end
				end
			end
			winbar.update()
		end,
	})
	vim.api.nvim_create_autocmd("WinEnter", {
		pattern = "*",
		group = "Term",
		callback = function()
			state.adopt_orphaned_terminals()

			-- Track focus within pane windows
			local current_win = vim.fn.win_getid()
			local wins = vim.t.term_winids or {}
			for _, win in ipairs(wins) do
				if win == current_win then
					local old_winid = vim.t.term_winid
					if old_winid and old_winid ~= current_win then
						vim.t.term_prev_pane_winid = old_winid
					end
					vim.t.term_winid = current_win
					vim.t.term_bufnr = vim.api.nvim_win_get_buf(current_win)

					-- Clear activity for the current tab
					local current_tab_idx = vim.t.term_tab_idx or 1
					local activity = vim.t.term_tab_activity or {}
					if activity[tostring(current_tab_idx)] then
						activity[tostring(current_tab_idx)] = nil
						vim.t.term_tab_activity = activity
						winbar.update()
					end
					break
				end
			end

			-- Refocus terminal pane if winbar overlay is entered
			if current_win == vim.t.term_winbar_winid then
				vim.schedule(function()
					if vim.fn.win_getid() ~= vim.t.term_winbar_winid then
						return
					end
					local target = vim.t.term_winid
					if state.win_valid(target) then
						vim.api.nvim_set_current_win(target)
					else
						local term_wins2 = vim.t.term_winids or {}
						for _, win in ipairs(term_wins2) do
							if state.win_valid(win) then
								vim.api.nvim_set_current_win(win)
								return
							end
						end
					end
				end)
			end

			-- Refocus terminal pane if statusline overlay is entered
			local stl_buf_ok, stl_buf = pcall(vim.api.nvim_win_get_buf, current_win)
			if stl_buf_ok and vim.b[stl_buf].terminal_stl then
				local stl_pane = vim.b[stl_buf].terminal_stl_pane
				vim.schedule(function()
					if stl_pane and state.win_valid(stl_pane) then
						vim.api.nvim_set_current_win(stl_pane)
						local buf = vim.api.nvim_win_get_buf(stl_pane)
						local mode = vim.b[buf].term_mode
						if mode == "t" or mode == nil then
							vim.cmd("startinsert")
						else
							vim.cmd("stopinsert")
						end
						statusline.update()
					end
				end)
			end

		end,
	})
	vim.api.nvim_create_autocmd("TabNew", {
		pattern = "*",
		group = "Term",
		callback = function()
			vim.t.term_height = config.get_term_height()
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		pattern = "*",
		group = "Term",
		callback = function()
			if not vim.t.term_toggling then
				state.save_term_height()
			end
			if not vim.t.term_toggling and config.is_float_mode() and state.is_term_related_window(vim.fn.win_getid()) then
				local tab = vim.api.nvim_get_current_tabpage()
				vim.schedule(function()
					if vim.api.nvim_get_current_tabpage() ~= tab then
						return
					end
					if not state.is_term_related_window(vim.fn.win_getid()) then
						api.toggle({ open = false })
					end
				end)
			end
		end,
	})

	local function update_float_win_config()
		if not config.is_float_mode() or not state.is_term_open() then
			return
		end
		window.rebuild_tab()
	end

	vim.api.nvim_create_autocmd("VimResized", {
		group = "Term",
		callback = function()
			update_float_win_config()
			winbar.update()
		end,
	})
	vim.api.nvim_create_autocmd("TabEnter", {
		group = "Term",
		callback = function()
			vim.schedule(function()
				state.adopt_orphaned_terminals()
				update_float_win_config()
				winbar.update()
				if vim.bo.buftype == "terminal" then
					if vim.b.term_mode == "t" or vim.b.term_mode == nil then
						vim.cmd("startinsert")
					end
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("TabClosed", {
		group = "Term",
		callback = function()
			vim.schedule(function()
				update_float_win_config()
				winbar.update()
			end)
		end,
	})
	vim.api.nvim_create_autocmd("TermClose", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local bufnr = ev.buf
			local tab_idx_closed = state.find_buf_tab(bufnr)

			local current_tab_idx = vim.t.term_tab_idx or 1
			local is_in_active_tab = tab_idx_closed == current_tab_idx

			local is_displayed = is_in_active_tab and state.is_term_open()

			state.remove_term_from_order(bufnr)

			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end

				if is_displayed then
					window.rebuild_tab()
				else
					winbar.update()
				end
			end)
		end,
	})
end

function M.setup_winbar_autocmds()
	if not config.config.winbar then
		return
	end

	vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter", "BufFilePost" }, {
		pattern = "*",
		group = "Term",
		callback = function()
			if vim.t.term_toggling then
				return
			end
			if vim.bo[0].buftype == "terminal" then
				winbar.update()
			end
		end,
	})

	vim.api.nvim_create_autocmd("TermRequest", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local seq = ev.data.sequence

			if seq:match("^\x1b%]0;") then
				local title = seq:match("\x1b%]0;([^\007]+)")
				if title and #title > 0 then
					local buf = ev.buf
					vim.b[buf].term_title = title
					winbar.update()
					statusline.update()
				end
			end
		end,
	})
end

function M.setup_osc_notifications()
	if not config.config.osc_notifications then
		return
	end

	vim.api.nvim_create_autocmd("TermRequest", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local seq = ev.data.sequence

			if seq:sub(1, 4) ~= "\x1b]9;" and seq:sub(1, 5) ~= "\x1b]99;" and seq:sub(1, 6) ~= "\x1b]777;" then
				return
			end

			-- Pass through to terminal
			vim.loop.write(out_tty, seq)

			-- OSC 9;4 is progress reporting -- pass through but don't notify
			if seq:sub(1, 5) == "\x1b]9;4" then
				return
			end

			state.set_last_notification_bufnr(ev.buf)

			-- Notify when not focused in a terminal buffer
			local is_term_buf = vim.bo.buftype == "terminal"
			if is_term_buf then
				return
			end

			local title, body = seq:match("\x1b%]777;notify;([^;\007]+);([^\007]*)")
			if not body then
				body = seq:match("\x1b%]777;notify;([^\007]*)")
			end
			if not body then
				body = seq:match("\x1b%]99?;([^\007]*)")
			end
			if body then
				title = title or "Terminal notification"
				vim.notify(title .. ": " .. body, vim.log.levels.INFO)
			end
			vim.loop.write(out_tty, "\a")
		end,
	})
end

function M.setup_keymap(api)
	local keys = config.config.keys
	if keys == false then
		return
	end

	local function map(modes, key, action, opts)
		if key == false then
			return
		end
		if type(key) == "table" then
			for _, k in ipairs(key) do
				map(modes, k, action, opts)
			end
			return
		end
		vim.keymap.set(modes, key, action, opts or {})
	end

	map({ "n", "t" }, keys.toggle, api.toggle)
	map("t", keys.normal_mode, "<C-\\><C-n>", { noremap = true })
	map({ "n", "t" }, keys.zoom, api.zoom)
	map({ "n", "t" }, keys.reset_height, api.reset_height)
	map({ "n", "t" }, keys.new, api.new, { noremap = true })
	map({ "n", "t" }, keys.delete, api.delete, { noremap = true })

	map({ "n", "t" }, keys.prev, function()
		api.switch(-1)
	end)
	map({ "n", "t" }, keys.next, function()
		api.switch(1)
	end)

	map({ "n", "t" }, keys.move_prev, function()
		api.move(-1)
	end)
	map({ "n", "t" }, keys.move_next, function()
		api.move(1)
	end)

	map({ "n", "t" }, keys.move_to_vim_tab_prev, function()
		api.move_to_vim_tab(-1)
	end)
	map({ "n", "t" }, keys.move_to_vim_tab_next, function()
		api.move_to_vim_tab(1)
	end)

	map({ "n", "t" }, keys.last_notification, api.go_to_notification, { noremap = true })

	for i = 1, 9 do
		local key = "<C-S-" .. i .. ">"
		if key ~= keys.last_notification then
			vim.keymap.set({ "n", "t" }, key, function()
				api.go_to(i)
			end, { noremap = true })
		end
	end

	local function switch_vim_tab(direction)
		local src_mode = vim.fn.mode()
		if vim.bo.buftype == "terminal" then
			vim.b.term_mode = src_mode
		end
		if src_mode == "t" then
			vim.cmd("stopinsert")
		end
		if direction > 0 then
			vim.cmd("tabnext")
		else
			vim.cmd("tabprevious")
		end
		vim.schedule(function()
			if vim.bo.buftype == "terminal" then
				if vim.b.term_mode == "t" or vim.b.term_mode == nil then
					vim.cmd("startinsert")
				end
			end
		end)
	end

	map({ "n", "t" }, keys.vim_tab_prev, function()
		switch_vim_tab(-1)
	end, { noremap = true })
	map({ "n", "t" }, keys.vim_tab_next, function()
		switch_vim_tab(1)
	end, { noremap = true })

	local function move_vim_tab(direction)
		local current = vim.fn.tabpagenr()
		local last = vim.fn.tabpagenr("$")
		if last < 2 then
			return
		end
		-- :tabmove N places the tab *after* tab N
		local target
		if direction == -1 then
			target = current - 2
		else
			target = current + 1
		end
		if target < 0 then
			target = last
		elseif target > last then
			target = 0
		end
		vim.cmd("tabmove " .. target)
	end

	map({ "n", "t" }, keys.vim_tab_move_prev, function()
		move_vim_tab(-1)
	end, { noremap = true })
	map({ "n", "t" }, keys.vim_tab_move_next, function()
		move_vim_tab(1)
	end, { noremap = true })

	if keys.paste_register ~= false then
		vim.keymap.set("t", keys.paste_register, function()
			local ok, char = pcall(vim.fn.getchar)
			if not ok or type(char) ~= "number" or char < 0 then
				return
			end
			local reg = vim.fn.nr2char(char)
			local txt = vim.fn.getreg(reg)

			local job = vim.b.terminal_job_id
			if not job then
				vim.notify("Not in a terminal buffer!", vim.log.levels.WARN)
				return
			end
			vim.api.nvim_chan_send(job, txt)
		end, { noremap = true, silent = true })

		vim.keymap.set("t", keys.paste_register .. "=", function()
			local expr = vim.fn.input("=")
			if expr == "" then
				return
			end

			local ok, result = pcall(vim.fn.eval, expr)
			if not ok then
				vim.notify("Invalid expression: " .. result, vim.log.levels.ERROR)
				return
			end

			local txt = tostring(result)
			local opener = "\027[200~"
			local closer = "\027[201~"

			local job = vim.b.terminal_job_id
			if not job then
				vim.notify("Not in a terminal buffer!", vim.log.levels.WARN)
				return
			end
			vim.api.nvim_chan_send(job, opener .. txt .. closer)
		end, { noremap = true, silent = true })
	end

	-- <C-S-w> prefix: terminal window management
	local function restore_term_mode()
		if vim.b.term_mode == "t" or vim.b.term_mode == nil then
			vim.cmd("startinsert")
		else
			vim.cmd("stopinsert")
		end
	end

	local function pane_navigate(delta)
		local wins = vim.t.term_winids or {}
		local current = vim.fn.win_getid()
		for i, win in ipairs(wins) do
			if win == current then
				local target = i + delta
				if target >= 1 and target <= #wins and state.win_valid(wins[target]) then
					vim.api.nvim_set_current_win(wins[target])
					restore_term_mode()
					statusline.update()
				end
				return
			end
		end
		-- Fallback to native wincmd in split mode
		if not config.is_float_mode() then
			vim.cmd("wincmd " .. (delta < 0 and "h" or "l"))
			restore_term_mode()
		end
	end

	local function pane_cycle()
		local wins = vim.t.term_winids or {}
		if #wins < 2 then
			return
		end
		local current = vim.fn.win_getid()
		for i, win in ipairs(wins) do
			if win == current then
				local target = (i % #wins) + 1
				if state.win_valid(wins[target]) then
					vim.api.nvim_set_current_win(wins[target])
					restore_term_mode()
					statusline.update()
				end
				return
			end
		end
	end

	map({ "n", "t" }, "<C-S-h>", function() pane_navigate(-1) end, { noremap = true })
	map({ "n", "t" }, "<C-S-l>", function() pane_navigate(1) end, { noremap = true })
	map({ "n", "t" }, "<C-S-v>", api.vsplit, { noremap = true })
	map({ "n", "t" }, "<C-S-p>", function()
		local prev = vim.t.term_prev_pane_winid
		if prev and state.win_valid(prev) then
			vim.api.nvim_set_current_win(prev)
			restore_term_mode()
			statusline.update()
		end
	end, { noremap = true })

	local function resize_current_pane(delta)
		local wins = vim.t.term_winids or {}
		local current = vim.fn.win_getid()

		if not config.is_float_mode() then
			if delta > 0 then
				vim.cmd(delta .. "wincmd >")
			else
				vim.cmd((-delta) .. "wincmd <")
			end
			return
		end

		local pane_idx
		for i, win in ipairs(wins) do
			if win == current then
				pane_idx = i
				break
			end
		end
		if not pane_idx or #wins < 2 then
			return
		end

		local widths = {}
		for i, win in ipairs(wins) do
			if state.win_valid(win) then
				widths[i] = vim.api.nvim_win_get_width(win)
			else
				return
			end
		end

		local new_widths = float_layout.calc_resized_widths(widths, pane_idx, delta)
		float_layout.apply_float_pane_layout(new_widths)
		float_layout.save_pane_widths()
	end

	local function move_pane_to(target_pos)
		local tab, tab_idx = state.get_current_tab()
		if not tab or #tab < 2 then
			return
		end

		local bufnr = vim.fn.bufnr()
		local _, pane_idx = state.find_buf_tab(bufnr)
		if not pane_idx then
			return
		end
		if target_pos == 1 and pane_idx == 1 then
			return
		end
		if target_pos == #tab and pane_idx == #tab then
			return
		end

		state.set_toggling()
		window.save_tab_state()
		window.close_pane_windows()

		local order = state.get_term_order()
		table.remove(order[tab_idx], pane_idx)
		table.insert(order[tab_idx], target_pos, bufnr)
		vim.t.term_order = order

		local st = state.get_tab_state(tab_idx)
		st.widths = nil
		st.focus = target_pos
		state.set_tab_state(tab_idx, st)

		window.reopen_current_tab(tab_idx)
	end

	local function rotate_panes(direction)
		local tab, tab_idx = state.get_current_tab()
		if not tab or #tab < 2 then
			return
		end

		local bufnr = vim.fn.bufnr()
		local _, pane_idx = state.find_buf_tab(bufnr)
		if not pane_idx then
			return
		end

		state.set_toggling()

		window.save_tab_state()
		window.close_pane_windows()

		local order = state.get_term_order()
		local g = order[tab_idx]
		if direction > 0 then
			local last = table.remove(g)
			table.insert(g, 1, last)
		else
			local first = table.remove(g, 1)
			table.insert(g, first)
		end
		vim.t.term_order = order

		local new_pane_idx
		for i, buf in ipairs(g) do
			if buf == bufnr then
				new_pane_idx = i
				break
			end
		end

		local st = state.get_tab_state(tab_idx)
		st.widths = nil
		st.focus = new_pane_idx or 1
		state.set_tab_state(tab_idx, st)

		window.reopen_current_tab(tab_idx)
	end

	if keys.wincmd ~= false then
		local function key_match(c, ...)
			local trans = vim.fn.keytrans(c)
			for _, name in ipairs({ ... }) do
				-- Exact match
				if trans == name then return true end
				-- Case-insensitive match for modified keys only (<C-S-H> matches <C-S-h>)
				if trans:match("^<") and name:match("^<") and trans:lower() == name:lower() then
					return true
				end
			end
			return false
		end

		local function term_wincmd()
			local count = 0

			while true do
				local ok, c = pcall(vim.fn.getcharstr)
				if not ok or c == "" then
					return
				end

				if c >= "0" and c <= "9" then
					count = count * 10 + tonumber(c)
				else
					if count == 0 then
						count = 1
					end

					if key_match(c, "w", "<C-S-w>") then
						pane_cycle()
					elseif key_match(c, "v", "<C-S-v>") then
						api.vsplit()
					elseif key_match(c, "h", "<C-S-h>") then
						pane_navigate(-1)
					elseif key_match(c, "l", "<C-S-l>") then
						pane_navigate(1)
					elseif c == ">" then
						resize_current_pane(count)
					elseif c == "<" then
						resize_current_pane(-count)
					elseif key_match(c, "H", "<S-H>") then
						local tab = state.get_current_tab()
						if tab then
							move_pane_to(1)
						end
					elseif key_match(c, "L", "<S-L>") then
						local tab = state.get_current_tab()
						if tab then
							move_pane_to(#tab)
						end
					elseif key_match(c, "r", "<C-R>", "<C-S-R>") then
						rotate_panes(1)
					elseif key_match(c, "R", "<S-R>") then
						rotate_panes(-1)
					elseif c == "=" then
						float_layout.equalize_panes()
					elseif key_match(c, "p", "<C-S-p>") then
						local prev = vim.t.term_prev_pane_winid
						if prev and state.win_valid(prev) then
							vim.api.nvim_set_current_win(prev)
							restore_term_mode()
							statusline.update()
						end
					elseif key_match(c, "c", "<C-S-c>") then
						api.delete()
					elseif key_match(c, "<CR>", "<C-S-CR>") and count > 1 then
						vim.t.term_height = count
						local wins = vim.t.term_winids or {}
						if not config.is_float_mode() and #wins > 0 and state.win_valid(wins[1]) then
							vim.api.nvim_win_call(wins[1], function()
								vim.cmd("resize " .. count)
							end)
						end
					end
					return
				end
			end
		end

		map({ "n", "t" }, keys.wincmd, term_wincmd, { noremap = true })
	end

	-- <C-w> overrides for terminal panes (normal mode)
	local function nmap_cw(suffix, action)
		vim.keymap.set({ "n" }, "<C-w>" .. suffix, function()
			if state.is_in_term_window() then
				action()
			else
				local fallback = vim.api.nvim_replace_termcodes("<C-w>" .. suffix, true, true, true)
				vim.api.nvim_feedkeys(fallback, "n", false)
			end
		end, { noremap = true })
	end

	local cw_actions = {
		{ { "w", "<C-w>" }, pane_cycle },
		{ { "h", "<C-h>" }, function() pane_navigate(-1) end },
		{ { "l", "<C-l>" }, function() pane_navigate(1) end },
		{ { ">" },          function() resize_current_pane(vim.v.count1) end },
		{ { "<lt>" },       function() resize_current_pane(-vim.v.count1) end },
		{ { "=" },          float_layout.equalize_panes },
		{ { "p", "<C-p>" }, function()
			local prev = vim.t.term_prev_pane_winid
			if prev and state.win_valid(prev) then
				vim.api.nvim_set_current_win(prev)
				restore_term_mode()
				statusline.update()
			end
		end },
		{ { "c", "<C-c>" }, api.delete },
		{ { "v", "<C-v>" }, api.vsplit },
		{ { "H" }, function()
			local g = state.get_current_tab(); if g then move_pane_to(1) end
		end },
		{ { "L" }, function()
			local g = state.get_current_tab(); if g then move_pane_to(#g) end
		end },
		{ { "r", "<C-r>" }, function() rotate_panes(1) end },
		{ { "R" },          function() rotate_panes(-1) end },
	}

	for _, entry in ipairs(cw_actions) do
		for _, suffix in ipairs(entry[1]) do
			nmap_cw(suffix, entry[2])
		end
	end
end

function M.setup_command(api)
	vim.api.nvim_create_user_command("TermSplit", "new | term", {})
	vim.api.nvim_create_user_command("TermVsplit", "vnew | term", {})
	vim.api.nvim_create_user_command("TermTab", function(opts)
		vim.cmd(opts.args .. "tabnew | term")
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("TermDelete", function()
		api.delete()
	end, {})
	vim.api.nvim_create_user_command("TermReset", 'exe "te" | bd!# | let t:term_bufnr = bufnr("%")', {})
end

function M.setup_alias()
	utils.alias("tsplit", "TermSplit")
	utils.alias("tvsplit", "TermVsplit")
	utils.alias("ttab", "TermTab")
	utils.alias("tdelete", "TermDelete")
	utils.alias("st", "TermSplit")
	utils.alias("vst", "TermVsplit")
	utils.alias("tt", "TermTab")
	utils.alias("td", "TermDelete")
end

return M
