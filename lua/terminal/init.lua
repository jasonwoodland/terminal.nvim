-- terminal.nvim

local M = {}

local loaded = false

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

M.config = {
	height = 0.5,
	winbar = true,
	float = false,
	float_zoom = true,
	keys = {
		toggle = "<C-->",
		normal_mode = "<C-;>",
		zoom = "<C-S-->",
		new = "<C-S-n>",
		delete = "<C-S-c>",
		prev = "<C-S-[>",
		next = "<C-S-]>",
		move_prev = "<C-S-M-[>",
		move_next = "<C-S-M-]>",
		paste_register = "<C-S-r>",
		reset_height = "<C-S-=>",
		tab_next = "<C-PageDown>",
		tab_prev = "<C-PageUp>",
	},
}

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------

local utils = require("terminal.utils")

local function get_term_height()
	if M.config.height < 1 then
		return math.floor(vim.o.lines * M.config.height)
	end
	return M.config.height
end

local function get_winbar_height()
	return M.config.winbar and 1 or 0
end

local function is_float_mode()
	return M.config.float or (M.config.float_zoom and vim.t.term_zoom)
end

local function save_term_height()
	if vim.fn.exists("t:term_bufnr") ~= 0 and vim.t.term_prev_height == nil and not vim.t.term_zoom then
		local height = vim.fn.winheight(vim.fn.bufwinnr(vim.t.term_bufnr))
		if height > 0 then
			vim.t.term_height = height + get_winbar_height()
		end
	end
end

local function sync_term_order()
	local order = vim.t.term_order or {}
	local valid_order = {}

	for _, buf in ipairs(order) do
		if vim.fn.bufexists(buf) == 1 and vim.fn.getbufvar(buf, "&buftype") == "terminal" then
			table.insert(valid_order, buf)
		end
	end

	vim.t.term_order = valid_order
	return valid_order
end

local function add_term_to_order(bufnr, after_bufnr)
	local order = vim.t.term_order or {}
	for _, buf in ipairs(order) do
		if buf == bufnr then
			return
		end
	end
	if after_bufnr then
		for i, buf in ipairs(order) do
			if buf == after_bufnr then
				table.insert(order, i + 1, bufnr)
				vim.t.term_order = order
				return
			end
		end
	end
	table.insert(order, bufnr)
	vim.t.term_order = order
end

local function remove_term_from_order(bufnr)
	local order = vim.t.term_order or {}
	local new_order = {}
	for _, buf in ipairs(order) do
		if buf ~= bufnr then
			table.insert(new_order, buf)
		end
	end
	vim.t.term_order = new_order
	_G["TermWinbarClick" .. bufnr] = nil
end

local set_terminal_winbar

local function move_term_in_order(direction)
	local bufnr = vim.fn.bufnr()
	if vim.bo.buftype ~= "terminal" then
		return
	end

	local order = sync_term_order()
	local idx = nil
	for i, buf in ipairs(order) do
		if buf == bufnr then
			idx = i
			break
		end
	end

	if not idx then
		return
	end

	local new_idx = idx + direction
	if new_idx < 1 or new_idx > #order then
		return
	end

	order[idx], order[new_idx] = order[new_idx], order[idx]
	vim.t.term_order = order

	set_terminal_winbar()
end

local function get_terminal_buffers()
	return sync_term_order()
end

local function get_next_terminal_buffer_before_close(bufnr)
	local bufs = get_terminal_buffers()

	local i
	bufnr = bufnr or vim.fn.bufnr()
	for j = 1, #bufs do
		if bufs[j] == bufnr then
			i = j
			break
		end
	end
	if i == nil then
		return nil
	end
	table.remove(bufs, i)

	if i > #bufs then
		i = #bufs
	end

	return bufs[i]
end

--------------------------------------------------------------------------------
-- Winbar
--------------------------------------------------------------------------------

