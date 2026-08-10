local uv = vim.uv or vim.loop

local config = require("pi.config")
local transport = require("pi.transport")
local util = require("pi.util")

local M = {}

local event_client = nil
local event_socket_path = nil
local event_connecting = false
local event_buffer = ""

local function close_event_client()
	if event_client and not event_client:is_closing() then
		pcall(function()
			event_client:read_stop()
		end)
		event_client:close()
	end
	event_client = nil
	event_socket_path = nil
	event_connecting = false
	event_buffer = ""
end

local function handle_bridge_event(payload)
	if payload.event ~= "file.changed" then
		return
	end

	vim.schedule(function()
		pcall(vim.cmd, "checktime")
	end)
end

function M.subscribe_events(opts)
	opts = opts or {}
	if not config.options.events then
		return
	end

	local socket_path = transport.get_socket_path({ quiet = true })
	if not socket_path then
		if not opts.quiet then
			util.notify("No Pi session found for event subscription", vim.log.levels.WARN)
		end
		return
	end

	if opts.force then
		close_event_client()
	elseif event_client and event_socket_path == socket_path and not event_client:is_closing() then
		return
	elseif event_connecting then
		return
	else
		close_event_client()
	end

	event_connecting = true
	event_socket_path = socket_path
	event_buffer = ""
	event_client = uv.new_pipe(false)
	if not event_client then
		event_connecting = false
		if not opts.quiet then
			util.notify("Failed to create Pi event pipe", vim.log.levels.ERROR)
		end
		return
	end

	local client = event_client
	client:connect(socket_path, function(connect_err)
		if connect_err then
			if event_client == client then
				close_event_client()
			end
			if not opts.quiet then
				util.notify("Failed to subscribe to Pi events: " .. connect_err, vim.log.levels.WARN)
			end
			return
		end

		if event_client ~= client then
			return
		end

		event_connecting = false
		client:write(vim.json.encode({ type = "subscribe", events = { "file.changed" } }) .. "\n")
		client:read_start(function(read_err, data)
			if read_err or not data then
				if event_client == client then
					close_event_client()
				end
				return
			end

			event_buffer = event_buffer .. data
			while true do
				local newline = event_buffer:find("\n", 1, true)
				if not newline then
					break
				end

				local line = event_buffer:sub(1, newline - 1)
				event_buffer = event_buffer:sub(newline + 1)
				if line ~= "" then
					local ok, payload = pcall(vim.json.decode, line)
					if ok and payload then
						if payload.type == "event" then
							handle_bridge_event(payload)
						elseif payload.ok == false and not opts.quiet then
							util.notify("Pi event subscription failed: " .. (payload.error or "unknown"), vim.log.levels.WARN)
						end
					end
				end
			end
		end)
	end)
end

M.subscribe = M.subscribe_events
M.close = close_event_client
M.close_event_client = close_event_client

return M
