-- terminal.nvim: float pane layout — canvas separator renderer and draggable
-- separators.
--
-- Float panes are borderless windows positioned by the layout tree's rects.
-- Underneath them sits a single "canvas" float whose buffer holds the entire
-- separator artwork: the outer border (when configured), interior separators,
-- junction characters (from 'fillchars': vert/horiz/verthoriz/…), and the
-- title.

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local frame = require("terminal.frame")
local mode = require("terminal.mode")
local winbar = require("terminal.winbar")
local statusline = require("terminal.statusline")

local drag_state = nil
local tabline_click_mode = nil
local stl_click = false
local canvas_bufnr = nil

local string_borders = {
	rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
	single  = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
	double  = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
	solid   = { " ", " ", " ", " ", " ", " ", " ", " " },
	none    = { "", "", "", "", "", "", "", "" },
	shadow  = { "", "", "", "", "", "", "", "" },
}

local function resolve_border(b)
	if type(b) == "string" then
		return string_borders[b] or string_borders.none
	end
	if type(b) == "table" then
		return b
	end
	return string_borders.none
end

-- A border char spec may be "char" or {"char", "hl"}.
local function border_char(spec)
	if type(spec) == "table" then
		spec = spec[1]
	end
	if spec == nil or spec == "" then
		return nil
	end
	return spec
end

function M.has_border(base)
	return base.border ~= nil and base.border ~= "none" and border_char(resolve_border(base.border)[2]) ~= nil
end

-- Grid origin of the pane content area in editor cells.
function M.content_origin(base)
	local off = M.has_border(base) and 1 or 0
	return base.row + off, base.col + off, off
end

local function canvas_chars()
	local fc = vim.opt.fillchars:get()
	return {
		vert = fc.vert or "│",
		horiz = fc.horiz or "─",
		verthoriz = fc.verthoriz or "┼",
		vertleft = fc.vertleft or "┤",
		vertright = fc.vertright or "├",
		horizup = fc.horizup or "┴",
		horizdown = fc.horizdown or "┬",
	}
end

