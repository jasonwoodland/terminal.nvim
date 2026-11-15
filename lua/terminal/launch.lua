-- Validate and capture launch settings before changing the workspace.
local M = {}

function M.normalize(opts)
	assert(opts == nil or type(opts) == "table", "terminal launch options must be a table")
	opts = opts or {}
	local allowed = { cmd = true, cwd = true, env = true, name = true }
	for key in pairs(opts) do assert(allowed[key], "unknown terminal launch option: " .. tostring(key)) end
	local cmd = opts.cmd
	if cmd == nil then cmd = vim.env.SHELL or vim.o.shell end
	if type(cmd) == "string" then
		assert(cmd:match("%S") and not cmd:find("\0", 1, true), "cmd must be a nonempty command")
	else
		assert(type(cmd) == "table" and vim.islist(cmd) and #cmd > 0, "cmd must be a string or argument list")
		for i, arg in ipairs(cmd) do
			assert(type(arg) == "string" and not arg:find("\0", 1, true) and (i > 1 or arg ~= ""),
				"cmd arguments must be strings, with a nonempty program")
		end
	end
	local cwd = opts.cwd
	assert(cwd == nil or (type(cwd) == "string" and cwd ~= "" and not cwd:find("\0", 1, true)),
		"cwd must be a directory path")
	cwd = cwd and vim.fn.fnamemodify(vim.fn.expand(cwd), ":p") or vim.fn.getcwd()
	assert(vim.fn.isdirectory(cwd) == 1, "terminal cwd does not exist: " .. cwd)
	assert(opts.env == nil or type(opts.env) == "table", "env must be a table")
	for key, value in pairs(opts.env or {}) do
		assert(type(key) == "string" and key ~= "" and not key:find("=", 1, true) and not key:find("\0", 1, true),
			"invalid environment variable name")
		assert(type(value) == "string" and not value:find("\0", 1, true), "environment values must be strings")
	end
	local name = opts.name
	assert(name == nil or (type(name) == "string" and not name:find("%c")), "name must be a string without control characters")
	if name then name = vim.trim(name) end
	return { cmd = vim.deepcopy(cmd), cwd = cwd, env = vim.deepcopy(opts.env or {}), name = name }
end

return M
