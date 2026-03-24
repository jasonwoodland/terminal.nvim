-- terminal.nvim: float pane layout and draggable borders

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local winbar = require("terminal.winbar")
local statusline = require("terminal.statusline")

local drag_state = nil
local tabline_click_mode = nil
local stl_click = false

-- Apply widths to all float pane windows
function M.apply_float_pane_layout(widths)
	local wins = vim.t.term_winids or {}
	if #wins == 0 then
		return
	end

	local first_cfg = vim.api.nvim_win_get_config(wins[1])
	local col = first_cfg.col

	for i, win in ipairs(wins) do
		if state.win_valid(win) then
			local cfg = vim.api.nvim_win_get_config(win)
			cfg.col = col
			cfg.width = widths[i]
			vim.api.nvim_win_set_config(win, cfg)
		end
		-- Advance: pane 1 has no left border; panes 2+ have left border (+1)
		if i == 1 then
			col = col + widths[i]
		else
			col = col + 1 + widths[i]
		end
	end
	statusline.update()
end

function M.save_pane_widths()
	local wins = vim.t.term_winids or {}
	if #wins < 2 then
		return
	end
	local _, tab_idx = state.get_current_tab()
	if not tab_idx then
		return
	end
	local widths = {}
	for i, win in ipairs(wins) do
		if state.win_valid(win) then
			widths[i] = vim.api.nvim_win_get_width(win)
		end
	end
	local st = state.get_tab_state(tab_idx)
	st.widths = widths
	state.set_tab_state(tab_idx, st)
end

