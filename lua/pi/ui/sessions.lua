local config = require("pi.config")
local events = require("pi.events")
local transport = require("pi.transport")
local util = require("pi.util")

local M = {}

--- Open the session finder and remember the selected socket for this Neovim instance.
--- @param opts { on_select: fun(session: table|nil)|nil }|nil
function M.select_session(opts)
	opts = opts or {}
	local sessions = transport.get_sessions()
	if #sessions == 0 then
		util.notify("No Pi sessions found", vim.log.levels.INFO)
		if opts.on_select then
			opts.on_select(nil)
		end
		return
	end

	local current = transport.get_socket_path({ quiet = true })
	vim.ui.select(sessions, {
		prompt = "Pi sessions (nearest first):",
		format_item = function(session)
			local marker = current == session.socket and "●" or "○"
			local started = util.short_time(session.started_at)
			local time_suffix = started ~= "" and (", started " .. started) or ""
			local distance = session.distance == math.huge and "distance unknown"
				or string.format("%d %s", session.distance, session.distance == 1 and "hop" or "hops")
			return string.format("%s %s [%s, pid %s%s]", marker, session.cwd, distance, session.pid, time_suffix)
		end,
	}, function(session)
		if not session then
			if opts.on_select then
				opts.on_select(nil)
			end
			return
		end

		config.options.socket_path = session.socket
		events.subscribe_events({ force = true, quiet = true })
		util.notify(string.format("Connected to Pi at %s [pid %s]", session.cwd, session.pid), vim.log.levels.INFO)
		if opts.on_select then
			opts.on_select(session)
		end
	end)
end

function M.list_sessions()
	M.select_session()
end

return M
