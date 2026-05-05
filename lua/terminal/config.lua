-- terminal.nvim: configuration

local M = {}

M.config = {
	height = 0.5,
	winbar = true,
	float = false,
	float_zoom = true,
	float_zoom_show_tabline = true,
	float_zoom_hide_cmdline = false,
	osc_notifications = true,
	keys = {
		toggle = "<C-S-Space>",
		normal_mode = "<C-S-\\>",
		zoom = "<C-S-z>",
		new = "<C-S-n>",
		wincmd = "<C-S-w>",
		delete = "<C-S-c>",
		prev = "<C-S-[>",
		next = "<C-S-]>",
		last_tab = "<C-S-o>",
		last_pane = "<C-S-p>",
		move_prev = "<C-S-M-[>",
		move_next = "<C-S-M-]>",
		paste_register = "<C-S-r>",
		digraph = "<C-S-k>",
		reset_height = "<C-S-=>",
		vim_tab_next = "<C-PageDown>",
		vim_tab_prev = "<C-PageUp>",
		vim_tab_move_prev = "<C-M-PageUp>",
		vim_tab_move_next = "<C-M-PageDown>",
		move_to_vim_tab_prev = "<C-S-M-PageUp>",
		move_to_vim_tab_next = "<C-S-M-PageDown>",
		last_notification = "<C-S-a>",
	},
}

function M.get_term_height()
	if M.config.height < 1 then
		return math.floor(vim.o.lines * M.config.height)
	end
	return M.config.height
end

function M.is_float_mode()
	return M.config.float or (M.config.float_zoom and vim.t.term_zoom)
end

-- True when float mode is active and not zoomed (winblend/overlay only apply
-- here; in zoom we want a fully opaque, full-screen terminal).
function M.is_plain_float_mode()
	return M.config.float and not vim.t.term_zoom
end

local function float_table()
	if type(M.config.float) == "table" then
		return M.config.float
	end
	return {}
end

function M.get_float_winblend()
	if not M.is_plain_float_mode() then
		return 0
	end
	local v = float_table().winblend
	return type(v) == "number" and v or 0
end

function M.get_float_overlay()
	if not M.is_plain_float_mode() then
		return nil
	end
	local overlay = float_table().overlay
	if not overlay then
		return nil
	end
	local defaults = { winblend = 60, hl = "TerminalOverlay" }
	if overlay == true then
		return defaults
	end
	if type(overlay) == "table" then
		return vim.tbl_extend("force", defaults, overlay)
	end
	return nil
end

function M.setup(user_config)
	local default_keys = M.config.keys
	M.config = vim.tbl_extend("force", M.config, user_config or {})
	if M.config.keys ~= false then
		M.config.keys = vim.tbl_extend("force", default_keys, M.config.keys or {})
	end
end

return M
