local M = {}

local loaded = false

M.config = {
	cycle_normal_mode = false,
	cycle_terminal_mode = false,
	height = 24,
	winbar = true,
	float = false,
	float_zoom = true,
}

local utils = require("terminal.utils")

local function get_term_height()
	if M.config.height < 1 then
		return vim.o.lines * M.config.height
	end
	return M.config.height
end

local function get_winbar_height()
	return M.config.winbar and 1 or 0
end

local function save_term_height()
	if vim.fn.exists("t:term_bufnr") ~= 0 then
		vim.t.term_height = vim.fn.winheight(vim.fn.bufwinnr(vim.t.term_bufnr)) - get_winbar_height()
	end
end

local function get_terminal_buffers()
	local terminal_buffers = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_option(buf, "buftype") == "terminal" then
			table.insert(terminal_buffers, buf)
		end
	end
	return terminal_buffers
end

local function format_terminal_buffers(terminal_buffers)
	local buffer_names = {}
	local current_buf = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(terminal_buffers) do
		local fn_name = "TermWinbarClick" .. buf
		-- _G[fn_name] = function()
		-- 	vim.cmd("buffer " .. buf)
		-- end

		_G[fn_name] = function()
			vim.cmd("buffer " .. buf)
		end

		local buf_name = vim.api.nvim_buf_get_name(buf)
		buf_name = vim.b[buf].term_title:match("^[^ ]+") or buf_name

		local shortened_name = buf_name:match("[^/:]+$") or buf_name
		shortened_name = vim.fn.substitute(buf_name, "\\v([^/]+)/", "\\=strpart(submatch(1), 0, 1) . '/'", "g")

		local styled_name
		if buf == current_buf then
			styled_name = "%#WinBarActive# " .. shortened_name .. " %*"
		else
			styled_name = " " .. shortened_name .. " "
		end

		local clickable_name = "%@v:lua.TermWinbarClick" .. buf .. "@" .. styled_name .. "%T"

		table.insert(buffer_names, clickable_name)
	end
	return table.concat(buffer_names)
end

local function set_terminal_winbar()
	local terminal_buffers = get_terminal_buffers()
	if #terminal_buffers > 0 then
		vim.wo.winbar = format_terminal_buffers(terminal_buffers)
	end
end

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
			-- zindex = 100,
		}
	end

	local float_config = {
		padding = { x = 24, y = 4 },
		border = "rounded",
	}

	-- If M.config.float is a table, merge with default config
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

local function create_float_win(bufnr)
	local win = vim.api.nvim_open_win(bufnr, true, get_float_win_config())
	vim.api.nvim_win_set_option(win, "winblend", 0)
	return win
end

