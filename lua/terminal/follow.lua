-- Follow inactive terminal output until the user scrolls back or pauses it.
local M = {}
local pending = false
local attached = {}
local paused = {}
local wheel_down = {}
local menu_target
local menu_source
local menu_mode
local clicked_pane

local function live_top(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local height = vim.api.nvim_win_get_height(win) - (vim.wo[win].winbar ~= "" and 1 or 0)
	return math.max(1, vim.api.nvim_buf_line_count(buf) - height + 1)
end

function M.is_following(win)
	if not win or not vim.api.nvim_win_is_valid(win) then return false end
	if paused[win] ~= nil then return not paused[win] end
	return vim.b[vim.api.nvim_win_get_buf(win)].term_mode == "t"
end

local function scroll_to_live(win)
	local top = live_top(win)
	local cursor = vim.api.nvim_win_get_cursor(win)
	if cursor[1] < top then vim.api.nvim_win_set_cursor(win, { top, cursor[2] }) end
	vim.api.nvim_win_call(win, function() vim.fn.winrestview({ topline = top, leftcol = 0 }) end)
end

function M.set_following(win, enabled)
	if not win or not vim.api.nvim_win_is_valid(win) then return end
	paused[win] = not enabled
	if enabled then scroll_to_live(win) end
end

local function mouse_pane()
	local win = vim.fn.getmousepos().winid
	-- Let Neovim route input to mouse-aware applications in the focused
	-- terminal. Inactive panes still use native scrollback navigation.
	if win == vim.api.nvim_get_current_win() and vim.api.nvim_get_mode().mode == "t" then return end
	for _, pane in ipairs(vim.t.term_winids or {}) do
		if pane == win and vim.api.nvim_win_is_valid(win) then return win end
	end
end

function M.on_left_mouse(mouse)
	if paused[mouse.winid] and vim.api.nvim_win_is_valid(mouse.winid)
		and vim.b[vim.api.nvim_win_get_buf(mouse.winid)].term_mode == "t" then
		clicked_pane = mouse.winid
	end
	return false
end

function M.on_left_release()
	if clicked_pane then
		local win = clicked_pane
		clicked_pane = nil
		vim.schedule(function()
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() == win then
				require("terminal.mode").restore_scheduled(win, "t")
			end
		end)
	end
	return false
end

function M.toggle_menu_follow()
	M.set_following(menu_target, not M.is_following(menu_target))
	if vim.api.nvim_get_current_win() == menu_source then
		require("terminal.mode").restore_scheduled(menu_source, menu_mode)
	end
end

local function show_menu(win, source, source_mode)
	if not vim.api.nvim_win_is_valid(win) then return end
	menu_target = win
	menu_source, menu_mode = source, source_mode
	if next(vim.fn.menu_info("TerminalFollow")) then
		vim.cmd("aunmenu TerminalFollow")
		vim.cmd("tlunmenu TerminalFollow")
	end
	local mark = M.is_following(win) and "[x]" or "[ ]"
	local item = "TerminalFollow." .. mark:gsub(" ", "\\ ") .. "\\ Follow\\ output"
	local action = " <Cmd>lua require('terminal.follow').toggle_menu_follow()<CR>"
	vim.cmd("anoremenu " .. item .. action)
	-- :amenu excludes Terminal mode; define it explicitly to avoid E335.
	vim.cmd("tlnoremenu " .. item .. action)
	vim.cmd("popup! TerminalFollow")
end

function M.setup()
	for _, key in ipairs({ "<ScrollWheelUp>", "<ScrollWheelDown>" }) do
		vim.keymap.set({ "n", "t" }, key, function()
			local win = mouse_pane()
			if win then
				-- Don't let native wheel scrolling overshoot the live screen
				-- and then visibly snap back on every further wheel event.
				if key == "<ScrollWheelDown>"
					and vim.api.nvim_win_call(win, vim.fn.winsaveview).topline >= live_top(win) then
					paused[win], wheel_down[win] = false, nil
					return ""
				end
				paused[win] = true
				wheel_down[win] = key == "<ScrollWheelDown>" or nil
			end
			return key
		end, { expr = true, noremap = true })
	end
	vim.api.nvim_create_autocmd("WinScrolled", {
		group = "Term",
		callback = function()
			for win in pairs(wheel_down) do
				if not vim.api.nvim_win_is_valid(win) then
					paused[win], wheel_down[win] = nil, nil
				elseif vim.api.nvim_win_call(win, vim.fn.winsaveview).topline >= live_top(win) then
					paused[win], wheel_down[win] = nil, nil
					M.set_following(win, true)
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = "Term",
		callback = function(ev)
			local win = tonumber(ev.match)
			paused[win], wheel_down[win] = nil, nil
		end,
	})
	vim.api.nvim_create_autocmd("TermEnter", {
		group = "Term",
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if paused[win] then M.set_following(win, true) end
			paused[win], wheel_down[win] = nil, nil
		end,
	})
	for _, prefix in ipairs({ "", "2-", "3-", "4-" }) do
		local press, release = "<" .. prefix .. "LeftMouse>", "<" .. prefix .. "LeftRelease>"
		vim.keymap.set({ "n", "t" }, press, function()
			return M.on_left_mouse(vim.fn.getmousepos()) and "" or press
		end, { expr = true, noremap = true })
		vim.keymap.set({ "n", "t" }, release, function()
			return M.on_left_release() and "" or release
		end, { expr = true, noremap = true })
	end
	local function right_mouse(key)
		local win = mouse_pane()
		if not win then return key end
		local source = vim.api.nvim_get_current_win()
		local source_mode = require("terminal.mode").record()
		vim.schedule(function() show_menu(win, source, source_mode) end)
		return ""
	end
	for _, key in ipairs({ "<RightMouse>", "<2-RightMouse>", "<3-RightMouse>", "<4-RightMouse>" }) do
		vim.keymap.set({ "n", "t" }, key, function() return right_mouse(key) end, { expr = true, noremap = true })
	end
end

function M.schedule()
	if pending then return end
	pending = true
	vim.schedule(function()
		pending = false
		local current = vim.api.nvim_get_current_win()
		for _, win in ipairs(vim.t.term_winids or {}) do
			if win ~= current and vim.api.nvim_win_is_valid(win) then
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].buftype == "terminal" and M.is_following(win) then
					-- The terminal screen is the final window-height lines of the
					-- buffer, including blank rows below the application's cursor.
					-- Keep the buffer cursor within that screen without forcing it
					-- to the last row: its position also guides native pane navigation.
					scroll_to_live(win)
				end
			end
		end
	end)
end

function M.attach(buf)
	if attached[buf] then return end
	attached[buf] = vim.api.nvim_buf_attach(buf, false, {
		on_lines = function() M.schedule() end,
		on_detach = function() attached[buf] = nil end,
	}) or nil
end

return M
