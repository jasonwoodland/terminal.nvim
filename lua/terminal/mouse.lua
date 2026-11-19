-- Mouse reporting for hovered terminal panes. Neovim only forwards mouse
-- events to the focused terminal and does not expose its reporting modes.
local M = {}
local trackers = {}
local gesture
local tracked = { [9] = true, [1000] = true, [1002] = true, [1003] = true,
	[1005] = true, [1006] = true, [1015] = true, [1016] = true }

local function set_mode(tracker, mode, enabled)
	tracker.modes[mode] = enabled
	-- These mode families are exclusive: the last set/reset selects the
	-- tracking policy or wire encoding, as in the terminal emulator.
	if mode == 9 or mode == 1000 or mode == 1002 or mode == 1003 then
		tracker.tracking = enabled and mode or nil
	else
		tracker.format = enabled and mode or nil
	end
end

local function csi(tracker, sequence)
	local params, action = sequence:match('^%?([%d;]+)([hlsr])$')
	if not params then return end
	for value in params:gmatch('%d+') do
		local mode = tonumber(value)
		if tracked[mode] then
			if action == 's' then tracker.saved[mode] = tracker.modes[mode] or false
			elseif action == 'r' then
				if tracker.saved[mode] ~= nil then set_mode(tracker, mode, tracker.saved[mode]) end
			else set_mode(tracker, mode, action == 'h') end
		end
	end
end

-- Parse only control sequences, skipping printable output and opaque strings.
-- State crosses stdout chunks; titles and DCS payloads must not change modes.
local function feed(tracker, data)
	local i = 1
	while i <= #data do
		local state = tracker.state
		if state == 'text' then
			local escape = data:find('\27', i, true)
			if not escape then return end
			i, tracker.state = escape + 1, 'escape'
		elseif state == 'string' then
			local stop = data:find(tracker.osc and '[\7\27]' or '\27', i)
			if not stop then return end
			tracker.state = data:byte(stop) == 7 and 'text' or 'string_escape'
			i = stop + 1
		else
			local char, byte = data:sub(i, i), data:byte(i)
			i = i + 1
			if state == 'escape' then
				if char == '[' then tracker.state, tracker.sequence = 'csi', ''
				elseif char == ']' or char == 'P' or char == '_' or char == '^' or char == 'X' then
					tracker.state, tracker.osc = 'string', char == ']'
				elseif char == 'c' then
					tracker.modes, tracker.saved, tracker.state = {}, {}, 'text'
					tracker.tracking, tracker.format = nil, nil
				elseif byte ~= 27 then tracker.state = 'text' end
			elseif state == 'string_escape' then
				tracker.state = char == '\\' and 'text' or (byte == 27 and 'string_escape' or 'string')
			elseif state == 'csi' then
				if byte == 27 then tracker.state = 'escape'
				elseif byte == 24 or byte == 26 then tracker.state = 'text'
				elseif byte >= 0x40 and byte <= 0x7e then
					csi(tracker, tracker.sequence .. char)
					tracker.state = 'text'
				elseif byte >= 0x20 then
					-- Bound storage even for malformed/incomplete output.
					tracker.sequence = #tracker.sequence < 256 and tracker.sequence .. char or '!'
				end
			end
		end
	end
end

function M.observe(buf)
	local tracker = { modes = {}, saved = {}, state = 'text' }
	trackers[buf] = tracker
	return function(_, data) feed(tracker, table.concat(data, '\n')) end
end

function M.detach(buf)
	trackers[buf] = nil
	if gesture and gesture.buf == buf then gesture = nil end
end

function M.is_reporting(buf)
	-- A terminal opened outside our launcher has no stdout observer.
	local tracker = trackers[buf]
	return tracker and tracker.tracking ~= nil
end

