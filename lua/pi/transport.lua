local uv = vim.uv or vim.loop

local config = require("pi.config")
local util = require("pi.util")

local M = {}

local function socket_from_info_path(info_path)
	local socket_path = info_path:gsub("%.info$", "")
	return socket_path
end

local function current_working_directory()
	local ok, cwd = pcall(vim.fn.getcwd)
	if ok and type(cwd) == "string" and cwd ~= "" then
		return cwd
	end
	return uv.cwd()
end

local function directory_parts(directory)
	if type(directory) ~= "string" or directory == "" or directory == "?" then
		return nil, nil
	end

	local normalized = vim.fs.normalize(directory)
	local realpath = uv.fs_realpath(normalized)
	if realpath then
		normalized = vim.fs.normalize(realpath)
	end
	local root = normalized:sub(1, 1) == "/" and "/" or "."
	local parts = {}
	for part in normalized:gmatch("[^/]+") do
		table.insert(parts, part)
	end
	return root, parts
end

--- Count path-tree hops between two directories.
--- @param from string
--- @param to string
--- @return number
function M.directory_distance(from, to)
	local from_root, from_parts = directory_parts(from)
	local to_root, to_parts = directory_parts(to)
	if not from_parts or not to_parts or from_root ~= to_root then
		return math.huge
	end

	local common = 0
	local limit = math.min(#from_parts, #to_parts)
	while common < limit and from_parts[common + 1] == to_parts[common + 1] do
		common = common + 1
	end

	return (#from_parts - common) + (#to_parts - common)
end

--- Find live Pi sessions ordered by directory distance from Neovim's cwd.
--- Newer sessions sort first when their distance is equal.
--- @param opts { cwd: string }|nil
--- @return table[]
function M.get_sessions(opts)
	opts = opts or {}
	local cwd = opts.cwd or current_working_directory()
	local pattern = config.options.sockets_dir .. "/*.info"
	local ok, files = pcall(vim.fn.glob, pattern, false, true)
	if not ok or not files then
		return {}
	end

	local sessions = {}
	for _, info_path in ipairs(files) do
		local info = util.read_json(info_path)
		local socket = socket_from_info_path(info_path)
		local stat = util.fs_stat(socket)
		if info and stat then
			local session_cwd = info.cwd or "?"
			table.insert(sessions, {
				cwd = session_cwd,
				distance = M.directory_distance(cwd, session_cwd),
				pid = info.pid or "?",
				started_at = info.startedAt,
				socket = socket,
				mtime = stat.mtime and stat.mtime.sec or 0,
			})
		end
	end

	table.sort(sessions, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		if a.mtime ~= b.mtime then
			return a.mtime > b.mtime
		end
		return a.socket < b.socket
	end)

	return sessions
end

--- Resolve only the Pi bridge socket explicitly configured or selected in this Neovim instance.
--- Session discovery is handled by the finder so exact-cwd and newest sessions are never chosen silently.
--- @param opts { quiet: boolean }|nil
--- @return string|nil
function M.get_socket_path(opts)
	opts = opts or {}

	if not config.options.socket_path or config.options.socket_path == "" then
		return nil
	end
	if util.fs_stat(config.options.socket_path) then
		return config.options.socket_path
	end
	if not opts.quiet then
		util.notify("Configured Pi socket does not exist: " .. config.options.socket_path, vim.log.levels.WARN)
	end
	return nil
end

--- Send a raw JSON message to the Pi socket.
--- @param msg table
--- @param cb fun(err: string|nil, response: table|nil)|nil
function M.send_raw(msg, cb)
	local socket_path = M.get_socket_path({ quiet = true })
	if not socket_path then
		local err = "No Pi session selected. Submit a prompt or run :PiSessions to open the finder."
		util.notify(err, vim.log.levels.ERROR)
		if cb then
			cb(err, nil)
		end
		return
	end

	local client = uv.new_pipe(false)
	if not client then
		local err = "Failed to create Unix pipe"
		util.notify(err, vim.log.levels.ERROR)
		if cb then
			cb(err, nil)
		end
		return
	end

	local timer = uv.new_timer()
	local done = false

	local function close_handles()
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
		if client and not client:is_closing() then
			pcall(function()
				client:read_stop()
			end)
			client:close()
		end
	end

	local function finish(err, response)
		if done then
			return
		end
		done = true
		close_handles()
		if cb then
			vim.schedule(function()
				cb(err, response)
			end)
		end
	end

	if timer then
		timer:start(config.options.request_timeout_ms, 0, function()
			finish("Timed out waiting for Pi response", nil)
		end)
	end

	client:connect(socket_path, function(connect_err)
		if connect_err then
			finish("Failed to connect to Pi: " .. connect_err, nil)
			return
		end

		client:write(vim.json.encode(msg) .. "\n")

		local buffer = ""
		client:read_start(function(read_err, data)
			if read_err then
				finish(read_err, nil)
				return
			end

			if not data then
				finish("Pi closed the socket before sending a response", nil)
				return
			end

			buffer = buffer .. data
			local newline = buffer:find("\n", 1, true)
			if newline then
				local line = buffer:sub(1, newline - 1)
				local ok, response = pcall(vim.json.decode, line)
				if ok and response then
					finish(nil, response)
				else
					finish("Invalid response from Pi", nil)
				end
			end
		end)
	end)
end

return M
