-- terminal.nvim: configuration

local M = {}

local default_float = {
	enabled = false,
	padding = { x = 24, y = 4 },
	border = false,
	winblend = 0,
	overlay = {
		enabled = true,
		winblend = 75,
		hl = "TerminalOverlay",
	},
}

M.config = {
	height = 0.5,
	drawer = {
		winpinned = true,
	},
	winbar = true,
	show_winbar_when_single_tab = false,
	float = vim.deepcopy(default_float),
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
		split = "<C-S-s>",
		break_to_tab = "<C-S-t>",
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

local defaults = vim.deepcopy(M.config)

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

-- Configuration supplies the initial mode. Runtime toggles belong to a Vim
-- tabpage, so changing one view does not reinterpret other open drawers.
function M.is_float_config_enabled()
	if vim.t.term_float_enabled ~= nil then return vim.t.term_float_enabled end
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

function M.get_float_config()
	if type(M.config.float) == "table" then
		return M.config.float
	end
	return default_float
end

function M.get_float_winblend()
	if not M.is_plain_float_mode() then
		return 0
	end
	local v = M.get_float_config().winblend
	return type(v) == "number" and v or 0
end

function M.get_float_overlay()
	if not M.is_plain_float_mode() then
		return nil
	end
	local overlay = M.get_float_config().overlay
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
	assert(user_config == nil or type(user_config) == "table", "terminal configuration must be a table")
	local candidate = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_config or {})
	assert(candidate.keys == false or type(candidate.keys) == "table", "keys must be a table or false")
	if candidate.keys ~= false then
		for name, value in pairs(candidate.keys) do
			assert(defaults.keys[name] ~= nil, "unknown terminal key: " .. name)
			assert(value == false or type(value) == "string" or (type(value) == "table" and vim.islist(value)),
				"key " .. name .. " must be a string, list of strings, or false")
			for _, key in ipairs(require("terminal.utils").key_list(value)) do
				assert(type(key) == "string" and key ~= "", "key " .. name .. " must contain nonempty strings")
				if name == "go_to_tab" then
					local ok, first = pcall(string.format, key, 1)
					local ok_last, last = pcall(string.format, key, 9)
					assert(ok and ok_last and first ~= last, "go_to_tab keys must contain an integer placeholder such as %d")
				end
			end
		end
	end
	M.config = candidate
end

return M