local function format_terminal_buffers(terminal_buffers)
	local buffer_names = {}
	local current_buf = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(terminal_buffers) do
		local fn_name = "TermWinbarClick" .. buf

		_G[fn_name] = function()
			local term_winid = vim.t.term_winid
			if term_winid and vim.fn.win_id2win(term_winid) > 0 then
				local src_bufnr = vim.api.nvim_win_get_buf(term_winid)
				if vim.bo[src_bufnr].buftype == "terminal" then
					vim.b[src_bufnr]._term_winbar_click = true
				end
				vim.api.nvim_set_current_win(term_winid)
				vim.cmd("buffer " .. buf)
				if vim.b.term_mode == "n" then
					vim.cmd("stopinsert")
				else
					vim.cmd("startinsert")
				end
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(src_bufnr) then
						vim.b[src_bufnr]._term_winbar_click = nil
					end
				end)
			end
		end

		local buf_name = vim.api.nvim_buf_get_name(buf)
		buf_name = vim.b[buf].term_title or buf_name
		buf_name = vim.fn.substitute(buf_name, "\\v([^/~ ]+)/", "\\=strpart(submatch(1), 0, 1) . '/'", "g")

		local styled_name
		if buf == current_buf then
			styled_name = "%#WinBarActive# " .. buf_name .. " %*"
		else
			styled_name = " " .. buf_name .. " "
		end

		local clickable_name = "%@v:lua.TermWinbarClick" .. buf .. "@" .. styled_name .. "%T"

		table.insert(buffer_names, clickable_name)
	end
	return table.concat(buffer_names)
end

set_terminal_winbar = function()
	if vim.t.term_winid == nil or vim.fn.win_getid() ~= vim.t.term_winid then
		return
	end
	local terminal_buffers = get_terminal_buffers()
	if #terminal_buffers > 0 then
		vim.wo.winbar = format_terminal_buffers(terminal_buffers)
	end
end

--------------------------------------------------------------------------------
-- Window management
--------------------------------------------------------------------------------

local function get_float_win_config()
	if vim.t.term_zoom then
		return {
			relative = "editor",
			width = vim.o.columns,
			height = vim.o.lines - 1,
			row = 0,
			col = 0,
			style = "minimal",
			border = "none",
		}
	end

	local float_config = {
		padding = { x = 24, y = 4 },
		border = "rounded",
	}

	if type(M.config.float) == "table" then
		float_config = vim.tbl_extend("force", float_config, M.config.float)
	end

	local col = float_config.padding.x
	local row = float_config.padding.y
	local border_width = float_config.border == "none" and 0 or 2
	local width = math.floor(vim.o.columns - float_config.padding.x * 2 - border_width)
	local height = math.floor(vim.o.lines - float_config.padding.y * 2 - border_width - 2)

	return {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = float_config.border,
		title = " Terminal ",
		title_pos = "center",
	}
end

local function open_window(bufnr, win_config)
	local scratch = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(scratch, true, win_config)
	if M.config.winbar then
		local buffers = get_terminal_buffers()
		if #buffers > 0 then
			vim.wo[win].winbar = format_terminal_buffers(buffers)
		end
	end
	vim.api.nvim_win_set_buf(win, bufnr)
	vim.api.nvim_buf_delete(scratch, { force = true })
	return win
end

local function create_float_win(bufnr)
	local win = open_window(bufnr, get_float_win_config())
	vim.wo[win].winblend = 0
	return win
end

