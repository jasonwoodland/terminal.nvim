-- Optional Telescope integration. No Telescope modules load during setup().
local M = {}

local function source_topline(buf)
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == buf then
			return vim.fn.getwininfo(win)[1].topline
		end
	end
	local top = vim.b[buf].terminal_preview_topline or 1
	local count = vim.b[buf].terminal_preview_line_count
	if count and vim.b[buf].terminal_preview_following then
		top = top + vim.api.nvim_buf_line_count(buf) - count
	end
	return math.max(1, top)
end

local function terminal_previewer()
	local current, timer
	local function valid(view)
		return view and vim.api.nvim_buf_is_valid(view.source)
			and vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_buf_is_valid(view.buf)
			and vim.api.nvim_win_get_buf(view.win) == view.buf
	end
	local function set_view(view, saved)
		vim.api.nvim_win_call(view.win, function() vim.fn.winrestview(saved) end)
	end
	local function refresh()
		local view = current
		if not valid(view) or not view.ready then return end
		local saved = vim.api.nvim_win_call(view.win, vim.fn.winsaveview)
		if saved.topline ~= view.top then view.manual = true end
		local tick = vim.api.nvim_buf_get_changedtick(view.source)
		local top = math.min(source_topline(view.source), vim.api.nvim_buf_line_count(view.source))
		if tick == view.tick and (view.manual or top == view.top) then return end
		if tick ~= view.tick then
			vim.api.nvim_buf_set_lines(view.buf, 0, -1, false,
				vim.api.nvim_buf_get_lines(view.source, 0, -1, false))
			view.tick = tick
		end
		if not view.manual then saved = { topline = top, lnum = top, col = 0, leftcol = 0, skipcol = 0 } end
		set_view(view, saved)
		view.top = vim.fn.getwininfo(view.win)[1].topline
	end
	return require("telescope.previewers").new_buffer_previewer({
		title = "Terminal Output",
		teardown = function()
			current = nil
			if timer then timer:stop(); timer:close(); timer = nil end
		end,
		define_preview = function(self, entry)
			current = nil
			if not vim.api.nvim_buf_is_valid(entry.bufnr) then return end
			local lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
			local view = {
				source = entry.bufnr, win = self.state.winid, buf = self.state.bufnr,
				top = math.min(source_topline(entry.bufnr), #lines),
				tick = vim.api.nvim_buf_get_changedtick(entry.bufnr),
			}
			current = view
			vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
			-- Wait for Telescope's buffer installation and preview-loaded hooks.
			vim.schedule(function()
				vim.schedule(function()
					if current ~= view or not valid(view) then return end
					local wo = vim.wo[view.win]
					wo.number = false
					wo.relativenumber = false
					wo.signcolumn = "no"
					wo.foldcolumn = "0"
					wo.statuscolumn = ""
					wo.scrolloff = 0
					set_view(view, { topline = view.top, lnum = view.top, col = 0, leftcol = 0, skipcol = 0 })
					view.ready = true
					if not timer then
						timer = assert(vim.uv.new_timer())
						timer:start(50, 50, vim.schedule_wrap(refresh))
					end
				end)
			end)
		end,
	})
end

function M.terminals(opts)
	opts = opts or {}
	local terminal = require("terminal")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local conf = require("telescope.config").values
	return require("telescope.pickers").new(opts, {
		prompt_title = "Terminals",
		finder = require("telescope.finders").new_table({
			results = terminal.list(),
			entry_maker = function(item)
				local label = ("%d:%d:%d  %s"):format(item.tabnr, item.tab_index, item.pane_index,
					item.title:gsub("%c", " "))
				return {
					value = item, bufnr = item.bufnr, filename = vim.api.nvim_buf_get_name(item.bufnr),
					display = label, ordinal = label,
				}
			end,
		}),
		sorter = conf.generic_sorter(opts),
		previewer = terminal_previewer(),
		attach_mappings = function(prompt_bufnr)
			local function select()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				if selection then
					local ok, err = terminal.focus(selection.value.bufnr)
					if not ok then vim.notify(err, vim.log.levels.WARN) end
				end
			end
			-- Every selection action navigates; none opens a duplicate buffer
			-- in the editor, a new split, or a new Vim tab.
			for _, name in ipairs({ "select_default", "select_horizontal", "select_vertical", "select_tab" }) do
				actions[name]:replace(select)
			end
			return true
		end,
	}):find()
end

return M