local function toggle_term()
	local height = vim.v.count1
	if M.config.cycle_normal_mode then
		-- if in terminal mode, switch to normal mode
		if vim.api.nvim_get_mode().mode == "t" then
			vim.cmd("stopinsert")
			return
		end
	end
	if #vim.api.nvim_tabpage_list_wins(0) == 1 and not M.config.float then
		vim.t.term_winid = nil
	end

	-- if a terminal window is open
	if
		vim.t.term_winid ~= 0
		and vim.fn.win_id2win(vim.t.term_winid) > 0
		and (#vim.api.nvim_tabpage_list_wins(0) > 1 or M.config.float)
	then
		if M.config.cycle_terminal_mode then
			-- if the terminal window is not the current window, set as current window
			if vim.fn.win_getid() ~= vim.t.term_winid then
				vim.t.current_win = vim.fn.win_getid()
				vim.api.nvim_set_current_win(vim.t.term_winid)
				vim.cmd("startinsert")
				return
			end
		end
		-- close the terminal
		vim.g.term_bufnr = vim.api.nvim_win_get_buf(vim.t.term_winid)
		vim.t.term_mode = vim.fn.mode()
		-- Save cursor/scroll position
		vim.b[vim.g.term_bufnr].term_view = vim.fn.winsaveview()
		local term_winnr = vim.fn.bufwinnr(vim.g.term_bufnr)

		if M.config.float then
			-- Close floating window
			vim.api.nvim_win_close(vim.t.term_winid, true)
			vim.t.term_winid = nil
		else
			if vim.fn.win_getid() == vim.t.term_winid then
				vim.cmd("wincmd p")
			end
			-- local current_win_before_close = vim.fn.win_getid()
			vim.cmd(term_winnr .. "close")
			-- if
			--     term_winnr == current_win_before_close
			--     and vim.t.current_win > 0
			--     and vim.fn.win_id2win(vim.t.current_win) > 0
			-- then
			-- 	vim.api.nvim_set_current_win(vim.t.current_win)
			-- end
		end
	else
		-- open the terminal
		vim.t.current_win = vim.fn.win_getid()
		vim.t.prev_winid = vim.fn.win_getid()

		if M.config.float then
			if vim.fn.exists("g:term_bufnr") ~= 0 and vim.fn.bufexists(vim.g.term_bufnr) ~= 0 then
				vim.t.term_winid = create_float_win(vim.g.term_bufnr)
			else
				-- Create a new terminal buffer
				local bufnr = vim.api.nvim_create_buf(false, true)
				vim.t.term_winid = create_float_win(bufnr)
				vim.fn.termopen(vim.env.SHELL)
				vim.g.term_bufnr = bufnr
			end
		else
			if vim.fn.exists("g:term_bufnr") ~= 0 and vim.fn.bufexists(vim.g.term_bufnr) ~= 0 then
				vim.cmd("botright sb" .. vim.g.term_bufnr)
				vim.t.term_winid = vim.fn.win_getid()
			else
				vim.cmd("botright sp term://" .. vim.env.SHELL)
			end

			local terminal_height = height > 1 and height or vim.t.term_height
			vim.cmd("res " .. terminal_height)
			vim.cmd("set wfh")
			vim.g.term_bufnr = vim.fn.bufnr()
			vim.t.term_winid = vim.fn.win_getid()
		end

		-- Restore cursor/scroll position
		if vim.b[vim.g.term_bufnr].term_view then
			vim.fn.winrestview(vim.b[vim.g.term_bufnr].term_view)
		end

		if vim.t.term_mode ~= "n" then
			vim.cmd("startinsert")
		end
	end
end

local function toggle_zoom()
	if M.config.float then
		vim.t.term_zoom = not vim.t.term_zoom
		local win_config = get_float_win_config()
		if vim.t.term_winid ~= 0 and vim.fn.win_id2win(vim.t.term_winid) > 0 then
			vim.api.nvim_win_set_config(vim.t.term_winid, win_config)
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

local function setup_vars()
	vim.g.term_bufnr = vim.g.term_bufnr or nil
	vim.t.term_winid = vim.g.term_winid or 0
	vim.t.term_height = vim.t.term_height or get_term_height()
	vim.t.current_win = vim.t.current_win or 0
end

local function setup_autocmd()
	vim.api.nvim_create_augroup("Term", {})
	vim.api.nvim_create_autocmd("TermOpen", {
		pattern = "*",
		group = "Term",
		callback = function()
			vim.opt_local.signcolumn = "no"
			vim.opt_local.number = false
			vim.opt_local.relativenumber = false
			vim.opt_local.scrolloff = 0
			vim.opt_local.sidescrolloff = 0
		end,
	})
	vim.api.nvim_create_autocmd("WinResized", {
		pattern = "*",
		group = "Term",
		callback = function()
			if vim.g.term_bufnr == nil then
				return
			end
			local height = vim.fn.winheight(vim.fn.bufwinnr(vim.g.term_bufnr))
			if height == -1 then
				return
			end
			vim.t.term_height = height + get_winbar_height()
		end,
	})
	vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter" }, {
		pattern = { "*" },
		group = "Term",
		callback = function()
			if vim.opt.buftype:get() == "terminal" then
				-- vim.cmd("startinsert")
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
end

local function setup_keymap()
	vim.keymap.set("n", "<C-->", toggle_term)
	vim.keymap.set("t", "<C-->", toggle_term)
	vim.keymap.set("t", "<C-;>", "<C-\\><C-n>", { noremap = true })
	vim.keymap.set("n", "<C-S-->", toggle_zoom)
	vim.keymap.set("t", "<C-S-->", toggle_zoom)
	vim.keymap.set("t", "<C-PageUp>", "<C-\\><C-n><C-PageUp>", { noremap = true })
	vim.keymap.set("t", "<C-PageDown>", [[<C-\><C-n><C-PageDown>]], { noremap = true })

	-- C-w convenience mappings
	-- vim.keymap.set("t", "<C-W>", "<C-\\><C-N><C-W>", { noremap = true })
	-- vim.keymap.set("t", "<C-W>.", "<C-W>", { noremap = true })
	-- vim.keymap.set("t", "<C-W><C-.>", "<C-W>", { noremap = true })
	-- vim.keymap.set("t", "<C-W>/", "<C-W><C-N>/", { noremap = true })
	-- vim.keymap.set("t", "<C-W>?", "<C-W><C-N>?", { noremap = true })
	-- vim.keymap.set("t", "<C-W><C-O>", "<C-\\><C-O>", { noremap = true })

	-- C-S-x convenience mappings
	vim.keymap.set("n", "<C-S-n>", "<cmd>terminal<cr>", { noremap = true })
	vim.keymap.set("t", "<C-S-n>", "<cmd>terminal<cr>", { noremap = true })
	vim.keymap.set("n", "<C-S-d>", TermDelete, { noremap = true })
	vim.keymap.set("t", "<C-S-d>", TermDelete, { noremap = true })

	-- Term tab switching
	vim.keymap.set("n", "<C-S-[>", function()
		SwitchTerm(-1)
	end)
	vim.keymap.set("n", "<C-S-]>", function()
		SwitchTerm(1)
	end)
	vim.keymap.set("t", "<C-S-[>", function()
		SwitchTerm(-1)
	end)
	vim.keymap.set("t", "<C-S-]>", function()
		SwitchTerm(1)
	end)

	local opts = { noremap = true, silent = true }

	vim.keymap.set("t", "<C-S-r>", function()
		-- grab one keystroke for the register name
		local ok, char = pcall(vim.fn.getchar)
		if not ok or char < 0 then
			return
		end
		local reg = vim.fn.nr2char(char)

		-- fetch the register as a string
		local txt = vim.fn.getreg(reg)

		-- wrap in bracketed-paste
		local opener = "\027[200~" -- \e[200~
		local closer = "\027[201~" -- \e[201~
		opener = ""
		closer = ""

		-- send to the terminal’s PTY
		local job = vim.b.terminal_job_id
		if not job then
			vim.notify("Not in a terminal buffer!", vim.log.levels.WARN)
			return
		end
		vim.api.nvim_chan_send(job, opener .. txt .. closer)
	end, opts)

	vim.keymap.set("t", "<C-S-r>=", function()
		-- 1) prompt for a Vim expression
		local expr = vim.fn.input("=")
		if expr == "" then
			return
		end

		-- 2) evaluate it
		local ok, result = pcall(vim.fn.eval, expr)
		if not ok then
			vim.notify("Invalid expression: " .. result, vim.log.levels.ERROR)
			return
		end

		-- 3) turn it into a string
		local txt = tostring(result)

		-- 4) wrap in bracketed-paste so the shell sees it as one atomic paste
		local opener = "\027[200~"
		local closer = "\027[201~"

		-- 5) send to the terminal job
		local job = vim.b.terminal_job_id
		if not job then
			vim.notify("Not in a terminal buffer!", vim.log.levels.WARN)
			return
		end
		vim.api.nvim_chan_send(job, opener .. txt .. closer)
	end, opts)
