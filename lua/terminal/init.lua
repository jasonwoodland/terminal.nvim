local M = {}

local loaded = false

M.config = {
	cycle_normal_mode = false,
	cycle_terminal_mode = false,
	height = 24,
	winbar = true,
}

local utils = require("terminal.utils")

local function get_term_height()
	if M.config.height < 1 then
		return vim.o.lines * M.config.height
	end
	return M.config.height
end

local function save_term_height()
	if vim.fn.exists("t:term_bufnr") ~= 0 then
		vim.t.term_height = vim.fn.winheight(vim.fn.bufwinnr(vim.t.term_bufnr))
	end
end

local function get_winbar_height()
	return M.config.winbar and 1 or 0
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
	-- if a terminal window is open
	if vim.t.term_winid ~= 0 and vim.fn.win_id2win(vim.t.term_winid) > 0 then
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
		vim.t.term_height = vim.fn.winheight(vim.fn.bufwinnr(vim.g.term_bufnr)) + get_winbar_height()
		vim.cmd(vim.fn.bufwinnr(vim.g.term_bufnr) .. "close")
		if vim.t.current_win > 0 then
			vim.api.nvim_set_current_win(vim.t.current_win)
		end
	else
		-- open the terminal
		vim.t.current_win = vim.fn.win_getid()
		vim.t.prev_winid = vim.fn.win_getid()
		if vim.fn.exists("g:term_bufnr") ~= 0 and vim.fn.bufexists(vim.g.term_bufnr) ~= 0 then
			vim.cmd("botright sb" .. vim.g.term_bufnr)
			vim.t.term_winid = vim.fn.win_getid()
		else
			vim.cmd("botright sp term://" .. vim.env.SHELL)
			vim.cmd [[ autocmd TermClose <buffer> execute "bdelete! " . expand("<abuf>") ]]
		end

		local terminal_height = height > 1 and height or vim.t.term_height
		vim.cmd("res " .. terminal_height)
		vim.cmd("set wfh")
		vim.g.term_bufnr = vim.fn.bufnr()
		vim.t.term_winid = vim.fn.win_getid()
		vim.cmd("startinsert")
	end
end

local function setup_vars()
	vim.g.term_bufnr = vim.g.term_bufnr or nil
	vim.t.term_winid = vim.g.term_winid or 0
	vim.t.term_height = vim.t.term_height or get_term_height()
	vim.t.current_win = vim.t.current_win or 0
end

local function setup_autocmd()
	vim.api.nvim_create_augroup("Terminal", {})
	vim.api.nvim_create_autocmd("TermOpen", {
		pattern = "*",
		group = "Terminal",
		callback = function()
			vim.opt_local.signcolumn = "no"
			vim.opt_local.number = false
			vim.opt_local.relativenumber = false
			vim.opt_local.scrolloff = 0

			-- vim.wo.display = ""
		end
	})
	vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter" }, {
		pattern = { "*" },
		group = "Terminal",
		callback = function()
			if vim.opt.buftype:get() == "terminal" then
				-- vim.cmd("startinsert")
			end
		end
	})
	vim.api.nvim_create_autocmd("TabNew", {
		pattern = "*",
		group = "Terminal",
		callback = function()
			vim.t.term_height = get_term_height()
		end
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		pattern = "*",
		group = "Terminal",
		callback = function()
			save_term_height()
		end
	})
end

local function setup_keymap()
	vim.keymap.set("n", "<C-Space>", toggle_term)
	vim.keymap.set("t", "<C-Space>", toggle_term)
	vim.keymap.set("t", "<C-PageUp>", "<C-\\><C-n><C-PageUp>", { noremap = true })
	vim.keymap.set("t", "<C-PageDown>", [[<C-\><C-n><C-PageDown>]], { noremap = true })
	vim.keymap.set("t", "<C-;>", "<C-\\><C-n>", { noremap = true })
	vim.cmd [[
		tnoremap <expr> <C-R> '<C-\><C-N>"'.nr2char(getchar()).'pi'
	]]
	-- vim.keymap.set("t", "<C-\\><C-\\>", "<C-\\><C-\\>", { noremap = true })
	-- vim.keymap.set("t", "<C-\\><C-O>", "<C-\\><C-O>", { noremap = true })

	-- vim.keymap.set("t", "<C-W>", "<C-\\><C-N><C-W>", { noremap = true })
	-- vim.keymap.set("t", "<C-W>.", "<C-W>", { noremap = true })
	-- vim.keymap.set("t", "<C-W><C-.>", "<C-W>", { noremap = true })
	-- vim.keymap.set("t", "<C-W>/", "<C-W><C-N>/", { noremap = true })
	-- vim.keymap.set("t", "<C-W>?", "<C-W><C-N>?", { noremap = true })
	-- vim.keymap.set("t", "<C-W><C-O>", "<C-\\><C-O>", { noremap = true })

	-- vim.keymap.set("t", "<C-\\><Esc>", "<C-\\><C-n>", { noremap = true })
	-- vim.keymap.set("t", "<C-\\><C-W>", "<C-\\><C-n><C-w>", { noremap = true })
	-- vim.keymap.set("t", "<C-\\>:", "<C-\\><C-n>:", { noremap = true })
	-- vim.keymap.set("t", "<C-\\><C-R>", "<C-\\><C-N>", {
	-- 	-- expr = true,
	-- 	callback = function()
	-- 		local char = vim.fn.nr2char(vim.fn.getchar())
	-- 		if char == "=" then
	-- 			vim.fn.mode("n")
	-- 			-- vim.api.nvim_input("<C-\\><C-N>")
	-- 			vim.ui.input({ prompt = "=", completion = "expression" }, function(input)
	-- 				if input == "" then
	-- 					return -- User pressed <Esc> or canceled the input
	-- 				end

	-- 				-- Evaluate the expression safely
	-- 				local status, result = pcall(loadstring, "return " .. input)
	-- 				if not status then
	-- 					vim.api.nvim_err_writeln("Error: " .. result)
	-- 					return
	-- 				elseif result ~= nil then
	-- 					vim.api.nvim_put({ tostring(result()) }, "c", false, true)
	-- 				end
	-- 			end)
	-- 			-- local input = vim.fn.input({ prompt = "=", completion = "expression" })
	-- 			-- if input == "" then
	-- 			-- 	return -- User pressed <Esc> or canceled the input
	-- 			-- end

	-- 			-- -- Evaluate the expression safely
	-- 			-- local status, result = pcall(loadstring, "return " .. input)
	-- 			-- if not status then
	-- 			-- 	vim.api.nvim_err_writeln("Error: " .. result)
	-- 			-- 	return
	-- 			-- elseif result ~= nil then
	-- 			-- 	vim.api.nvim_put({ tostring(result()) }, "c", false, true)
	-- 			-- end
	-- 		else
	-- 			local reg = vim.fn.getreg(char)
	-- 			vim.api.nvim_put({ reg }, "c", false, true)

	-- 			-- return "" .. char .. "pi"
	-- 		end
	-- 	end,
	-- })
	vim.keymap.set("n", "<C-S-[>", function() SwitchTerminal(-1) end)
	vim.keymap.set("n", "<C-S-]>", function() SwitchTerminal(1) end)
	vim.keymap.set("t", "<C-S-[>", function() SwitchTerminal(-1) end)
	vim.keymap.set("t", "<C-S-]>", function() SwitchTerminal(1) end)
