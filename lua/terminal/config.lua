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
		normal_mode = "<C-S-n>",
		zoom = "<C-S-z>",
		new = "<C-S-t>",
		wincmd = "<C-S-w>",
		delete = "<C-S-c>",
		prev = "<C-S-[>",
		next = "<C-S-]>",
		move_prev = "<C-S-M-[>",
		move_next = "<C-S-M-]>",
		paste_register = "<C-S-r>",
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

function M.setup(user_config)
	local default_keys = M.config.keys
	M.config = vim.tbl_extend("force", M.config, user_config or {})
	if M.config.keys ~= false then
		M.config.keys = vim.tbl_extend("force", default_keys, M.config.keys or {})
	end
end

return M
