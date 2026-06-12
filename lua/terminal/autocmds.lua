-- terminal.nvim: autocommand registration

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local mode = require("terminal.mode")
local window = require("terminal.window")
local winbar = require("terminal.winbar")
local statusline = require("terminal.statusline")
local float_layout = require("terminal.float_layout")
local bufname = require("terminal.bufname")

local function get_term_refocus_target()
	local target = vim.t.term_winid
	if state.win_valid(target) then
		return target
	end

	for _, win in ipairs(vim.t.term_winids or {}) do
		if state.win_valid(win) then
			return win
		end
	end

	return nil
end

local function refocus_term_overlay(overlay_win, target_win, target_mode, after)
	if not state.win_valid(target_win) then
		return
	end

	vim.t.term_overlay_refocus = true
	vim.schedule(function()
		if vim.api.nvim_get_current_win() ~= overlay_win then
			vim.schedule(function()
				vim.t.term_overlay_refocus = false
			end)
			return
		end

		if state.win_valid(target_win) then
			vim.api.nvim_set_current_win(target_win)
			mode.restore_scheduled(target_win, target_mode)
			if after then
				after()
			end
		end

		vim.schedule(function()
			vim.t.term_overlay_refocus = false
		end)
	end)
end

function M.setup(api)
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

			local bufnr = vim.api.nvim_get_current_buf()
			local was_winbar_visible = config.should_show_winbar(#state.get_tabs())
			local known_tab = state.find_buf_tab(bufnr)
			if not known_tab then
				state.add_term_to_order(bufnr)
			end
			vim.b.term_mode = "t"
			vim.b[bufnr].term_owner_tab = vim.api.nvim_get_current_tabpage()
			float_layout.setup_mouse_mappings(bufnr, api)

			local is_winbar_visible = config.should_show_winbar(#state.get_tabs())
			if was_winbar_visible ~= is_winbar_visible and state.is_term_open() and not vim.t.term_toggling then
				vim.schedule(function()
					if state.is_term_open() then
						window.rebuild_tab()
					else
						winbar.update()
					end
				end)
			end

			vim.api.nvim_buf_attach(bufnr, false, {
				on_lines = function(_, buf)
					if not vim.api.nvim_buf_is_valid(buf) then
						return true
					end
					-- Activity already flagged: skip the order scan until the
					-- flag is cleared (on_lines fires per output chunk, so this
					-- is the hot path for busy background terminals)
					if vim.b[buf].term_activity_flagged then
						return
					end
					-- O(1) owner lookup via buffer variable set on TermOpen
					local owner_tab = vim.b[buf].term_owner_tab
					if not owner_tab or not vim.api.nvim_tabpage_is_valid(owner_tab) then
						return
					end
					if vim.t[owner_tab].term_toggling then
						return
					end
					-- Skip if buffer is displayed in a current terminal window
					local wins = vim.t[owner_tab].term_winids
					if wins then
						for _, win in ipairs(wins) do
							if state.win_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
								return
							end
						end
					end
					-- Find the tab entry of this buffer within the owning tabpage
					local raw_order = vim.t[owner_tab].term_order
					if not raw_order then
						return
					end
					local order = state.migrate_term_order(raw_order)
					local gi = nil
					for i, entry in ipairs(order) do
						for _, b in ipairs(entry.bufs) do
							if b == buf then
								gi = i
								break
							end
						end
						if gi then break end
					end
					local tab_idx = vim.t[owner_tab].term_tab_idx
					if not gi or gi == (tab_idx or 1) then
						return
					end
					if order[gi].activity then
						return
					end
					order[gi].activity = true
					vim.b[buf].term_activity_flagged = true
					vim.t[owner_tab].term_order = order
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
			local bufnr = vim.api.nvim_get_current_buf()
			local winid = vim.api.nvim_get_current_win()
			vim.schedule(function()
				if vim.t.term_overlay_refocus then
					return
				end
				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end
				if vim.api.nvim_get_current_win() ~= winid then
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
			state.adopt_current_terminal()

			-- Track focus within pane windows
			local current_win = vim.api.nvim_get_current_win()
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
					if state.set_activity(current_tab_idx, false) then
						winbar.update()
					end
					break
				end
			end

			-- Refocus terminal pane if winbar overlay is entered
			if current_win == vim.t.term_winbar_winid then
				local target = get_term_refocus_target()
				local target_mode = mode.of_win(target)
				refocus_term_overlay(current_win, target, target_mode)
			end

			-- Refocus terminal pane if statusline overlay is entered
			local stl_buf_ok, stl_buf = pcall(vim.api.nvim_win_get_buf, current_win)
			if stl_buf_ok and vim.b[stl_buf].terminal_stl then
				local stl_pane = vim.b[stl_buf].terminal_stl_pane
				local target_mode = mode.of_win(stl_pane)
				refocus_term_overlay(current_win, stl_pane, target_mode, function()
					statusline.update()
				end)
			end

		end,
	})
	-- Plugins like Telescope return focus to the previous window (the
	-- term pane) and run :edit, which loads the file buffer into the
	-- pane. Detect this and re-route: restore the terminal buffer in
	-- the pane, and open the foreign buffer in a real window.
	vim.api.nvim_create_autocmd("BufWinEnter", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local buf = ev.buf
			if not vim.api.nvim_buf_is_valid(buf) then return end
			if vim.bo[buf].buftype == "terminal" then return end

			local win = vim.api.nvim_get_current_win()
			local wins = vim.t.term_winids or {}
			local pane_idx
			for i, w in ipairs(wins) do
				if w == win then pane_idx = i; break end
			end
			if not pane_idx then return end

			local tab = state.get_current_tab()
			if not tab or not tab.bufs[pane_idx] then return end
			local term_buf = tab.bufs[pane_idx]

			local function find_target()
				local prev = vim.t.prev_winid
				if state.win_valid(prev) and not state.is_term_related_window(prev) then
					local ok, cfg = pcall(vim.api.nvim_win_get_config, prev)
					if ok and cfg.relative == "" then return prev end
				end
				for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
					if state.win_valid(w) and not state.is_term_related_window(w) then
						local ok, cfg = pcall(vim.api.nvim_win_get_config, w)
						if ok and cfg.relative == "" then return w end
					end
				end
				return nil
			end
			local target = find_target()

			vim.schedule(function()
				if state.win_valid(win) and vim.api.nvim_buf_is_valid(term_buf) then
					pcall(vim.api.nvim_win_set_buf, win, term_buf)
				end
				if target and vim.api.nvim_buf_is_valid(buf) then
					pcall(vim.api.nvim_win_set_buf, target, buf)
					pcall(vim.api.nvim_set_current_win, target)
				end
			end)
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
			if not vim.t.term_toggling and config.is_float_mode() and state.is_term_related_window(vim.api.nvim_get_current_win()) then
				local tab = vim.api.nvim_get_current_tabpage()
				vim.schedule(function()
					if vim.api.nvim_get_current_tabpage() ~= tab then
						return
					end
					local cur_win = vim.api.nvim_get_current_win()
					if not state.is_term_related_window(cur_win) then
						local ok, cfg = pcall(vim.api.nvim_win_get_config, cur_win)
						local is_float = ok and cfg.relative ~= ""
						if not (vim.t.term_zoom and is_float) then
							api.toggle({ open = false })
						end
					end
				end)
			end
		end,
	})

	local function update_float_win_config()
		if not config.is_float_mode() or not state.is_term_open() then
			return
		end
		-- Skip rebuild when the app window is too small to fit the zoom
		-- layout. Neovim auto-clamps existing floats to stay within the
		-- screen bounds, so leaving them in place is safe; the next resize
		-- back to a normal size will rebuild cleanly.
		if not window.can_rebuild_float() then
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
				state.adopt_current_terminal()
				update_float_win_config()
				winbar.update()
				if vim.bo.buftype == "terminal" then
					mode.restore_current()
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
			local was_winbar_visible = config.should_show_winbar(#state.get_tabs())
			local tab_idx_closed = state.find_buf_tab(bufnr)

			local current_tab_idx = vim.t.term_tab_idx or 1
			local is_in_active_tab = tab_idx_closed == current_tab_idx

			local is_displayed = is_in_active_tab and state.is_term_open()

			state.remove_term_from_order(bufnr)
			bufname.clear(bufnr)
			local is_winbar_visible = config.should_show_winbar(#state.get_tabs())
			local winbar_visibility_changed = was_winbar_visible ~= is_winbar_visible

			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end

				if is_displayed or (winbar_visibility_changed and state.is_term_open()) then
					window.rebuild_tab()
				else
					winbar.update()
				end
			end)
		end,
	})

	if config.config.winbar then
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
	end

	vim.api.nvim_create_autocmd("TermRequest", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local seq = ev.data.sequence

			if seq:match("^\x1b%]0;") then
				local title = seq:match("\x1b%]0;([^\007]+)")
				if title then title = title:match("^%s*(.-)%s*$") end
				if title and #title > 0 then
					local buf = ev.buf
					vim.b[buf].term_title = title
					bufname.set_from_title(buf, title)
					winbar.update()
					statusline.update()
				end
			end
		end,
	})
end

return M
