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
local activity = require("terminal.activity")

local pending_title_bufs = {}
local title_update_scheduled = false
local title_update_delay = 100

local function schedule_title_update(bufnr)
	pending_title_bufs[bufnr] = true
	if title_update_scheduled then
		return
	end
	title_update_scheduled = true

	vim.defer_fn(function()
		title_update_scheduled = false
		local pending = pending_title_bufs
		pending_title_bufs = {}
		local refresh_overlays = false
		local current_tab = vim.api.nvim_get_current_tabpage()

		for buf in pairs(pending) do
			if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
				local title = vim.b[buf].term_title
				if title and title:match("%S") then
					title = title:match("^%s*(.-)%s*$")
					if vim.b[buf].term_title_handled ~= title then
						vim.b[buf].term_title_handled = title
						bufname.set_from_title(buf, title)
						if vim.b[buf].term_owner_tab == current_tab then
							refresh_overlays = true
						end
					end
				end
			end
		end

		if refresh_overlays then
			winbar.update()
			statusline.update()
		end
	end, title_update_delay)
end

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
	if not state.win_valid(target_win) then return end
	local view = state.capture_view(target_win)
	local token = (vim.t.term_refocus_generation or 0) + 1
	vim.t.term_refocus_generation = token
	vim.t.term_overlay_refocus = true
	vim.schedule(function()
		if state.view_matches(view) and vim.api.nvim_get_current_win() == overlay_win then
			vim.api.nvim_set_current_win(target_win)
			mode.restore_scheduled(target_win, target_mode)
			if after then after() end
		end
		vim.schedule(function()
			if vim.api.nvim_tabpage_is_valid(view.tab) and vim.t[view.tab].term_refocus_generation == token then
				vim.t[view.tab].term_overlay_refocus = nil
			end
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
			if vim.b[bufnr].terminal_job_runner then return end
			local was_winbar_visible = config.should_show_winbar(#state.get_tabs())
			local known_tab = state.find_buf_tab(bufnr)
			if not known_tab then
				state.add_term_to_order(bufnr)
			end
			vim.b.term_mode = "t"
			local owner_tab = vim.api.nvim_get_current_tabpage()
			vim.b[bufnr].term_owner_tab = owner_tab
			float_layout.setup_mouse_mappings(bufnr, api)

			local is_winbar_visible = config.should_show_winbar(#state.get_tabs())
			if was_winbar_visible ~= is_winbar_visible and state.is_term_open() and not vim.t.term_toggling then
				state.defer_view(state.capture_view(), function()
					if state.is_term_open() then
						window.rebuild_tab()
					else
						winbar.update()
					end
				end)
			end

			vim.schedule(function()
				activity.sync(owner_tab)
			end)
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
			state.defer_view(state.capture_view(winid), function()
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
			-- Drawer height is the span over all panes, not the first pane's
			-- height (stacked panes are shorter than the drawer)
			if not config.is_float_mode() then
				local span = state.drawer_span()
				if span and span > 0 then
					vim.t.term_height = span
				end
			end
			-- Save pane sizes into the layout tree when the user resizes
			if #wins >= 2 then
				window.save_layout_sizes()
			end
			winbar.update()
		end,
	})
	vim.api.nvim_create_autocmd("WinEnter", {
		pattern = "*",
		group = "Term",
		callback = function()
			state.adopt_current_terminal()
			if state.is_in_term_window() and vim.bo.buftype == "terminal" then
				bufname.sync(vim.api.nvim_get_current_buf())
			end

			-- Track focus within pane windows. Skip while toggling:
			-- closing panes shifts focus through the survivors, and a
			-- winbar.update() here would recreate the overlay anchored to
			-- a window that is about to close (leaving it stranded at the
			-- top of the screen).
			if vim.t.term_toggling then
				return
			end
			local current_win = vim.api.nvim_get_current_win()
			local wins = vim.t.term_winids or {}
			for _, win in ipairs(wins) do
				if win == current_win then
					local old_winid = vim.t.term_winid
					if old_winid and old_winid ~= current_win then
						vim.t.term_prev_pane_winid = old_winid
					end
					local old_bufnr = vim.t.term_bufnr
					vim.t.term_winid = current_win
					vim.t.term_bufnr = vim.api.nvim_win_get_buf(current_win)

					-- Clear activity; refresh the winbar when the focused
					-- pane changed (the tab title follows the focused pane)
					local current_tab_idx = vim.t.term_tab_idx or 1
					local activity_changed = state.set_activity(current_tab_idx, false)
					if activity_changed or vim.t.term_bufnr ~= old_bufnr then
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
			local target_buf = target and vim.api.nvim_win_get_buf(target)
			state.defer_view(state.capture_view(win), function()
				if vim.api.nvim_get_current_win() ~= win or not vim.api.nvim_buf_is_valid(term_buf)
					or not state.win_valid(target) or vim.api.nvim_win_get_buf(target) ~= target_buf then return end
				vim.api.nvim_win_set_buf(win, term_buf)
				vim.api.nvim_win_set_buf(target, buf)
				vim.api.nvim_set_current_win(target)
			end)
		end,
	})
	vim.api.nvim_create_autocmd("TabNew", {
		pattern = "*",
		group = "Term",
		callback = function()
			vim.t.term_height = config.get_term_height()
			state.init_tab_options()
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
				state.defer_view(state.capture_view(), function()
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
			state.sync_zoom_options()
			state.defer_view(state.capture_view(), function()
				state.adopt_current_terminal()
				if vim.t.term_needs_rebuild then
					state.set_toggling()
					if window.rebuild_tab() then vim.t.term_needs_rebuild = nil end
				else
					update_float_win_config()
				end
				winbar.update()
				if vim.bo.buftype == "terminal" then
					mode.restore_current()
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("TabLeave", {
		group = "Term",
		callback = state.leave_tab,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = "Term",
		callback = function()
			state.defer_view(state.capture_view(), state.sync_zoom_options)
		end,
	})
	vim.api.nvim_create_autocmd("TabClosed", {
		group = "Term",
		callback = function()
			state.defer_view(state.capture_view(), function()
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
			if vim.b[bufnr].terminal_job_runner then return end
			local owner = vim.b[bufnr].term_owner_tab
			if not owner or not vim.api.nvim_tabpage_is_valid(owner) then
				return
			end
			local vars = vim.t[owner]
			local was_winbar_visible = config.should_show_winbar(#state.get_tabs(owner))
			local is_displayed, is_open = false, false
			for _, win in ipairs(vars.term_winids or {}) do
				if state.win_valid(win) then
					is_open = true
					is_displayed = is_displayed or vim.api.nvim_win_get_buf(win) == bufnr
				end
			end

			state.remove_term_from_order(bufnr, owner)
			local is_winbar_visible = config.should_show_winbar(#state.get_tabs(owner))
			local rebuild = is_displayed or (was_winbar_visible ~= is_winbar_visible and is_open)

			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end

				if not vim.api.nvim_tabpage_is_valid(owner) then
					return
				end
				if vim.api.nvim_get_current_tabpage() ~= owner then
					-- Never rebuild whichever tab happens to be current when
					-- this callback runs. Repair the owner when it is entered.
					if rebuild then vim.t[owner].term_needs_rebuild = true end
					return
				end
				if rebuild then
					state.set_toggling()
					window.rebuild_tab()
				else
					winbar.update()
				end
			end)
		end,
	})

	if config.config.winbar then
		vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter" }, {
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
			if ev.data.sequence:match("^\x1b%][02];") then
				schedule_title_update(ev.buf)
			end
		end,
	})
end

return M