end

local function setup_command()
	vim.cmd("command! -nargs=0 TerminalSplit :new|term")
	vim.cmd("command! -nargs=0 TerminalVsplit :vnew|term")
	vim.cmd("command! -nargs=? TerminalTab :<args>tabnew|term")
	vim.cmd("command! -nargs=0 TerminalClose :lua CloseTerminal()")
	vim.cmd("command! -nargs=0 TerminalReset :exe \"te\"|bd!#|let t:term_bufnr = bufnr(\"%\")")
end

local function setup_alias()
	utils.alias("st", "TerminalSplit")
	utils.alias("vt", "TerminalVsplit")
	utils.alias("tt", "TerminalTab")
	utils.alias("tc", "TerminalClose")
end


function SwitchTerminal(delta)
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

	local b = bufs[(i) % #bufs + 1]
	vim.cmd("buffer " .. b)
end

function CloseTerminal()
	if vim.bo.buftype ~= "terminal" then return end
	SwitchTerminal(-1)
	if _G.term_bufnr ~= vim.fn.bufnr("%") then
		vim.cmd("bdelete!" .. vim.fn.bufnr("%"))
		_G.term_bufnr = vim.fn.bufnr("%")
	else
		vim.cmd("bdelete!")
	end
end

function TerminalJob(cmd, cb)
	vim.cmd("bot new +resize10")
	local bufnr = vim.fn.bufnr()
	vim.fn.termopen(cmd, {
		on_exit = function(job_id, code, event)
			if code == 0 then
				vim.cmd("bd" .. bufnr)
				if cb then cb() end
			else
				vim.cmd("wincmd p")
				vim.cmd("resize " .. get_term_height())
				vim.cmd("startinsert")
			end
		end
	})
	vim.cmd("norm G")
	_G.terminal_job_bufnr = bufnr
	vim.cmd("wincmd p")
end

function TerminalJobClose()
	vim.cmd("bd!" .. _G.terminal_job_bufnr)
end

function FugitiveJob(cmd)
	TerminalJob(cmd, ReloadFugitiveBuffers)
end

vim.cmd("command! -nargs=1 -complete=shellcmd TerminalJob lua TerminalJob(<q-args>)")
vim.cmd("command! -nargs=1 -complete=shellcmd FugitiveJob lua FugitiveJob(<q-args>)")
vim.cmd("command! TerminalJobClose lua TerminalJobClose()")

vim.cmd("cabbrev tj TerminalJob")
vim.cmd("cabbrev tjc TerminalJobClose")

function ReloadFugitiveBuffers()
	vim.cmd("call FugitiveDidChange()")
	print("Reloading fugitive buffers")
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
	local function get_terminal_buffers()
		local terminal_buffers = {}
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_option(buf, 'buftype') == 'terminal' then
				table.insert(terminal_buffers, buf)
			end
		end
		return terminal_buffers
	end

	local function format_terminal_buffers(terminal_buffers)
		local buffer_names = {}
		local current_buf = vim.api.nvim_get_current_buf()
		for _, buf in ipairs(terminal_buffers) do
			local buf_name = vim.api.nvim_buf_get_name(buf)

			-- Shorten the buffer name (example: use only the last part of the path)
			local shortened_name = buf_name:match("[^/:]+$") or buf_name

			if buf == current_buf then
				table.insert(buffer_names, "%#WinBarActive# " .. shortened_name .. " %*")
			else
				table.insert(buffer_names, " " .. shortened_name .. " ")
			end
		end
		return table.concat(buffer_names)
	end

	local function set_terminal_winbar()
		local terminal_buffers = get_terminal_buffers()
		if #terminal_buffers > 0 then
			vim.wo.winbar = format_terminal_buffers(terminal_buffers);
		end
	end

	-- Call the function to set the winbar whenever a terminal buffer is entered
	vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter", "BufFilePost" }, {
		pattern = "*",
		callback = function()
			if vim.api.nvim_buf_get_option(0, 'buftype') == 'terminal' then
				set_terminal_winbar()
			end
		end
	})
end

return M