-- Build the canvas text grid: (layout.h + 2*off) rows of (layout.w + 2*off)
-- cells. Interior separators come from the layout tree; junctions are picked
-- by connectivity, so ├ ┤ ┬ ┴ ┼ appear where separators meet each other or
-- the outer border.
local function build_canvas_lines(layout, base, off)
	local chars = canvas_chars()
	local W = layout.w + 2 * off
	local H = layout.h + 2 * off

	local cells = {} -- [r][c] = char
	local conn = {} -- [r][c] = {up=,down=,left=,right=}
	local function cell_conn(r, c)
		conn[r] = conn[r] or {}
		conn[r][c] = conn[r][c] or {}
		return conn[r][c]
	end
	local function put(r, c, ch)
		if r >= 0 and r < H and c >= 0 and c < W then
			cells[r] = cells[r] or {}
			cells[r][c] = ch
		end
	end

	-- outer border
	if off == 1 then
		local b = resolve_border(base.border)
		for c = 1, W - 2 do
			put(0, c, border_char(b[2]) or " ")
			put(H - 1, c, border_char(b[6]) or " ")
			local tc = cell_conn(0, c)
			tc.left, tc.right = true, true
			local bc = cell_conn(H - 1, c)
			bc.left, bc.right = true, true
		end
		for r = 1, H - 2 do
			put(r, 0, border_char(b[8]) or " ")
			put(r, W - 1, border_char(b[4]) or " ")
			local lc = cell_conn(r, 0)
			lc.up, lc.down = true, true
			local rc = cell_conn(r, W - 1)
			rc.up, rc.down = true, true
		end
		put(0, 0, border_char(b[1]) or " ")
		put(0, W - 1, border_char(b[3]) or " ")
		put(H - 1, W - 1, border_char(b[5]) or " ")
		put(H - 1, 0, border_char(b[7]) or " ")
	end

	-- interior separators + endpoint connectivity into neighbors
	local _, seps = frame.rects(layout, off, off)
	for _, sep in ipairs(seps) do
		if sep.axis == "v" then
			for r = sep.row, sep.row + sep.len - 1 do
				put(r, sep.col, chars.vert)
				local c = cell_conn(r, sep.col)
				c.up, c.down = true, true
			end
			cell_conn(sep.row - 1, sep.col).down = true
			cell_conn(sep.row + sep.len, sep.col).up = true
		else
			for c = sep.col, sep.col + sep.len - 1 do
				put(sep.row, c, chars.horiz)
				local cl = cell_conn(sep.row, c)
				cl.left, cl.right = true, true
			end
			cell_conn(sep.row, sep.col - 1).right = true
			cell_conn(sep.row, sep.col + sep.len).left = true
		end
	end

	-- junctions: any cell connecting in 3+ directions
	for r, row in pairs(conn) do
		for c, cl in pairs(row) do
			local n = (cl.up and 1 or 0) + (cl.down and 1 or 0) + (cl.left and 1 or 0) + (cl.right and 1 or 0)
			if n >= 3 then
				local ch
				if cl.up and cl.down and cl.left and cl.right then
					ch = chars.verthoriz
				elseif cl.up and cl.down then
					ch = cl.left and chars.vertleft or chars.vertright
				else
					ch = cl.up and chars.horizup or chars.horizdown
				end
				put(r, c, ch)
			end
		end
	end

	-- title on the top border
	if off == 1 and base.title then
		local title = type(base.title) == "string" and base.title or ""
		local tlen = vim.fn.strwidth(title)
		if tlen > 0 and tlen <= W - 2 then
			local start = math.max(1, math.floor((W - tlen) / 2))
			local i = 0
			for _, ch in ipairs(vim.fn.split(title, "\\zs")) do
				put(0, start + i, ch)
				i = i + 1
			end
		end
	end

	local lines = {}
	for r = 0, H - 1 do
		local row = cells[r] or {}
		local parts = {}
		for c = 0, W - 1 do
			parts[#parts + 1] = row[c] or " "
		end
		lines[r + 1] = table.concat(parts)
	end
	return lines
end

function M.close_canvas()
	local win = vim.t.term_canvas_winid
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
	vim.t.term_canvas_winid = nil
end

-- Create or refresh the canvas float under the panes.
function M.update_canvas(layout, base)
	local off = M.has_border(base) and 1 or 0
	local _, seps = frame.rects(layout, 0, 0)
	if off == 0 and #seps == 0 then
		M.close_canvas()
		return
	end

	if not canvas_bufnr or not vim.api.nvim_buf_is_valid(canvas_bufnr) then
		canvas_bufnr = vim.api.nvim_create_buf(false, true)
		vim.bo[canvas_bufnr].bufhidden = "hide"
		vim.bo[canvas_bufnr].buftype = "nofile"
	end

	local lines = build_canvas_lines(layout, base, off)
	vim.api.nvim_buf_set_lines(canvas_bufnr, 0, -1, false, lines)

	local cfg = {
		relative = "editor",
		row = base.row,
		col = base.col,
		width = layout.w + 2 * off,
		height = layout.h + 2 * off,
		style = "minimal",
		border = "none",
		zindex = 29,
		focusable = false,
		noautocmd = true,
	}

	local win = vim.t.term_canvas_winid
	if state.win_valid(win) then
		cfg.noautocmd = nil
		vim.api.nvim_win_set_config(win, cfg)
		vim.api.nvim_win_set_buf(win, canvas_bufnr)
	else
		win = vim.api.nvim_open_win(canvas_bufnr, false, cfg)
		vim.t.term_canvas_winid = win
	end
	vim.wo[win].winhighlight = "Normal:WinSeparator,NormalFloat:WinSeparator"
	vim.wo[win].winblend = config.get_float_winblend()
end

-- Position all pane floats (and the canvas) from the entry's layout tree.
-- In drawer mode, applies the sizes to the real split windows instead.
function M.apply_layout(entry)
	local window = require("terminal.window")

	if not config.is_float_mode() then
		window.apply_drawer_sizes(entry)
		window.save_layout_sizes()
		return
	end

	local wins = vim.t.term_winids or {}
	if #wins == 0 or #wins ~= #entry.bufs then
		window.rebuild_tab()
		return
	end

	local base = window.get_float_win_config()
	local origin_row, origin_col = M.content_origin(base)
	local rects = frame.rects(entry.layout, 0, 0)

	for i, buf in ipairs(entry.bufs) do
		local rect = rects[buf]
		local win = wins[i]
		if not rect or not state.win_valid(win) then
			window.rebuild_tab()
			return
		end
		local cfg = vim.api.nvim_win_get_config(win)
		cfg.relative = "editor"
		cfg.row = origin_row + rect.row
		cfg.col = origin_col + rect.col
		cfg.width = rect.w
		cfg.height = rect.h
		vim.api.nvim_win_set_config(win, cfg)
	end

	M.update_canvas(entry.layout, base)
	window.save_layout_sizes()
	winbar.update()
	statusline.update()
end

-- CTRL-W =: vim's win_equal over the layout tree, in both modes.
function M.equalize_panes()
	local window = require("terminal.window")
	local tab, tab_idx = state.get_current_tab()
	if not tab or #tab.bufs < 2 then
		return
	end

	window.save_layout_sizes()
	local order = state.get_term_order()
	local entry = order[tab_idx]
	if not entry or not entry.layout then
		return
	end
	frame.equalize(entry.layout, entry.layout.w, entry.layout.h)
	vim.t.term_order = order

	M.apply_layout(entry)
end

-- The separator (if any) at the given mouse position, along with the tab
-- entry whose layout produced it.
local function sep_at_mouse(mouse)
	if not config.is_float_mode() or not state.is_term_open() then
		return nil
	end
	local _, tab_idx = state.get_current_tab()
	if not tab_idx then
		return nil
	end
	local entry = state.get_term_order()[tab_idx]
	if not entry or not entry.layout then
		return nil
	end

	local window = require("terminal.window")
	local base = window.get_float_win_config()
	local origin_row, origin_col = M.content_origin(base)
	local grid_row = mouse.screenrow - 1 - origin_row
	local grid_col = mouse.screencol - 1 - origin_col

	local sep = frame.sep_at(entry.layout, grid_row, grid_col)
	if not sep then
		return nil
	end
	return sep, entry, tab_idx
end

-- Current grid position of a separator inside drag_state.layout (positions
-- move as the drag progresses; node references stay stable).
local function drag_sep_position()
	local _, seps = frame.rects(drag_state.layout, 0, 0)
	for _, sep in ipairs(seps) do
		if sep.node == drag_state.sep.node and sep.idx == drag_state.sep.idx and sep.axis == drag_state.sep.axis then
			return sep
		end
	end
	return nil
end

local click_api = nil

-- Mouse handlers take the mouse position (getmousepos() shape) and return
-- the key to feed ("" = consumed). Extracted from the mappings so tests can
-- drive them with synthetic positions.

function M.on_left_mouse(mouse)
	-- Track mode for tabline clicks so LeftRelease can restore it
	if mouse.screenrow == 1 and vim.o.showtabline > 0 then
		tabline_click_mode = vim.api.nvim_get_mode().mode
	end

	-- Handle winbar click without changing focus/mode
	if mouse.winid == vim.t.term_winbar_winid then
		local col = mouse.column - 1
		for _, range in ipairs(winbar.get_click_ranges()) do
			if col >= range.start_col and col < range.end_col then
				vim.schedule(function()
					if click_api then
						click_api.go_to(range.tab_idx)
					end
				end)
				break
			end
		end
		return ""
	end

	-- Statusline overlay (zoom): the overlay sits on the separator row
	-- between stacked panes, so prefer starting a drag; a plain click (no
	-- movement) focuses the pane on release.
	if statusline.is_stl_window(mouse.winid) then
		local stl_buf = vim.api.nvim_win_get_buf(mouse.winid)
		local stl_pane = vim.b[stl_buf].terminal_stl_pane
		local sep, entry = sep_at_mouse(mouse)
		if sep then
			drag_state = { layout = entry.layout, sep = sep, click_pane = stl_pane, moved = false }
			vim.schedule(function()
				vim.cmd("stopinsert")
			end)
			return ""
		end
		if stl_pane and state.win_valid(stl_pane) then
			local m = mode.of_win(stl_pane)
			mode.record()
			vim.schedule(function()
				vim.api.nvim_set_current_win(stl_pane)
				mode.restore(stl_pane, m)
				statusline.update()
			end)
		end
		return ""
	end

	-- Native statusline (drawer): pass the click through so vim's own
	-- statusline drag can resize stacked panes; terminal mode is restored on
	-- release.
	if mouse.line == 0 and not config.is_float_mode() then
		local wins = vim.t.term_winids or {}
		for _, win in ipairs(wins) do
			if mouse.winid == win and state.win_valid(win) then
				stl_click = true
				mode.record()
				return "<LeftMouse>"
			end
		end
	end

	-- Grab a canvas separator for dragging
	local sep, entry = sep_at_mouse(mouse)
	if sep then
		drag_state = { layout = entry.layout, sep = sep }
		-- Match Neovim's behaviour of exiting to normal mode when resizing
		vim.schedule(function()
			vim.cmd("stopinsert")
		end)
		return ""
	end
	return "<LeftMouse>"
end

function M.on_left_drag(mouse)
	if stl_click then
		-- native statusline drag (drawer): let vim resize
		return "<LeftDrag>"
	end
	if not drag_state then
		if mouse.winid == vim.t.term_winbar_winid or statusline.is_stl_window(mouse.winid) then
			return ""
		end
		return "<LeftDrag>"
	end
	drag_state.moved = true

	local window = require("terminal.window")
	local base = window.get_float_win_config()
	local origin_row, origin_col = M.content_origin(base)
	local sep = drag_sep_position()
	if not sep then
		drag_state = nil
		return ""
	end

	local delta
	if sep.axis == "v" then
		delta = (mouse.screencol - 1 - origin_col) - sep.col
	else
		delta = (mouse.screenrow - 1 - origin_row) - sep.row
	end
	if delta == 0 then
		return ""
	end

	frame.drag(drag_state.layout, sep, delta)

	local _, tab_idx = state.get_current_tab()
	if tab_idx then
		local order = state.get_term_order()
		if order[tab_idx] then
			order[tab_idx].layout = drag_state.layout
			vim.t.term_order = order
			vim.schedule(function()
				local cur = state.get_term_order()[tab_idx]
				if cur then
					M.apply_layout(cur)
				end
			end)
		end
	end
	return ""
end

function M.on_left_release(mouse)
	if drag_state then
		-- plain click (no movement) on a zoom statusline: focus that pane
		local click_pane = not drag_state.moved and drag_state.click_pane or nil
		drag_state = nil
		if click_pane and state.win_valid(click_pane) then
			local m = mode.of_win(click_pane)
			mode.record()
			vim.schedule(function()
				vim.api.nvim_set_current_win(click_pane)
				mode.restore(click_pane, m)
				statusline.update()
			end)
		else
			vim.schedule(function()
				require("terminal.window").save_layout_sizes()
			end)
		end
		return ""
	end
	if stl_click then
		-- end of a native statusline click/drag (drawer): let vim finish it,
		-- then restore the terminal mode and record the resized layout
		stl_click = false
		vim.schedule(function()
			require("terminal.window").save_layout_sizes()
			mode.restore_current()
		end)
		return "<LeftRelease>"
	end
	if mouse.winid == vim.t.term_winbar_winid or statusline.is_stl_window(mouse.winid) then
		return ""
	end
	if tabline_click_mode then
		local was_terminal = tabline_click_mode == "t"
		tabline_click_mode = nil
		if was_terminal and vim.bo.buftype == "terminal" then
			vim.schedule(mode.restore_current)
		end
		return ""
	end
	return "<LeftRelease>"
end

function M.setup_mouse_mappings(bufnr, api)
	click_api = api
	for _, keymode in ipairs({ "n", "t" }) do
		vim.keymap.set(keymode, "<LeftMouse>", function()
			return M.on_left_mouse(vim.fn.getmousepos())
		end, { buffer = bufnr, expr = true, noremap = true })

		vim.keymap.set(keymode, "<LeftDrag>", function()
			return M.on_left_drag(vim.fn.getmousepos())
		end, { buffer = bufnr, expr = true, noremap = true })

		for _, event in ipairs({
			"<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>",
			"<2-LeftRelease>", "<3-LeftRelease>", "<4-LeftRelease>",
			"<2-LeftDrag>", "<3-LeftDrag>", "<4-LeftDrag>",
		}) do
			vim.keymap.set(keymode, event, function()
				local ev_mouse = vim.fn.getmousepos()
				if ev_mouse.winid == vim.t.term_winbar_winid or statusline.is_stl_window(ev_mouse.winid) then
					return ""
				end
				return event
			end, { buffer = bufnr, expr = true, noremap = true })
		end

		vim.keymap.set(keymode, "<LeftRelease>", function()
			return M.on_left_release(vim.fn.getmousepos())
		end, { buffer = bufnr, expr = true, noremap = true })
	end
end

return M