function M.toggle()
	local height = vim.v.count1
	if #vim.api.nvim_tabpage_list_wins(0) == 1 and not is_float_mode() then
		vim.t.term_winid = nil
	end

	if
	    vim.t.term_winid ~= 0
	    and vim.fn.win_id2win(vim.t.term_winid) > 0
	    and (#vim.api.nvim_tabpage_list_wins(0) > 1 or is_float_mode())
	then
		vim.t.term_bufnr = vim.api.nvim_win_get_buf(vim.t.term_winid)
		vim.t.term_mode = vim.fn.mode()
		vim.b[vim.t.term_bufnr].term_view = vim.fn.winsaveview()
		local term_winnr = vim.fn.bufwinnr(vim.t.term_bufnr)

		if is_float_mode() then
			vim.api.nvim_win_close(vim.t.term_winid, true)
			vim.t.term_winid = nil
		else
			if vim.fn.win_getid() == vim.t.term_winid then
				vim.cmd("wincmd p")
			end
			vim.cmd(term_winnr .. "close")
		end
	else
		vim.t.current_win = vim.fn.win_getid()
		vim.t.prev_winid = vim.fn.win_getid()

		if is_float_mode() then
			if vim.fn.exists("t:term_bufnr") ~= 0 and vim.fn.bufexists(vim.t.term_bufnr) ~= 0 then
				vim.t.term_winid = create_float_win(vim.t.term_bufnr)
			else
				local bufnr = vim.api.nvim_create_buf(false, true)
				vim.t.term_winid = create_float_win(bufnr)
				vim.fn.termopen(vim.env.SHELL)
				vim.t.term_bufnr = bufnr
			end
		else
			if vim.fn.exists("t:term_bufnr") ~= 0 and vim.fn.bufexists(vim.t.term_bufnr) ~= 0 then
				local terminal_height = height > 1 and height or vim.t.term_height or get_term_height()
				vim.t.term_winid = open_window(vim.t.term_bufnr, {
					split = "below",
					win = -1,
					height = terminal_height,
				})
				if vim.t.term_prev_height ~= nil then
					vim.cmd("resize")
					vim.t.term_height = vim.fn.winheight(vim.t.term_winid) + get_winbar_height()
				end
			else
				local bufnr = vim.api.nvim_create_buf(false, true)
				local terminal_height = height > 1 and height or vim.t.term_height or get_term_height()
				vim.t.term_winid = open_window(bufnr, {
					split = "below",
					win = -1,
					height = terminal_height,
				})
				vim.fn.termopen(vim.env.SHELL)
				if vim.t.term_prev_height ~= nil then
					vim.cmd("resize")
					vim.t.term_height = vim.fn.winheight(vim.t.term_winid) + get_winbar_height()
				end
			end

			vim.cmd("set wfh")
			vim.t.term_bufnr = vim.fn.bufnr()
			vim.t.term_winid = vim.fn.win_getid()
		end

		if vim.b[vim.t.term_bufnr].term_view then
			vim.fn.winrestview(vim.b[vim.t.term_bufnr].term_view)
		end

		if vim.t.term_mode ~= "n" then
			vim.cmd("startinsert")
		end
	end
end

function M.zoom()
	if M.config.float then
		vim.t.term_zoom = not vim.t.term_zoom
		local win_config = get_float_win_config()
		if vim.t.term_winid ~= 0 and vim.fn.win_id2win(vim.t.term_winid) > 0 then
			vim.api.nvim_win_set_config(vim.t.term_winid, win_config)
		end
		return
	end
	if M.config.float_zoom then
		local term_win_open = vim.t.term_winid and vim.t.term_winid ~= 0 and
		vim.fn.win_id2win(vim.t.term_winid) > 0
		if not term_win_open then
			return
		end

		local bufnr = vim.api.nvim_win_get_buf(vim.t.term_winid)
		local mode = vim.b[bufnr].term_mode or "t"

		if not vim.t.term_zoom then
			save_term_height()
			vim.t.term_zoom = true

			if vim.fn.win_getid() == vim.t.term_winid then
				vim.cmd("wincmd p")
			end
			local term_winnr = vim.fn.win_id2win(vim.t.term_winid)
			vim.cmd(term_winnr .. "close")

			vim.t.term_winid = create_float_win(bufnr)
			vim.t.term_bufnr = bufnr
		else
			local height = vim.t.term_height or get_term_height()
			vim.api.nvim_win_close(vim.t.term_winid, true)
			vim.t.term_zoom = nil
			vim.t.term_winid = open_window(bufnr, {
				split = "below",
				win = -1,
				height = height,
			})
			vim.cmd("set wfh")
			print("") -- trigger redraw of cmdline to clear ruler
			vim.t.term_bufnr = bufnr
			vim.t.term_height = height
		end

		if mode ~= "n" then
			vim.cmd("startinsert")
		end
		return
	end
	if vim.t.term_prev_height == nil then
		vim.t.term_prev_height = vim.t.term_height
		vim.cmd("resize")
		vim.t.term_height = vim.fn.winheight(vim.t.term_winid) + get_winbar_height()
	else
		vim.t.term_height = vim.t.term_prev_height
		vim.t.term_prev_height = nil
	end
	if vim.t.term_winid ~= 0 and vim.fn.win_id2win(vim.t.term_winid) > 0 then
		vim.cmd("resize " .. vim.t.term_height)
	end
end

function M.reset_height()
	if vim.t.term_prev_height ~= nil or vim.t.term_zoom then
		return
	end
	vim.t.term_height = get_term_height()
	if vim.t.term_winid ~= 0 and vim.fn.win_id2win(vim.t.term_winid) > 0 then
		vim.cmd("resize " .. vim.t.term_height)
	end
end

--------------------------------------------------------------------------------
-- Buffer switching
--------------------------------------------------------------------------------

local function switch_to_term_buf(target_buf)
	local in_term_win = vim.t.term_winid and vim.fn.win_getid() == vim.t.term_winid

	if in_term_win then
		vim.b.term_mode = vim.fn.mode()
		vim.cmd("buffer " .. target_buf)
		if vim.b.term_mode ~= "n" then
			vim.cmd("startinsert")
		else
			vim.cmd("stopinsert")
		end
	else
		vim.api.nvim_win_set_buf(vim.t.term_winid, target_buf)
		vim.t.term_bufnr = target_buf
		vim.api.nvim_win_call(vim.t.term_winid, function()
			set_terminal_winbar()
		end)
	end
end

function M.switch(delta, clamp)
	local bufs = get_terminal_buffers()
	if #bufs == 0 then
		return
	end

	local in_term_win = vim.t.term_winid and vim.fn.win_getid() == vim.t.term_winid
	local term_win_open = vim.t.term_winid and vim.fn.win_id2win(vim.t.term_winid) > 0

	if not in_term_win and not term_win_open then
		return
	end

	local current_buf
	if in_term_win then
		current_buf = vim.fn.bufnr("%")
	else
		current_buf = vim.api.nvim_win_get_buf(vim.t.term_winid)
	end

	local i = nil
	for j, buf in ipairs(bufs) do
		if buf == current_buf then
			i = j
			break
		end
	end

	if i == nil then
		i = delta == 1 and #bufs or 1
	else
		i = i + delta
	end

	local b
	if clamp then
		b = bufs[math.max(1, math.min(#bufs, i))]
	else
		i = ((i - 1) % #bufs) + 1
		b = bufs[i]
	end

	if b == nil or b == current_buf then
		return
	end

	switch_to_term_buf(b)
end

function M.go_to(index)
	local bufs = get_terminal_buffers()
	if index < 1 or index > #bufs then
		return
	end
	local b = bufs[index]

	local in_term_win = vim.t.term_winid and vim.fn.win_getid() == vim.t.term_winid
	local term_win_open = vim.t.term_winid and vim.fn.win_id2win(vim.t.term_winid) > 0

	if not in_term_win and not term_win_open then
		return
	end

	local current_buf
	if in_term_win then
		current_buf = vim.fn.bufnr("%")
	else
		current_buf = vim.api.nvim_win_get_buf(vim.t.term_winid)
	end

	if b == current_buf then
		return
	end

	switch_to_term_buf(b)
end

function M.move(direction)
	move_term_in_order(direction)
end

function M.delete()
	if vim.bo.buftype ~= "terminal" then
		return
	end
	local bufnr = vim.fn.bufnr()
	local b = get_next_terminal_buffer_before_close()
	if b ~= nil then
		vim.cmd("buffer " .. b)
	end
	remove_term_from_order(bufnr)
	vim.api.nvim_buf_delete(bufnr, { force = true })
	if b ~= nil then
		set_terminal_winbar()
	end
end

function M.new()
	local current_buf = vim.fn.bufnr()
	vim.cmd("terminal")
	local new_buf = vim.fn.bufnr()
	remove_term_from_order(new_buf)
	add_term_to_order(new_buf, current_buf)
	set_terminal_winbar()
	vim.cmd("startinsert")
end

function M.next()
	M.switch(1)
end

function M.prev()
	M.switch(-1)
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local function setup_vars()
	vim.t.term_winid = vim.t.term_winid or 0
	vim.t.term_height = vim.t.term_height or get_term_height()
	vim.t.current_win = vim.t.current_win or 0
end

local function setup_autocmd()
	vim.api.nvim_create_augroup("Term", {})
	pcall(vim.api.nvim_clear_autocmds, { group = "nvim.terminal", event = "TermClose" })
	vim.api.nvim_create_autocmd("TermOpen", {
		pattern = "*",
		group = "Term",
		callback = function()
			vim.opt_local.signcolumn = "no"
			vim.opt_local.number = false
			vim.opt_local.relativenumber = false
			vim.opt_local.scrolloff = 0
			vim.opt_local.sidescrolloff = 0
			add_term_to_order(vim.fn.bufnr())
			vim.b.term_mode = "t"
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		pattern = "*:t",
		group = "Term",
		callback = function()
			if vim.bo.buftype == "terminal" then
				vim.b.term_mode = "t"
			end
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		pattern = { "t:nt", "t:n" },
		group = "Term",
		callback = function()
			local bufnr = vim.fn.bufnr()
			local winid = vim.fn.win_getid()
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end
				if vim.b[bufnr]._term_winbar_click then
					return
				end
				if vim.fn.win_getid() ~= winid then
					return
				end
				if vim.bo[bufnr].buftype == "terminal" then
					vim.b[bufnr].term_mode = "n"
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("WinResized", {
		pattern = "*",
		group = "Term",
		callback = function()
			if vim.t.term_bufnr == nil then
				return
			end
			if vim.t.term_prev_height ~= nil or vim.t.term_zoom then
				return
			end
			local height = vim.fn.winheight(vim.fn.bufwinnr(vim.t.term_bufnr))
			if height <= 0 then
				return
			end
			vim.t.term_height = height + get_winbar_height()
		end,
	})
	vim.api.nvim_create_autocmd("WinEnter", {
		pattern = "*",
		group = "Term",
		callback = function()
			if vim.bo.buftype == "terminal" then
				if vim.b._term_winbar_click then
					return
				end
				local mode = vim.fn.mode()
				vim.b.term_mode = (mode == "t") and "t" or "n"
			end
		end,
	})
	vim.api.nvim_create_autocmd("TabNew", {
		pattern = "*",
		group = "Term",
		callback = function()
			vim.t.term_height = get_term_height()
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		pattern = "*",
		group = "Term",
		callback = function()
			save_term_height()
		end,
	})
	vim.api.nvim_create_autocmd("TermClose", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local bufnr = ev.buf

			local term_win_open = vim.t.term_winid and vim.fn.win_id2win(vim.t.term_winid) > 0
			local is_displayed = term_win_open and vim.api.nvim_win_get_buf(vim.t.term_winid) == bufnr

			local next_buf = get_next_terminal_buffer_before_close(bufnr)
			remove_term_from_order(bufnr)

			if is_displayed and next_buf then
				vim.api.nvim_win_set_buf(vim.t.term_winid, next_buf)
				vim.t.term_bufnr = next_buf
			end

			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end

				if not is_displayed then
					if term_win_open and vim.fn.win_id2win(vim.t.term_winid) > 0 then
						vim.api.nvim_win_call(vim.t.term_winid, function()
							set_terminal_winbar()
						end)
					end
					return
				end

				if next_buf then
					if vim.t.term_winid and vim.fn.win_id2win(vim.t.term_winid) > 0 then
						vim.api.nvim_win_call(vim.t.term_winid, function()
							set_terminal_winbar()
						end)
					end
				else
					if vim.t.term_winid and vim.fn.win_id2win(vim.t.term_winid) > 0 then
						if vim.fn.win_getid() == vim.t.term_winid then
							vim.cmd("wincmd p")
						end
						if is_float_mode() then
							vim.api.nvim_win_close(vim.t.term_winid, true)
						else
							local term_winnr = vim.fn.win_id2win(vim.t.term_winid)
							if term_winnr > 0 then
								vim.cmd(term_winnr .. "close")
							end
						end
					end
					vim.t.term_winid = nil
					vim.t.term_bufnr = nil
				end
			end)
		end,
	})
end

local function setup_winbar_autocmds()
	if not M.config.winbar then
		return
	end

	vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter", "BufFilePost" }, {
		pattern = "*",
		group = "Term",
		callback = function()
			if vim.bo[0].buftype == "terminal" then
				set_terminal_winbar()
			end
		end,
	})

	vim.api.nvim_create_autocmd("TermRequest", {
		pattern = "*",
		group = "Term",
		callback = function(ev)
			local seq = ev.data.sequence

			if seq:match("^\x1b%]0;") then
				local title = seq:match("\x1b%]0;([^;\007]+)")
				if title and #title > 0 then
					local buf = ev.buf
					vim.b[buf].term_title = title
					set_terminal_winbar()
				end
			end
		end,
	})
end

local function setup_keymap()
	local keys = M.config.keys
	if keys == false then
		return
	end

	local function map(modes, key, action, opts)
		if key == false then
			return
		end
		vim.keymap.set(modes, key, action, opts or {})
	end

	map({ "n", "t" }, keys.toggle, M.toggle)
	map("t", keys.normal_mode, "<C-\\><C-n>", { noremap = true })
	map({ "n", "t" }, keys.zoom, M.zoom)
	map({ "n", "t" }, keys.reset_height, M.reset_height)
	map({ "n", "t" }, keys.new, M.new, { noremap = true })
	map({ "n", "t" }, keys.delete, M.delete, { noremap = true })

	map({ "n", "t" }, keys.prev, function()
		M.switch(-1)
	end)
	map({ "n", "t" }, keys.next, function()
		M.switch(1)
	end)

	map({ "n", "t" }, keys.move_prev, function()
		M.move(-1)
	end)
	map({ "n", "t" }, keys.move_next, function()
		M.move(1)
	end)

	for i = 1, 9 do
		vim.keymap.set({ "n", "t" }, "<C-S-" .. i .. ">", function()
			M.go_to(i)
		end, { noremap = true })
	end

	local function switch_tab(direction)
		local src_mode = vim.fn.mode()
		if vim.bo.buftype == "terminal" then
			vim.b.term_mode = src_mode
		end
		if src_mode == "t" then
			vim.cmd("stopinsert")
		end
		if direction > 0 then
			vim.cmd("tabnext")
		else
			vim.cmd("tabprevious")
		end
		vim.schedule(function()
			if vim.bo.buftype == "terminal" then
				if vim.b.term_mode == "t" or vim.b.term_mode == nil then
					vim.cmd("startinsert")
				end
			end
		end)
	end

	map({ "n", "t" }, keys.tab_prev, function()
		switch_tab(-1)
	end, { noremap = true })
	map({ "n", "t" }, keys.tab_next, function()
		switch_tab(1)
	end, { noremap = true })

	if keys.paste_register ~= false then
		vim.keymap.set("t", keys.paste_register, function()
			local ok, char = pcall(vim.fn.getchar)
			if not ok or char < 0 then
				return
			end
			local reg = vim.fn.nr2char(char)
			local txt = vim.fn.getreg(reg)

			local job = vim.b.terminal_job_id
			if not job then
				vim.notify("Not in a terminal buffer!", vim.log.levels.WARN)
				return
			end
			vim.api.nvim_chan_send(job, txt)
		end, { noremap = true, silent = true })

		vim.keymap.set("t", keys.paste_register .. "=", function()
			local expr = vim.fn.input("=")
			if expr == "" then
				return
			end

			local ok, result = pcall(vim.fn.eval, expr)
			if not ok then
				vim.notify("Invalid expression: " .. result, vim.log.levels.ERROR)
				return
			end

			local txt = tostring(result)
			local opener = "\027[200~"
			local closer = "\027[201~"

			local job = vim.b.terminal_job_id
			if not job then
				vim.notify("Not in a terminal buffer!", vim.log.levels.WARN)
				return
			end
			vim.api.nvim_chan_send(job, opener .. txt .. closer)
		end, { noremap = true, silent = true })
	end
end

local function setup_command()
	vim.api.nvim_create_user_command("TermSplit", "new | term", {})
	vim.api.nvim_create_user_command("TermVsplit", "vnew | term", {})
	vim.api.nvim_create_user_command("TermTab", function(opts)
		vim.cmd(opts.args .. "tabnew | term")
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("TermDelete", function()
		M.delete()
	end, {})
	vim.api.nvim_create_user_command("TermReset", 'exe "te" | bd!# | let t:term_bufnr = bufnr("%")', {})
end

local function setup_alias()
	utils.alias("tsplit", "TermSplit")
	utils.alias("tvsplit", "TermVsplit")
	utils.alias("ttab", "TermTab")
	utils.alias("tdelete", "TermDelete")
	utils.alias("st", "TermSplit")
	utils.alias("vst", "TermVsplit")
	utils.alias("tt", "TermTab")
	utils.alias("td", "TermDelete")
end

function M.setup(config)
	M.config = vim.tbl_extend("force", M.config, config or {})

	if M.config.keys ~= false then
		local default_keys = {
			toggle = "<C-->",
			normal_mode = "<C-;>",
			zoom = "<C-S-->",
			new = "<C-S-n>",
			delete = "<C-S-c>",
			prev = "<C-S-[>",
			next = "<C-S-]>",
			move_prev = "<C-S-M-[>",
			move_next = "<C-S-M-]>",
			paste_register = "<C-S-r>",
			reset_height = "<C-S-=>",
			tab_next = "<C-PageDown>",
			tab_prev = "<C-PageUp>",
		}
		M.config.keys = vim.tbl_extend("force", default_keys, M.config.keys or {})
	end

	if loaded then
		return
	end

	setup_vars()
	setup_autocmd()
	setup_winbar_autocmds()
	setup_keymap()
	setup_command()
	setup_alias()

	require("terminal.job").setup()
	require("terminal.fugitive").setup()

	loaded = true
end

return M
