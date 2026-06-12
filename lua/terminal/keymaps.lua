-- terminal.nvim: keymap registration

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local mode = require("terminal.mode")
local window = require("terminal.window")
local float_layout = require("terminal.float_layout")
local panes = require("terminal.panes")
local digraph = require("terminal.digraph")

function M.setup(api)
	local keys = config.config.keys
	if keys == false then
		return
	end

	local function map(modes, key, action, opts)
		if key == false then
			return
		end
		if type(key) == "table" then
			for _, k in ipairs(key) do
				map(modes, k, action, opts)
			end
			return
		end
		vim.keymap.set(modes, key, action, opts or {})
	end

	map({ "n", "t" }, keys.toggle, api.toggle)
	map("t", keys.normal_mode, "<C-\\><C-n>", { noremap = true })
	map({ "n", "t" }, keys.zoom, api.zoom)
	map({ "n", "t" }, keys.float_toggle, api.float_toggle)
	map({ "n", "t" }, keys.reset_height, api.reset_height)
	map({ "n", "t" }, keys.new, api.new, { noremap = true })
	map({ "n", "t" }, keys.delete, api.delete, { noremap = true })

	map({ "n", "t" }, keys.prev, function()
		api.switch(-1)
	end)
	map({ "n", "t" }, keys.next, function()
		api.switch(1)
	end)

	map({ "n", "t" }, keys.move_prev, function()
		api.move(-1)
	end)
	map({ "n", "t" }, keys.move_next, function()
		api.move(1)
	end)

	map({ "n", "t" }, keys.move_to_vim_tab_prev, function()
		api.move_to_vim_tab(-1)
	end)
	map({ "n", "t" }, keys.move_to_vim_tab_next, function()
		api.move_to_vim_tab(1)
	end)

	map({ "n", "t" }, keys.last_notification, api.go_to_notification, { noremap = true })

	if type(keys.go_to_tab) == "string" then
		for i = 1, 9 do
			local key = keys.go_to_tab:format(i)
			if key ~= keys.last_notification then
				vim.keymap.set({ "n", "t" }, key, function()
					api.go_to(i)
				end, { noremap = true })
			end
		end
	end

	local function switch_vim_tab(direction)
		local src_mode = mode.record()
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
				mode.restore_current()
			end
		end)
	end

	map({ "n", "t" }, keys.vim_tab_prev, function()
		switch_vim_tab(-1)
	end, { noremap = true })
	map({ "n", "t" }, keys.vim_tab_next, function()
		switch_vim_tab(1)
	end, { noremap = true })

	local function move_vim_tab(direction)
		local current = vim.fn.tabpagenr()
		local last = vim.fn.tabpagenr("$")
		if last < 2 then
			return
		end
		-- :tabmove N places the tab *after* tab N
		local target
		if direction == -1 then
			target = current - 2
		else
			target = current + 1
		end
		if target < 0 then
			target = last
		elseif target > last then
			target = 0
		end
		vim.cmd("tabmove " .. target)
	end

	map({ "n", "t" }, keys.vim_tab_move_prev, function()
		move_vim_tab(-1)
	end, { noremap = true })
	map({ "n", "t" }, keys.vim_tab_move_next, function()
		move_vim_tab(1)
	end, { noremap = true })

	if keys.paste_register ~= false then
		vim.keymap.set("t", keys.paste_register, function()
			local ok, char = pcall(vim.fn.getchar)
			if not ok or type(char) ~= "number" or char < 0 then
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

	digraph.setup(keys.digraph)

	map({ "n", "t" }, keys.pane_left, function() panes.navigate(-1) end, { noremap = true })
	map({ "n", "t" }, keys.pane_right, function() panes.navigate(1) end, { noremap = true })
	map({ "n", "t" }, keys.vsplit, api.vsplit, { noremap = true })
	map({ "n", "t" }, keys.last_pane, panes.goto_last, { noremap = true })
	map({ "n", "t" }, keys.last_tab, function()
		local prev_idx = vim.t.term_prev_tab_idx
		if not prev_idx then
			return
		end
		local tabs = state.get_tabs()
		if prev_idx < 1 or prev_idx > #tabs then
			return
		end
		if prev_idx == (vim.t.term_tab_idx or 1) then
			return
		end
		if not state.is_term_open() then
			return
		end
		window.switch_to_tab(prev_idx)
	end, { noremap = true })

	if keys.wincmd ~= false then
		local function key_match(c, ...)
			local trans = vim.fn.keytrans(c)
			for _, name in ipairs({ ... }) do
				-- Exact match
				if trans == name then return true end
				-- Case-insensitive match for modified keys only (<C-S-H> matches <C-S-h>)
				if trans:match("^<") and name:match("^<") and trans:lower() == name:lower() then
					return true
				end
			end
			return false
		end

		local function term_wincmd()
			local count = 0

			while true do
				local ok, c = pcall(vim.fn.getcharstr)
				if not ok or c == "" then
					return
				end

				if c >= "0" and c <= "9" then
					count = count * 10 + tonumber(c)
				else
					if count == 0 then
						count = 1
					end

					if key_match(c, "w", "<C-S-w>") then
						panes.cycle(count > 1 and count or nil)
					elseif key_match(c, "v", "<C-S-v>") then
						api.vsplit()
					elseif key_match(c, "h", "<C-S-h>") then
						panes.navigate(-1, count)
					elseif key_match(c, "j", "<NL>", "<S-NL>", "<C-j>", "<C-S-j>") then
						if not config.is_float_mode() then panes.native_wincmd("j", count) end
					elseif key_match(c, "k", "<C-k>", "<C-S-k>") then
						if not config.is_float_mode() then panes.native_wincmd("k", count) end
					elseif key_match(c, "l", "<C-S-l>") then
						panes.navigate(1, count)
					elseif c == ">" then
						panes.resize(count)
					elseif c == "<" then
						panes.resize(-count)
					elseif key_match(c, "H", "<S-H>") then
						local tab = state.get_current_tab()
						if tab then
							panes.move_to(1)
						end
					elseif key_match(c, "L", "<S-L>") then
						local tab = state.get_current_tab()
						if tab then
							panes.move_to(#tab.bufs)
						end
					elseif key_match(c, "r", "<C-R>", "<C-S-R>") then
						panes.rotate(1)
					elseif key_match(c, "R", "<S-R>") then
						panes.rotate(-1)
					elseif c == "=" then
						float_layout.equalize_panes()
					elseif key_match(c, "p", "<C-S-p>") then
						panes.goto_previous()
					elseif key_match(c, "c", "<C-S-c>") then
						api.delete()
					elseif key_match(c, "<CR>", "<C-S-CR>") and count > 1 then
						vim.t.term_height = count
						local wins = vim.t.term_winids or {}
						if not config.is_float_mode() and #wins > 0 and state.win_valid(wins[1]) then
							vim.api.nvim_win_call(wins[1], function()
								vim.api.nvim_win_set_height(0, count)
							end)
						end
					end
					return
				end
			end
		end

		map({ "n", "t" }, keys.wincmd, term_wincmd, { noremap = true })
	end

	-- <C-w> overrides for terminal panes (normal mode)
	local function nmap_cw(suffix, action)
		vim.keymap.set({ "n" }, "<C-w>" .. suffix, function()
			if state.is_in_term_window() then
				action()
			else
				local fallback = vim.api.nvim_replace_termcodes("<C-w>" .. suffix, true, true, true)
				vim.api.nvim_feedkeys(fallback, "n", false)
			end
		end, { noremap = true })
	end

	local cw_actions = {
		{ { "w", "<C-w>" }, function() panes.cycle(vim.v.count > 0 and vim.v.count or nil) end },
		{ { "h", "<C-h>" }, function() panes.navigate(-1, vim.v.count1) end },
		{ { "j", "<C-j>" }, function() if not config.is_float_mode() then panes.native_wincmd("j", vim.v.count1) end end },
		{ { "k", "<C-k>" }, function() if not config.is_float_mode() then panes.native_wincmd("k", vim.v.count1) end end },
		{ { "l", "<C-l>" }, function() panes.navigate(1, vim.v.count1) end },
		{ { ">" },          function() panes.resize(vim.v.count1) end },
		{ { "<lt>" },       function() panes.resize(-vim.v.count1) end },
		{ { "=" },          float_layout.equalize_panes },
		{ { "p", "<C-p>" }, panes.goto_previous },
		{ { "c", "<C-c>" }, api.delete },
		{ { "v", "<C-v>" }, api.vsplit },
		{ { "H" }, function()
			local g = state.get_current_tab(); if g then panes.move_to(1) end
		end },
		{ { "L" }, function()
			local g = state.get_current_tab(); if g then panes.move_to(#g.bufs) end
		end },
		{ { "r", "<C-r>" }, function() panes.rotate(1) end },
		{ { "R" },          function() panes.rotate(-1) end },
	}

	for _, entry in ipairs(cw_actions) do
		for _, suffix in ipairs(entry[1]) do
			nmap_cw(suffix, entry[2])
		end
	end
end

return M
