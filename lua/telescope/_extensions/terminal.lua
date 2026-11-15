return require("telescope").register_extension({
	exports = {
		terminals = require("terminal.telescope").terminals,
	},
})
