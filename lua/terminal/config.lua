-- terminal.nvim: configuration

local M = {}

M.config = {
	height = 0.5,
	winbar = true,
	show_winbar_when_single_tab = false,
	float = {
		enabled = false,
		border = false,
		overlay = {
			enabled = true,
			winblend = 75,
			hl = "TerminalOverlay",
		},
	},
	float_zoom = true,
	float_zoom_show_tabline = true,
	float_zoom_hide_cmdline = false,
	set_buffer_name = true,
	osc_notifications = true,
	keys = {
		toggle = "<C-S-Space>",
		normal_mode = "<C-S-\\>",
		zoom = "<C-S-z>",
		float_toggle = "<C-S-f>",
		new = "<C-S-n>",
		wincmd = "<C-S-w>",
		delete = "<C-S-c>",
		prev = "<C-S-[>",
		next = "<C-S-]>",
		last_tab = "<C-S-o>",
		last_pane = "<C-S-p>",
		pane_left = "<C-S-h>",
		pane_right = "<C-S-l>",
		vsplit = "<C-S-v>",
		-- %d is replaced with 1-9; set to false to disable the go-to-tab maps
		go_to_tab = "<C-S-%d>",
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

function M.should_show_winbar(tab_count)
	if not M.config.winbar then
		return false
	end
	if tab_count ~= nil and tab_count <= 0 then
		return false
	end
	if tab_count ~= nil and tab_count <= 1 then
		return M.config.show_winbar_when_single_tab
	end
	return true
end

function M.get_winbar_height(tab_count)
	return M.should_show_winbar(tab_count) and 1 or 0
end

-- True when the float config is set and not opted out via `enabled = false`.
-- Lets users define `float = { enabled = false, padding = ... }` so the config
-- is preset for `float_toggle` without starting in float mode.
function M.is_float_config_enabled()
	local f = M.config.float
	if type(f) == "table" then
		return f.enabled ~= false
	end
	return not not f
end

function M.is_float_mode()
	return M.is_float_config_enabled() or (M.config.float_zoom and vim.t.term_zoom)
end

-- True when float mode is active and not zoomed (winblend/overlay only apply
-- here; in zoom we want a fully opaque, full-screen terminal).
function M.is_plain_float_mode()
	return M.is_float_config_enabled() and not vim.t.term_zoom
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
	if overlay == false or overlay == nil then
		return nil
	end
	local defaults = { winblend = 75, hl = "TerminalOverlay" }
	if overlay == true then
		return defaults
	end
	if type(overlay) == "table" then
		if overlay.enabled == false then
			return nil
		end
		return vim.tbl_extend("force", defaults, overlay)
	end
	return nil
end

function M.setup(user_config)
	local default_keys = M.config.keys
	local default_float = M.config.float
	M.config = vim.tbl_extend("force", M.config, user_config or {})
	if M.config.keys ~= false then
		M.config.keys = vim.tbl_extend("force", default_keys, M.config.keys or {})
	end
	if type(M.config.float) == "table" and type(default_float) == "table" then
		M.config.float = vim.tbl_deep_extend("force", default_float, M.config.float)
	end
end

return M
