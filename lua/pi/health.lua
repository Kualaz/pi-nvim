local config = require("pi.config")
local transport = require("pi.transport")
local util = require("pi.util")

local M = {}

local health = vim.health or {}

local function report(kind, ...)
	local fn = health[kind]
	if fn then
		fn(...)
		return
	end

	local legacy = ({
		start = "report_start",
		ok = "report_ok",
		warn = "report_warn",
		error = "report_error",
		info = "report_info",
	})[kind]
	if legacy and health[legacy] then
		health[legacy](...)
	end
end

function M.check()
	report("start", "pi-nvim")

	if vim.fn.has("nvim-0.9") == 1 then
		report("ok", "Neovim version supports required Lua APIs")
	else
		report("warn", "Neovim 0.9+ is recommended")
	end

	if util.fs_stat(config.options.sockets_dir) then
		report("ok", "Socket directory exists: " .. config.options.sockets_dir)
	else
		report("warn", "Socket directory not found: " .. config.options.sockets_dir)
	end

	local sessions = transport.get_sessions()
	if #sessions > 0 then
		report("ok", string.format("Found %d Pi session(s)", #sessions))
	else
		report("warn", "No Pi session manifests found")
	end

	local socket_path = transport.get_socket_path({ quiet = true })
	if socket_path then
		report("ok", "Selected Pi socket: " .. socket_path)
	elseif #sessions > 0 then
		report("warn", "No Pi session selected yet. Submit a prompt or run :PiSessions to open the finder.")
	else
		report("warn", "No Pi socket available. Start Pi with the pi-nvim extension loaded.")
	end

	if config.options.events then
		report("ok", "File-change event subscription is enabled")
	else
		report("info", "File-change event subscription is disabled")
	end
end

return M