function M.on_left_mouse(mouse, key)
	gesture = nil
	local win = mouse.winid
	if not win or win == 0 or not vim.api.nvim_win_is_valid(win) or mouse.line == 0 then return end
	local buf = vim.api.nvim_win_get_buf(win)
	local tracker = trackers[buf]
	if not tracker or not tracker.tracking or vim.b[buf].term_mode ~= 't'
		or not require('terminal.state').is_managed(buf) then return end
	local pane = false
	for _, candidate in ipairs(vim.t.term_winids or {}) do
		if win == candidate then pane = true; break end
	end
	if not pane or require("terminal.follow").is_wheel_paused(win) then return end
	if win == vim.api.nvim_get_current_win() and vim.api.nvim_get_mode().mode ~= 't' then return end
	gesture = { win = win, buf = buf }
	if win == vim.api.nvim_get_current_win() then return end
	-- Expressions cannot change windows. Focus outside textlock, then replay
	-- the original key without remapping: Neovim owns the entire mouse gesture.
	return string.format('<Cmd>lua require("terminal.follow").focus_terminal(%d,%d)<CR>%s', win, buf, key)
end

function M.continue_gesture(mouse, action)
	if not gesture then return end
	local win, buf = gesture.win, gesture.buf
	if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf
		or vim.api.nvim_get_current_win() ~= win or vim.api.nvim_get_mode().mode ~= 't'
		or not trackers[buf] or not trackers[buf].tracking then
		gesture = nil
		return
	end
	local position = vim.api.nvim_win_get_position(win)
	local info = vim.fn.getwininfo(win)[1]
	local winbar = vim.wo[win].winbar ~= '' and 1 or 0
	local top = position[1] + winbar
	local left = position[2] + info.textoff
	local row = math.max(top, math.min(mouse.screenrow - 1, position[1] + vim.api.nvim_win_get_height(win) - 1))
	local col = math.max(left, math.min(mouse.screencol - 1, position[2] + vim.api.nvim_win_get_width(win) - 1))
	if row == mouse.screenrow - 1 and col == mouse.screencol - 1 then
		if action == 'release' then gesture = nil end
		return
	end
	-- Native terminal handling exits Terminal mode for events outside its
	-- window. Requeue at the nearest cell so its encoder and held-button
	-- state still handle the drag/release, including releases over overlays.
	local modifiers = vim.fn.getcharmod()
	local mods = (bit.band(modifiers, 2) ~= 0 and 'S' or '')
		.. (bit.band(modifiers, 4) ~= 0 and 'C' or '')
		.. (bit.band(modifiers, 8) ~= 0 and 'A' or '')
	vim.api.nvim_input_mouse('left', action, mods, 0, row, col)
	return ''
end

function M.wheel(win, key, mouse)
	local buf = vim.api.nvim_win_get_buf(win)
	local tracker = trackers[buf]
	if not tracker or vim.b[buf].term_mode ~= 't' then return false end
	if not tracker.tracking or tracker.tracking == 9 then return false end
	-- Pixel reporting needs pixel coordinates which getmousepos() cannot supply.
	if tracker.format == 1016 then return false end
	local position = vim.api.nvim_win_get_position(win)
	local info = vim.fn.getwininfo(win)[1]
	local col = mouse.screencol - position[2] - info.textoff
	local winbar = vim.wo[win].winbar ~= '' and 1 or 0
	local row = mouse.screenrow - position[1] - winbar
	if row < 1 or row > vim.api.nvim_win_get_height(win) - winbar or col < 1
		or col > vim.api.nvim_win_get_width(win) - info.textoff then return false end
	local button = key == '<ScrollWheelUp>' and 64 or 65
	local modifiers = vim.fn.getcharmod()
	if bit.band(modifiers, 2) ~= 0 then button = button + 4 end
	if bit.band(modifiers, 8) ~= 0 then button = button + 8 end
	if bit.band(modifiers, 4) ~= 0 then button = button + 16 end
	local sequence
	if tracker.format == 1006 then sequence = string.format('\27[<%d;%d;%dM', button, col, row)
	elseif tracker.format == 1015 then sequence = string.format('\27[%d;%d;%dM', button + 32, col, row)
	elseif tracker.format == 1005 then
		if col > 2015 or row > 2015 then return true end
		sequence = '\27[M' .. vim.fn.nr2char(button + 32) .. vim.fn.nr2char(col + 32) .. vim.fn.nr2char(row + 32)
	else
		if col > 223 or row > 223 then return true end
		sequence = '\27[M' .. string.char(button + 32, col + 32, row + 32)
	end
	local job = vim.b[buf].terminal_job_id
	if not job then return false end
	local ok, sent = pcall(vim.fn.chansend, job, sequence)
	return ok and sent > 0
end

return M
