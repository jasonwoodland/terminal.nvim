-- terminal.nvim: keymap registration

local M = {}

local config = require("terminal.config")
local state = require("terminal.state")
local mode = require("terminal.mode")
local window = require("terminal.window")
local float_layout = require("terminal.float_layout")
local panes = require("terminal.panes")
local digraph = require("terminal.digraph")
local paste = require("terminal.paste")
local utils = require("terminal.utils")

function M.setup(api)
	local keys = config.config.keys
	if keys == false then
		return
	end

	local function map(modes, key, action, opts)
		for _, lhs in ipairs(utils.key_list(key)) do
			vim.keymap.set(modes, lhs, action, opts or {})
		end
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

	for _, pattern in ipairs(utils.key_list(keys.go_to_tab)) do
		for i = 1, 9 do
			local key = pattern:format(i)
			if key ~= keys.last_notification then
				vim.keymap.set({ "n", "t" }, key, function()
					api.go_to(i)
				end, { noremap = true })
			end
		end
	end

	-- Notification mapping takes precedence over generated tab keys.
	map({ "n", "t" }, keys.last_notification, api.go_to_notification, { noremap = true })

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
		local target = vim.api.nvim_get_current_win()
		state.defer_view(state.capture_view(target), function()
			if vim.api.nvim_get_current_win() == target and vim.bo.buftype == "terminal" then
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

	for _, key in ipairs(utils.key_list(keys.paste_register)) do
		map("t", key, paste.register, { noremap = true, silent = true })
		map("t", key .. "=", paste.expression, { noremap = true, silent = true })
	end

	digraph.setup(keys.digraph)

	map({ "n", "t" }, keys.pane_left, function() panes.navigate("h") end, { noremap = true })
	map({ "n", "t" }, keys.pane_down, function() panes.navigate("j") end, { noremap = true })
	map({ "n", "t" }, keys.pane_up, function() panes.navigate("k") end, { noremap = true })
	map({ "n", "t" }, keys.pane_right, function() panes.navigate("l") end, { noremap = true })
	map({ "n", "t" }, keys.vsplit, api.vsplit, { noremap = true })
	map({ "n", "t" }, keys.split, api.hsplit, { noremap = true })
	map({ "n", "t" }, keys.break_to_tab, api.break_pane_to_tab, { noremap = true })
	map({ "n", "t" }, keys.last_pane, panes.goto_last, { noremap = true })
	map({ "n", "t" }, keys.last_tab, function()
		local prev_idx = state.previous_tab_index()
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
					local explicit_count = count > 0 and count or nil
					count = math.max(count, 1)

					if key_match(c, "w", "<C-S-w>") then
						panes.cycle(explicit_count)
					elseif key_match(c, "W", "<S-W>") then
						panes.cycle(explicit_count, true)
					elseif key_match(c, "v", "<C-S-v>") then
						api.vsplit()
					elseif key_match(c, "s", "<C-S-s>") then
						api.hsplit()
					elseif key_match(c, "h", "<C-S-h>") then
						panes.navigate("h", count)
					elseif key_match(c, "j", "<NL>", "<S-NL>", "<C-j>", "<C-S-j>") then
						panes.navigate("j", count)
					elseif key_match(c, "k", "<C-k>", "<C-S-k>") then
						panes.navigate("k", count)
					elseif key_match(c, "l", "<C-S-l>") then
						panes.navigate("l", count)
					elseif c == ">" then
						panes.resize(count, "w")
					elseif c == "<" then
						panes.resize(-count, "w")
					elseif c == "+" then
						panes.resize(count, "h")
					elseif c == "-" then
						panes.resize(-count, "h")
					elseif c == "_" then
						panes.set_size("h", explicit_count)
					elseif c == "|" then
						panes.set_size("w", explicit_count)
					elseif key_match(c, "H", "<S-H>") then
						panes.splitmove("left")
					elseif key_match(c, "L", "<S-L>") then
						panes.splitmove("right")
					elseif key_match(c, "K", "<S-K>") then
						panes.splitmove("top")
					elseif key_match(c, "J", "<S-J>") then
						panes.splitmove("bottom")
					elseif key_match(c, "x", "<C-S-x>") then
						panes.exchange(explicit_count)
					elseif key_match(c, "r", "<C-R>", "<C-S-R>") then
						panes.rotate(1, count)
					elseif key_match(c, "R", "<S-R>") then
						panes.rotate(-1, count)
					elseif c == "=" then
						float_layout.equalize_panes()
					elseif key_match(c, "p", "<C-S-p>") then
						panes.goto_previous()
					elseif key_match(c, "c", "<C-S-c>") then
						api.delete()
					elseif key_match(c, "t", "<C-S-t>") then
						api.break_pane_to_tab()
					elseif key_match(c, "<CR>", "<C-S-CR>") and explicit_count then
						window.set_drawer_height(count)
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
				local prefix = vim.v.count > 0 and tostring(vim.v.count) or ""
				vim.api.nvim_feedkeys(prefix .. fallback, "n", false)
			end
		end, { noremap = true })
	end

	local cw_actions = {
		{ { "w", "<C-w>" }, function() panes.cycle(vim.v.count > 0 and vim.v.count or nil) end },
		{ { "W" },          function() panes.cycle(vim.v.count > 0 and vim.v.count or nil, true) end },
		{ { "h", "<C-h>" }, function() panes.navigate("h", vim.v.count1) end },
		{ { "j", "<C-j>" }, function() panes.navigate("j", vim.v.count1) end },
		{ { "k", "<C-k>" }, function() panes.navigate("k", vim.v.count1) end },
		{ { "l", "<C-l>" }, function() panes.navigate("l", vim.v.count1) end },
		{ { ">" },          function() panes.resize(vim.v.count1, "w") end },
		{ { "<lt>" },       function() panes.resize(-vim.v.count1, "w") end },
		{ { "+" },          function() panes.resize(vim.v.count1, "h") end },
		{ { "-" },          function() panes.resize(-vim.v.count1, "h") end },
		{ { "_", "<C-_>" }, function() panes.set_size("h", vim.v.count > 0 and vim.v.count or nil) end },
		{ { "<Bar>" },      function() panes.set_size("w", vim.v.count > 0 and vim.v.count or nil) end },
		{ { "=" },          float_layout.equalize_panes },
		{ { "p", "<C-p>" }, panes.goto_previous },
		{ { "c", "<C-c>" }, api.delete },
		{ { "v", "<C-v>" }, api.vsplit },
		{ { "s", "<C-s>" }, api.hsplit },
		{ { "x", "<C-x>" }, function() panes.exchange(vim.v.count > 0 and vim.v.count or nil) end },
		{ { "H" },          function() panes.splitmove("left") end },
		{ { "L" },          function() panes.splitmove("right") end },
		{ { "K" },          function() panes.splitmove("top") end },
		{ { "J" },          function() panes.splitmove("bottom") end },
		{ { "T" },          api.break_pane_to_tab },
		{ { "r", "<C-r>" }, function() panes.rotate(1, vim.v.count1) end },
		{ { "R" },          function() panes.rotate(-1, vim.v.count1) end },
	}

	for _, entry in ipairs(cw_actions) do
		for _, suffix in ipairs(entry[1]) do
			nmap_cw(suffix, entry[2])
		end
	end

	-- vim's z{height}<CR> for terminal panes (normal mode). Digits followed
	-- by <CR> set the pane height; any other sequence (zz, zt, folds, plain
	-- z<CR>, counts) is replayed natively.
	vim.keymap.set("n", "z", function()
		local count = vim.v.count
		local prefix = count > 0 and tostring(count) or ""
		if not state.is_in_term_window() then
			vim.api.nvim_feedkeys(prefix .. "z", "n", false)
			return
		end
		local digits = ""
		while true do
			local ok, c = pcall(vim.fn.getcharstr)
			if not ok or c == "" then
				return
			end
			if c >= "0" and c <= "9" then
				digits = digits .. c
			elseif (c == "\r" or c == "\n") and #digits > 0 then
				panes.set_height(tonumber(digits))
				return
			else
				vim.api.nvim_feedkeys(prefix .. "z" .. digits .. c, "n", false)
				return
			end
		end
	end, { noremap = true })
end

return M
