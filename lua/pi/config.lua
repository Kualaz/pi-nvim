local M = {}

M.options = {
	socket_path = nil,
	sockets_dir = "/tmp/pi-nvim-sockets",
	request_timeout_ms = 5000,
	events = true,
}

function M.setup(opts)
	local merged = vim.tbl_deep_extend("force", M.options, opts or {})

	for key in pairs(M.options) do
		M.options[key] = nil
	end

	for key, value in pairs(merged) do
		M.options[key] = value
	end

	return M.options
end

return M