end

local function setup_command()
	vim.cmd("command! -nargs=0 TermSplit :new|term")
	vim.cmd("command! -nargs=0 TermVsplit :vnew|term")
	vim.cmd("command! -nargs=? TermTab :<args>tabnew|term")
	vim.cmd("command! -nargs=0 TermDelete :lua TermDelete()")
	vim.cmd('command! -nargs=0 TermReset :exe "te"|bd!#|let t:term_bufnr = bufnr("%")')
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

function SwitchTerm(delta, clamp)
	local bufs = {}
	for i = 1, vim.fn.bufnr("$") do
		if vim.fn.getbufvar(i, "&buftype") == "terminal" then
			table.insert(bufs, i)
		end
	end

	local i = vim.fn.index(bufs, vim.fn.bufnr("%"))
	if i == nil then
		i = delta == 1 and #bufs or 1
	else
		i = i + delta
	end

	local b
	if clamp then
		b = bufs[math.max(1, math.min(#bufs, i))]
	else
		b = bufs[i % #bufs + 1]
	end
	if b ~= nil then
		-- Save current buffer's mode
		vim.b.term_mode = vim.fn.mode()
		vim.cmd("buffer " .. b)
		-- Restore target buffer's mode
		if vim.b.term_mode ~= "n" then
			vim.cmd("startinsert")
		else
			vim.cmd("stopinsert")
		end
	end
end

local function get_next_terminal_buffer_before_close()
	local bufs = get_terminal_buffers()

	local i
	local bufnr = vim.fn.bufnr()
	for j = 1, #bufs do
		if bufs[j] == bufnr then
			i = j
			break
		end
	end
	table.remove(bufs, i)

	if i > #bufs then
		i = #bufs
	end

	return bufs[i]
end

function TermDelete()
	if vim.bo.buftype ~= "terminal" then
		return
	end
	local bufnr = vim.fn.bufnr()
	local b = get_next_terminal_buffer_before_close()
	if b ~= nil then
		vim.cmd("buffer " .. b)
	end
	vim.api.nvim_buf_delete(bufnr, { force = true })
	if b ~= nil then
		set_terminal_winbar()
	end
end

function TermJob(cmd, cb)
	vim.cmd("bot new +resize10")
	local bufnr = vim.fn.bufnr()
	vim.fn.termopen(cmd, {
		on_exit = function(job_id, code, event)
			if code == 0 then
				vim.cmd("bd" .. bufnr)
				if cb then
					cb()
				end
			else
				vim.cmd("wincmd p")
				vim.cmd("resize " .. get_term_height())
				vim.cmd("startinsert")
			end
		end,
	})
	vim.cmd("norm G")
	_G.terminal_job_bufnr = bufnr
	vim.cmd("wincmd p")
end

function TermJobClose()
	vim.cmd("bd!" .. _G.terminal_job_bufnr)
end

function FugitiveJob(cmd)
	TermJob(cmd, ReloadFugitiveBuffers)
end

vim.cmd("command! -nargs=1 -complete=shellcmd TermJob lua TermJob(<q-args>)")
vim.cmd("command! -nargs=1 -complete=shellcmd FugitiveJob lua FugitiveJob(<q-args>)")
vim.cmd("command! TermJobClose lua TermJobClose()")

vim.cmd("cabbrev tj TermJob")
vim.cmd("cabbrev tjc TermJobClose")

function ReloadFugitiveBuffers()
	vim.cmd("call FugitiveDidChange()")
	-- print("Reloading fugitive buffers")
	-- local buf_list = vim.api.nvim_list_bufs()
	-- local current_buf = vim.api.nvim_get_current_buf()

	-- for _, buf_id in ipairs(buf_list) do
	-- 	local buf_name = vim.api.nvim_buf_get_name(buf_id)
	-- 	if string.find(buf_name, 'fugitive:') then
	-- 		print("Reloading " .. buf_name)
	-- 		vim.api.nvim_set_current_buf(buf_id)
	-- 		vim.cmd('edit!')
	-- 	end
	-- end
	-- vim.api.nvim_set_current_buf(current_buf)
end

function M.setup(config)
	M.config = vim.tbl_extend("force", M.config, config or {})

	if loaded then
		return
	end

	setup_vars()
	setup_autocmd()
	setup_keymap()
	setup_command()
	setup_alias()

	loaded = true
end

---
---

local always_insert = {}

local term_mode_bufnrs = {}

-- function always_insert.enable()
-- 	-- Function to enter insert mode
-- 	vim.api.nvim_create_autocmd({ "TermOpen" }, {
-- 		pattern = "*",
-- 		callback = function()
-- 			vim.api.nvim_command("startinsert")

-- 			local bufnr = vim.fn.bufnr()
-- 			local function enter_insert_mode()
-- 				if vim.opt.buftype:get() == "terminal" and term_mode_bufnrs[vim.fn.bufnr()] ~= false then
-- 					-- print(vim.inspect(vim.api.nvim_get_mode()))
-- 					if vim.api.nvim_get_mode().mode == "nt" then
-- 						vim.api.nvim_command("startinsert")
-- 						term_mode_bufnrs[vim.fn.bufnr()] = true
-- 					end
-- 				else
-- 					term_mode_bufnrs[vim.fn.bufnr()] = false
-- 					vim.api.nvim_command("stopinsert")
-- 				end
-- 			end

-- 			-- Autocmds to trigger i  -- Autocmds to trigger insert mode
-- 			vim.api.nvim_create_autocmd({ "ModeChanged" }, {
-- 				buffer = bufnr,
-- 				callback = enter_insert_mode,
-- 				group = "always_insert",
-- 			})

-- 			vim.keymap.set("t", "<C-W>N", function()
-- 				vim.api.nvim_command("stopinsert")
-- 				term_mode_bufnrs[vim.fn.bufnr()] = false
-- 			end, {
-- 				buffer = true
-- 			})
-- 			vim.keymap.set("n", "i", function()
-- 				vim.api.nvim_command("startinsert")
-- 				if vim.opt.buftype:get() == "terminal" then
-- 					-- set eof fillchar
-- 					term_mode_bufnrs[vim.fn.bufnr()] = true
-- 				end
-- 			end, {
-- 				buffer = true
-- 			})
-- 		end,
-- 		group = "always_insert",
-- 	})
-- end

-- function always_insert.disable()
-- 	-- Clear all autocmds created by this plugin
-- 	vim.api.nvim_clear_autocmds({ group = "always_insert" })
-- end

-- -- Create an augroup to manage autocmds
-- vim.api.nvim_create_augroup("always_insert", { clear = true })

-- -- Enable the plugin by default
-- always_insert.enable()

---
---

if M.config.winbar then
	vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter", "BufFilePost" }, {
		pattern = "*",
		callback = function()
			if vim.api.nvim_get_option_value("buftype", { buf = 0 }) == "terminal" then
				set_terminal_winbar()
			end
		end,
	})

	vim.api.nvim_create_autocmd("TermRequest", {
		pattern = "*",
		callback = function(ev)
			local seq = ev.data.sequence

			-- print(seq)

			if seq:match("^\x1b%]0;") then
				-- print("MATCH")
				local title = seq:match("\x1b%]0;([^;\007]+)")
				if title and #title > 0 then
					local buf = ev.buf
					local win = vim.fn.bufwinid(buf)
					local shown_title = "[Terminal] " .. title
					-- Store title as variable, or rename the buffer
					vim.b[buf].term_title = title
					-- vim.api.nvim_buf_set_name(buf, shown_title)
					set_terminal_winbar()
				end
			end
		end,
	})
end

return M
