-- Follow terminal output and preserve the mode across wheel-scrollback.
local M = {}
local pending = false
local attached = {}
local paused = {}
local follow_enabled = {}
local wheel_down = {}
local wheel_insert = {}
local menu_target
local menu_source
local menu_mode

local function live_top(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local height = vim.api.nvim_win_get_height(win) - (vim.wo[win].winbar ~= "" and 1 or 0)
	return math.max(1, vim.api.nvim_buf_line_count(buf) - height + 1)
end

function M.is_following(win)
	if not win or not vim.api.nvim_win_is_valid(win) then return false end
	if not require("terminal.state").is_managed(vim.api.nvim_win_get_buf(win)) then return false end
	if paused[win] ~= nil then return not paused[win] end
	local buf = vim.api.nvim_win_get_buf(win)
	return follow_enabled[win] == buf or vim.b[buf].term_mode == "t"
end

function M.is_wheel_paused(win)
	return paused[win] == true and wheel_insert[win] == vim.api.nvim_win_get_buf(win)
end

function M.restore_wheel_view(win, view)
	paused[win], wheel_down[win], wheel_insert[win] = true, nil, vim.api.nvim_win_get_buf(win)
	vim.api.nvim_win_call(win, function() vim.fn.winrestview(view) end)
end

function M.on_normal_mode(win)
	if wheel_insert[win] ~= vim.api.nvim_win_get_buf(win) then
		paused[win], wheel_down[win], wheel_insert[win] = nil, nil, nil
		follow_enabled[win] = nil
	end
end

local function scroll_to_live(win)
	local top = live_top(win)
	local cursor = vim.api.nvim_win_get_cursor(win)
	if cursor[1] < top then vim.api.nvim_win_set_cursor(win, { top, cursor[2] }) end
	vim.api.nvim_win_call(win, function() vim.fn.winrestview({ topline = top, leftcol = 0 }) end)
end

function M.set_following(win, enabled)
	if not win or not vim.api.nvim_win_is_valid(win) then return end
	paused[win] = not enabled or nil
	follow_enabled[win] = enabled and vim.api.nvim_win_get_buf(win) or nil
	if enabled then scroll_to_live(win) end
end

local function mouse_pane(win, include_focused_terminal)
	-- Keep focused Terminal-mode clicks on Neovim's native path.
	if not include_focused_terminal and win == vim.api.nvim_get_current_win()
		and vim.api.nvim_get_mode().mode == "t" then return end
	for _, pane in ipairs(vim.t.term_winids or {}) do
		if pane == win and vim.api.nvim_win_is_valid(win)
			and require("terminal.state").is_managed(vim.api.nvim_win_get_buf(win)) then return win end
	end
end

local function resume_after_wheel(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local restore_insert = wheel_insert[win] == buf
	local focused = vim.api.nvim_get_current_win() == win
	wheel_down[win] = nil
	if not focused and (restore_insert or follow_enabled[win] == buf or vim.b[buf].term_mode == "t") then
		if restore_insert then vim.b[buf].term_mode = "t" end
		paused[win], wheel_insert[win] = nil, nil
		return
	end
	if focused and vim.api.nvim_get_mode().mode == "t" then
		paused[win], wheel_insert[win] = nil, nil
		return
	end
	paused[win] = not (focused and restore_insert)
	if paused[win] then return end
	vim.schedule(function()
		if wheel_insert[win] == buf and vim.api.nvim_get_current_win() == win and vim.api.nvim_get_current_buf() == buf
			and vim.api.nvim_get_mode().mode:sub(1, 1) == "n" and not paused[win]
			and vim.fn.winsaveview().topline >= live_top(win) then
			wheel_insert[win] = nil
			require("terminal.mode").restore(win, "t")
		end
	end)
end

function M.focus_terminal(win, buf)
	if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf
		or not require("terminal.state").is_managed(buf) then return end
	local mode = require("terminal.mode")
	mode.record()
	vim.api.nvim_set_current_win(win)
	scroll_to_live(win)
	paused[win], wheel_down[win], wheel_insert[win] = nil, nil, nil
	mode.restore(win, "t")
end

function M.finish_wheel_page(win)
	scroll_to_live(win)
	resume_after_wheel(win)
end

function M.on_left_mouse(mouse)
	local win = mouse_pane(mouse.winid)
	if not win or mouse.line == 0 or M.is_wheel_paused(win) then return end
	local buf = vim.api.nvim_win_get_buf(win)
	if (win ~= vim.api.nvim_get_current_win() or paused[win]) and vim.b[buf].term_mode == "t" then
		-- Focus outside the expression mapping's textlock, before mouse-up.
		return string.format('<Cmd>lua require("terminal.follow").focus_terminal(%d,%d)<CR>', win, buf)
	end
end

function M.toggle_menu_follow()
	M.set_following(menu_target, not M.is_following(menu_target))
	if vim.api.nvim_get_current_win() == menu_source then
		require("terminal.mode").restore_scheduled(menu_source, menu_mode)
	end
end

function M.enter_menu_terminal()
	local win = vim.api.nvim_get_current_win()
	if win ~= menu_target or win ~= menu_source or not require("terminal.state").is_managed() then return end
	scroll_to_live(win)
	require("terminal.mode").restore(win, "t")
end

local function show_menu(win, source, source_mode)
	if not vim.api.nvim_win_is_valid(win) then return end
	menu_target = win
	menu_source, menu_mode = source, source_mode
	if next(vim.fn.menu_info("TerminalFollow")) then
		vim.cmd("aunmenu TerminalFollow")
		vim.cmd("tlunmenu TerminalFollow")
	end
	local label, action
	if win == source then
		label, action = "Enter terminal mode", "enter_menu_terminal"
	else
		local mark = M.is_following(win) and "[x]" or "[ ]"
		label, action = mark .. " Follow output", "toggle_menu_follow"
	end
	local item = "TerminalFollow." .. label:gsub(" ", "\\ ")
	local command = " <Cmd>lua require('terminal.follow')." .. action .. "()<CR>"
	vim.cmd("anoremenu " .. item .. command)
	-- :amenu excludes Terminal mode; define it explicitly to avoid E335.
	vim.cmd("tlnoremenu " .. item .. command)
	vim.cmd("popup! TerminalFollow")
end

function M.setup(bufnr)
	local function map(_, key, callback, opts)
		-- Normal-mode mouse handling is needed when hovering an inactive
		-- pane from the editor. Respect existing user mappings. Terminal-mode
		-- handling is installed only on our own buffers.
		if not bufnr and vim.fn.maparg(key, "n") ~= "" then return end
		opts = vim.tbl_extend("force", {}, opts, bufnr and { buffer = bufnr } or {})
		vim.keymap.set(bufnr and "t" or "n", key, callback, opts)
	end
	for _, key in ipairs({
		"<ScrollWheelUp>", "<ScrollWheelDown>",
		"<S-ScrollWheelUp>", "<S-ScrollWheelDown>",
		"<C-ScrollWheelUp>", "<C-ScrollWheelDown>",
	}) do
		local down = key:find("Down", 1, true) ~= nil
		map({ "n", "t" }, key, function()
			local mouse = vim.fn.getmousepos()
			if mouse.winid == vim.t.term_winbar_winid then
				if key ~= "<ScrollWheelUp>" and key ~= "<ScrollWheelDown>" then return key end
				local state = require("terminal.state")
				local delta = down and 1 or -1
				state.defer_view(state.capture_view(), function()
					require("terminal").switch(delta, true)
				end)
				return ""
			end
			local win = mouse_pane(mouse.winid, true)
			if win then
				local mouse_input = require("terminal.mouse")
				local buf = vim.api.nvim_win_get_buf(win)
				local focused_insert = win == vim.api.nvim_get_current_win()
					and vim.api.nvim_get_mode().mode == "t"
				if focused_insert and mouse_input.is_reporting(buf) ~= false then return key end
				local direction = down and "<ScrollWheelDown>" or "<ScrollWheelUp>"
				if not focused_insert and M.is_following(win) and mouse_input.wheel(win, direction, mouse) then
					return ''
				end
				-- Without scrollback, wheel-up cannot leave the live screen.
				if not down and live_top(win) == 1 then return "" end
				-- Don't let native wheel scrolling overshoot the live screen
				-- and then visibly snap back on every further wheel event.
				local last_page = false
				if down then
					local remaining = live_top(win) - vim.api.nvim_win_call(win, vim.fn.winsaveview).topline
					if remaining == 0 or (remaining < 0 and key ~= "<S-ScrollWheelDown>") then
						resume_after_wheel(win)
						return ""
					end
					last_page = key == "<S-ScrollWheelDown>" and remaining <= vim.api.nvim_win_get_height(win)
				end
				if focused_insert or (win ~= vim.api.nvim_get_current_win() and vim.b[buf].term_mode == "t") then
					wheel_insert[win] = buf
				end
				paused[win] = true
				wheel_down[win] = down or nil
				if last_page then
					-- Apply the final partial page after the expression mapping returns.
					return ("<Cmd>lua require('terminal.follow').finish_wheel_page(%d)<CR>"):format(win)
				end
				-- Scroll the buffer using Neovim's Normal-mode wheel handling.
				if focused_insert then return "<C-\\><C-n>" .. key end
			end
			return key
		end, { expr = true, noremap = true })
	end
	for _, key in ipairs({ "<S-ScrollWheelLeft>", "<S-ScrollWheelRight>" }) do
		map({ "n", "t" }, key, function()
			if mouse_pane(vim.fn.getmousepos().winid, true) then return "" end
			return key
		end, { expr = true, noremap = true })
	end
	if bufnr then
		for _, key in ipairs({ "<ScrollWheelLeft>", "<ScrollWheelRight>" }) do
			map("t", key, function()
				-- A diagonal wheel gesture can include a horizontal event even
				-- when horizontal scrolling is disabled. Neovim still exits Terminal mode.
				if vim.o.mousescroll:match("hor:0%f[%D]")
					and vim.fn.getmousepos().winid == vim.api.nvim_get_current_win()
					and require("terminal.mouse").is_reporting(bufnr) == false then
					return ""
				end
				return key
			end, { expr = true, noremap = true })
		end
	end
	if not bufnr then
		vim.on_key(function(_, typed)
			if typed == "" or not next(wheel_insert) then return end
			local win = vim.api.nvim_get_current_win()
			if wheel_insert[win] ~= vim.api.nvim_get_current_buf() then return end
			-- Inspect the original input: wheel-up itself maps to a mode switch.
			-- Neovim can report several wheel events together after a mapping.
			local key = vim.fn.keytrans(typed):gsub("<[%w%-]*ScrollWheel%a+>", "")
			-- A release can finish the click that brought this pane into focus.
			if key == "" or key == "<MouseMove>"
				or key:match("Release>$") or key:match("Drag>$") then return end
			if key:match("Mouse>$") then
				if vim.fn.getmousepos().winid ~= win then return end
			elseif vim.fn.maparg(key, "t") ~= "" then
				-- Terminal shortcuts also work while browsing scrollback.
				return
			end
			wheel_insert[win] = nil
			M.on_normal_mode(win)
			vim.b.term_mode = "n"
		end, vim.api.nvim_create_namespace("terminal.wheel_scrollback"))
		vim.api.nvim_create_autocmd("WinScrolled", {
			group = "Term",
			callback = function()
				for win in pairs(wheel_down) do
					if not vim.api.nvim_win_is_valid(win) then
						paused[win], wheel_down[win], wheel_insert[win] = nil, nil, nil
					elseif vim.api.nvim_win_call(win, vim.fn.winsaveview).topline >= live_top(win) then
						scroll_to_live(win)
						resume_after_wheel(win)
					end
				end
			end,
		})
		vim.api.nvim_create_autocmd("WinClosed", {
			group = "Term",
			callback = function(ev)
				local win = tonumber(ev.match)
				paused[win], wheel_down[win], wheel_insert[win] = nil, nil, nil
				follow_enabled[win] = nil
			end,
		})
		vim.api.nvim_create_autocmd("TermEnter", {
			group = "Term",
			callback = function()
				if not require("terminal.state").is_managed() then return end
				local win = vim.api.nvim_get_current_win()
				if paused[win] then scroll_to_live(win) end
				paused[win], wheel_down[win], wheel_insert[win] = nil, nil, nil
			end,
		})
	end
	for _, prefix in ipairs({ "", "2-", "3-", "4-" }) do
		local press, release = "<" .. prefix .. "LeftMouse>", "<" .. prefix .. "LeftRelease>"
		map({ "n", "t" }, press, function()
			local mouse = vim.fn.getmousepos()
			local native = require('terminal.mouse').on_left_mouse(mouse, press)
			if native then return native end
			return M.on_left_mouse(mouse) or press
		end, { expr = true, noremap = true })
		map({ "n", "t" }, release, function()
			local captured = require('terminal.mouse').continue_gesture(vim.fn.getmousepos(), 'release')
			if captured then return captured end
			return release
		end, { expr = true, noremap = true })
	end
	local function right_mouse(key)
		local win = mouse_pane(vim.fn.getmousepos().winid)
		if not win then return key end
		local source = vim.api.nvim_get_current_win()
		local source_mode = require("terminal.mode").record()
		vim.schedule(function() show_menu(win, source, source_mode) end)
		return ""
	end
	for _, key in ipairs({ "<RightMouse>", "<2-RightMouse>", "<3-RightMouse>", "<4-RightMouse>" }) do
		map({ "n", "t" }, key, function() return right_mouse(key) end, { expr = true, noremap = true })
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
				if require("terminal.state").is_managed(buf) and M.is_following(win) then
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

local function should_follow(win)
	if win == vim.api.nvim_get_current_win() then
		return vim.api.nvim_get_mode().mode == "t"
	end
	return M.is_following(win)
end

local function preserve_bottom_view(buf, growth)
	if growth <= 0 then return end
	local old_last = vim.api.nvim_buf_line_count(buf) - growth
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if not should_follow(win) and vim.api.nvim_win_get_cursor(win)[1] == old_last then
			-- on_lines runs before Neovim moves an EOF cursor to the new last
			-- line. Keep G's position and undo only that automatic movement.
			local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
			vim.schedule(function()
				if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf
					or should_follow(win) then return end
				local last = vim.api.nvim_buf_line_count(buf)
				if last > old_last and vim.api.nvim_win_get_cursor(win)[1] == last then
					vim.api.nvim_win_call(win, function() vim.fn.winrestview(view) end)
				end
			end)
		end
	end
end

function M.attach(buf)
	if attached[buf] then return end
	attached[buf] = vim.api.nvim_buf_attach(buf, false, {
		on_lines = function(_, _, _, _, last, new_last)
			preserve_bottom_view(buf, new_last - last)
			M.schedule()
		end,
		on_detach = function()
			attached[buf] = nil
			require('terminal.mouse').detach(buf)
		end,
	}) or nil
end

return M