function M.equalize_panes()
	local wins = vim.t.term_winids or {}
	if #wins < 2 then
		return
	end
	local total = 0
	for _, win in ipairs(wins) do
		if state.win_valid(win) then
			total = total + vim.api.nvim_win_get_width(win)
		end
	end
	local widths = state.compute_equal_widths(total, #wins)
	if config.is_float_mode() then
		M.apply_float_pane_layout(widths)
	else
		for i, win in ipairs(wins) do
			if state.win_valid(win) then
				vim.api.nvim_win_set_width(win, widths[i])
			end
		end
	end
	M.save_pane_widths()
end

-- Resize pane_idx by delta, cascading to neighbors when they hit min width
function M.calc_resized_widths(widths, pane_idx, delta)
	local new_widths = {}
	for i, w in ipairs(widths) do
		new_widths[i] = w
	end

	if delta > 0 then
		-- Growing: take from right neighbors first, then left
		local remaining = delta
		for i = pane_idx + 1, #new_widths do
			local take = math.min(new_widths[i] - 1, remaining)
			if take > 0 then
				new_widths[i] = new_widths[i] - take
				remaining = remaining - take
			end
			if remaining <= 0 then
				break
			end
		end
		if remaining > 0 then
			for i = pane_idx - 1, 1, -1 do
				local take = math.min(new_widths[i] - 1, remaining)
				if take > 0 then
					new_widths[i] = new_widths[i] - take
					remaining = remaining - take
				end
				if remaining <= 0 then
					break
				end
			end
		end
		new_widths[pane_idx] = new_widths[pane_idx] + (delta - remaining)
	else
		-- Shrinking: take from left neighbors, give to right neighbor
		local remaining = -delta
		for i = pane_idx, 1, -1 do
			local take = math.min(new_widths[i] - 1, remaining)
			if take > 0 then
				new_widths[i] = new_widths[i] - take
				remaining = remaining - take
			end
			if remaining <= 0 then
				break
			end
		end
		local gave = -delta - remaining
		if pane_idx < #new_widths then
			new_widths[pane_idx + 1] = new_widths[pane_idx + 1] + gave
		elseif pane_idx > 1 then
			new_widths[pane_idx - 1] = new_widths[pane_idx - 1] + gave
		end
	end

	return new_widths
end

local function get_sep_screen_col(sep_idx)
	local wins = vim.t.term_winids or {}
	if sep_idx < 1 or sep_idx >= #wins then return nil end
	local win = wins[sep_idx]
	if not state.win_valid(win) then return nil end
	local cfg = vim.api.nvim_win_get_config(win)
	local width = vim.api.nvim_win_get_width(win)
	-- Right border position: for pane 1 (no left border) it's cfg.col + width
	-- For pane i>1 (has left border) it's cfg.col + 1 + width
	if sep_idx == 1 then
		return cfg.col + width
	else
		return cfg.col + 1 + width
	end
end

function M.setup_mouse_mappings(bufnr, api)
	for _, mode in ipairs({ "n", "t" }) do
		vim.api.nvim_buf_set_keymap(bufnr, mode, "<LeftMouse>", "", {
			noremap = true,
			expr = true,
			callback = function()
				local mouse = vim.fn.getmousepos()

				-- Track mode for tabline clicks so LeftRelease can restore it
				if mouse.screenrow == 1 and vim.o.showtabline > 0 then
					tabline_click_mode = vim.fn.mode()
				end

				-- Handle winbar click without changing focus/mode
				if mouse.winid == vim.t.term_winbar_winid then
					local col = mouse.column - 1
					for _, range in ipairs(winbar.get_click_ranges()) do
						if col >= range.start_col and col < range.end_col then
							vim.schedule(function()
								api.go_to(range.tab_idx)
							end)
							break
						end
					end
					return ""
				end

				-- Handle statusline overlay click without changing focus/mode
				if statusline.is_stl_window(mouse.winid) then
					local stl_buf = vim.api.nvim_win_get_buf(mouse.winid)
					local stl_pane = vim.b[stl_buf].terminal_stl_pane
					if stl_pane and state.win_valid(stl_pane) then
						vim.schedule(function()
							vim.api.nvim_set_current_win(stl_pane)
							local buf = vim.api.nvim_win_get_buf(stl_pane)
							local m = vim.b[buf].term_mode
							if m == "t" or m == nil then
								vim.cmd("startinsert")
							else
								vim.cmd("stopinsert")
							end
							statusline.update()
						end)
					end
					return ""
				end

				-- Handle native statusline click to preserve terminal mode
				if mouse.line == 0 and not config.is_float_mode() then
					local wins = vim.t.term_winids or {}
					for _, win in ipairs(wins) do
						if mouse.winid == win and state.win_valid(win) then
							stl_click = true
							vim.schedule(function()
								vim.api.nvim_set_current_win(win)
								local buf = vim.api.nvim_win_get_buf(win)
								local m = vim.b[buf].term_mode
								if m == "t" or m == nil then
									vim.cmd("startinsert")
								else
									vim.cmd("stopinsert")
								end
							end)
							return ""
						end
					end
				end

				if not config.is_float_mode() or not state.is_term_open() then
					return vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true)
				end
				local screencol = mouse.screencol - 1
				local wins = vim.t.term_winids or {}
				for i = 1, #wins - 1 do
					local sc = get_sep_screen_col(i)
					if sc and screencol == sc then
						drag_state = { sep_idx = i }
						-- Match Neovim's behaviour of exiting to normal mode when resizing
						vim.schedule(function()
							vim.cmd("stopinsert")
						end)
						return ""
					end
				end
				return vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true)
			end,
		})

		vim.api.nvim_buf_set_keymap(bufnr, mode, "<LeftDrag>", "", {
			noremap = true,
			expr = true,
			callback = function()
				local drag_mouse = vim.fn.getmousepos()
				if drag_mouse.winid == vim.t.term_winbar_winid or statusline.is_stl_window(drag_mouse.winid) or stl_click then
					return ""
				end
				if not drag_state then
					return vim.api.nvim_replace_termcodes("<LeftDrag>", true, true, true)
				end
				local mouse = vim.fn.getmousepos()
				local mouse_col = mouse.screencol - 1
				local pane_wins = vim.t.term_winids or {}
				if not pane_wins[drag_state.sep_idx] then return "" end
				if not state.win_valid(pane_wins[drag_state.sep_idx]) then return "" end

				local widths = {}
				for i, win in ipairs(pane_wins) do
					if state.win_valid(win) then
						widths[i] = vim.api.nvim_win_get_width(win)
					else
						return ""
					end
				end

				local current_sep_col = get_sep_screen_col(drag_state.sep_idx)
				if not current_sep_col then return "" end
				local delta = mouse_col - current_sep_col
				if delta == 0 then return "" end

				local new_widths = M.calc_resized_widths(widths, drag_state.sep_idx, delta)
				vim.schedule(function()
					M.apply_float_pane_layout(new_widths)
				end)
				return ""
			end,
		})

		for _, event in ipairs({
			"<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>",
			"<2-LeftRelease>", "<3-LeftRelease>", "<4-LeftRelease>",
			"<2-LeftDrag>", "<3-LeftDrag>", "<4-LeftDrag>",
		}) do
			vim.api.nvim_buf_set_keymap(bufnr, mode, event, "", {
				noremap = true,
				expr = true,
				callback = function()
					local ev_mouse = vim.fn.getmousepos()
					if ev_mouse.winid == vim.t.term_winbar_winid or statusline.is_stl_window(ev_mouse.winid) then
						return ""
					end
					return vim.api.nvim_replace_termcodes(event, true, true, true)
				end,
			})
		end

		vim.api.nvim_buf_set_keymap(bufnr, mode, "<LeftRelease>", "", {
			noremap = true,
			expr = true,
			callback = function()
				local rel_mouse = vim.fn.getmousepos()
				if rel_mouse.winid == vim.t.term_winbar_winid or statusline.is_stl_window(rel_mouse.winid) then
					return ""
				end
				if stl_click then
					stl_click = false
					return ""
				end
				if tabline_click_mode then
					local was_terminal = tabline_click_mode == "t"
					tabline_click_mode = nil
					if was_terminal and vim.bo.buftype == "terminal" and (vim.b.term_mode == "t" or vim.b.term_mode == nil) then
						vim.schedule(function()
							vim.cmd("startinsert")
						end)
					end
					return ""
				end
				if not drag_state then
					return vim.api.nvim_replace_termcodes("<LeftRelease>", true, true, true)
				end
				vim.schedule(function()
					M.save_pane_widths()
				end)
				drag_state = nil
				return ""
			end,
		})
	end
end

return M
