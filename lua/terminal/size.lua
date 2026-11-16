-- Dimension syntax shared by the Lua API, Ex command and session metadata.
local M = {}

local function dimension(value)
	if type(value) == "number" then
		return value >= 1 and value < math.huge and value == math.floor(value)
	end
	if type(value) == "string" and value:match("^%d+%%$") then
		local percent = tonumber(value:sub(1, -2))
		return percent >= 1 and percent <= 100
	end
	return false
end

function M.validate(opts)
	if opts == nil then return {} end
	if type(opts) ~= "table" then return nil, "Size must be a table with width and/or height" end
	for key, value in pairs(opts) do
		if key ~= "width" and key ~= "height" then return nil, "Unknown size option: " .. tostring(key) end
		if not dimension(value) then return nil, key .. " must be a positive integer or 1%–100%" end
	end
	return vim.deepcopy(opts)
end

function M.parse(args)
	args = vim.trim(args)
	if args == "" then return {} end
	local width, height = args:match("^(%d+%%?)x(%d+%%?)$")
	if width then
		return M.validate({ width = tonumber(width) or width, height = tonumber(height) or height })
	end
	if args:match("^%d+%%?$") then return M.validate({ height = tonumber(args) or args }) end
	return nil, "Expected height or widthxheight (for example 24, 50%, or 120x24)"
end

function M.available(floating)
	local tabline = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)) and 1 or 0
	local border = 0
	if floating then
		local configured = require("terminal.config").get_float_config().border
		border = configured and configured ~= "none" and 2 or 0
	end
	local reserved = floating and border or (2 + (vim.o.laststatus > 0 and 1 or 0))
	return vim.o.columns - border, math.max(0, vim.o.lines - vim.o.cmdheight - tabline - reserved), tabline
end

function M.resolve(value, available)
	local resolved = type(value) == "number" and value or math.max(1, math.floor(available * tonumber(value:sub(1, -2)) / 100))
	return math.min(resolved, available)
end

return M
