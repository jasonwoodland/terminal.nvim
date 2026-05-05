-- terminal.nvim: dimming backdrop behind float panes

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")

local overlay_bufnr = nil

vim.api.nvim_set_hl(0, "TerminalOverlay", { bg = "#000000", default = true })

local function tabline_height()
	if vim.o.showtabline == 2 then
		return 1
	end
	if vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1 then
		return 1
	end
	return 0
end

local function get_overlay_win_config()
	local th = tabline_height()
	return {
		relative = "editor",
		row = th,
		col = 0,
		width = vim.o.columns,
		height = math.max(vim.o.lines - vim.o.cmdheight - th, 1),
		focusable = false,
		style = "minimal",
		border = "none",
		zindex = 25,
	}
end

function M.update()
	local overlay = config.get_float_overlay()
	if not overlay then
		M.destroy()
		return
	end

	if not overlay_bufnr or not vim.api.nvim_buf_is_valid(overlay_bufnr) then
		overlay_bufnr = vim.api.nvim_create_buf(false, true)
		vim.bo[overlay_bufnr].bufhidden = "hide"
		vim.bo[overlay_bufnr].buftype = "nofile"
	end

	local cfg = get_overlay_win_config()
	local winid = vim.t.term_overlay_winid
	if state.win_valid(winid) then
		vim.api.nvim_win_set_config(winid, cfg)
	else
		winid = vim.api.nvim_open_win(overlay_bufnr, false, cfg)
		vim.t.term_overlay_winid = winid
	end

	local hl = overlay.hl or "TerminalOverlay"
	vim.wo[winid].winhighlight = "Normal:" .. hl .. ",NormalNC:" .. hl .. ",EndOfBuffer:" .. hl
	vim.wo[winid].winblend = overlay.winblend or 60
	vim.wo[winid].cursorline = false
	vim.wo[winid].number = false
	vim.wo[winid].relativenumber = false
	vim.wo[winid].signcolumn = "no"
	vim.wo[winid].fillchars = "eob: "
end

function M.destroy()
	local winid = vim.t.term_overlay_winid
	if winid and vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_win_close(winid, true)
	end
	vim.t.term_overlay_winid = nil
end

return M
